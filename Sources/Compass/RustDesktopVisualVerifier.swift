import Foundation

struct RustDesktopVisualVerification: Equatable, Sendable {
  static let screenshotBeginMarker = "COMPASS_VISUAL_SCREENSHOT_BASE64_BEGIN"
  static let screenshotEndMarker = "COMPASS_VISUAL_SCREENSHOT_BASE64_END"

  static let discoveryCommand = """
    if [ -f Cargo.toml ] && [ -f crates/app-desktop/Cargo.toml ] && [ -f xtask/Cargo.toml ]; then
      echo PRESENT
    else
      echo MISSING
    fi
    """

  static let command = RustProjectScaffold.visualVerifyCommand

  static let requiresSharedVMRouteIssue =
    "[verify] Rust desktop visual verification requires the Shared VM route so build, launch, input, screenshot, and termination all happen inside the guest GUI session. The blessed Rust desktop scaffold was found, but this Verify attempt is not running in the Shared VM."

  static func isPresent(_ result: ProcessResult) -> Bool {
    result.exitCode == 0
      && result.stdout
        .split(whereSeparator: \.isNewline)
        .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "PRESENT" }
  }

  static func screenshotData(from output: String) -> Data? {
    guard
      let begin = output.range(of: screenshotBeginMarker),
      let end = output.range(of: screenshotEndMarker, range: begin.upperBound..<output.endIndex)
    else {
      return nil
    }
    let encoded = output[begin.upperBound..<end.lowerBound]
      .filter { !$0.isWhitespace }
    guard !encoded.isEmpty else { return nil }
    return Data(base64Encoded: String(encoded))
  }

  static func redactedOutput(_ output: String) -> String {
    guard
      let begin = output.range(of: screenshotBeginMarker),
      let end = output.range(of: screenshotEndMarker, range: begin.upperBound..<output.endIndex)
    else {
      return output
    }
    var redacted = output
    redacted.replaceSubrange(
      begin.lowerBound..<end.upperBound,
      with: "\(screenshotBeginMarker)\n<base64 screenshot omitted>\n\(screenshotEndMarker)"
    )
    return redacted
  }
}

@MainActor
extension CompassProject {
  func runRustDesktopVisualVerificationIfAvailable(
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int,
    attempt: Int
  ) async -> [String] {
    do {
      guard case .sharedVM = launchPlan.effectiveRoute else {
        guard RustProjectScaffold.isBlessedDesktopWorkspace(at: workingDirectory) else {
          return []
        }
        log(
          "Rust desktop visual verification failed: Shared VM route is required for Level 2 verification.",
          level: .error
        )
        return [RustDesktopVisualVerification.requiresSharedVMRouteIssue]
      }

      let discovery = try await runVerifyCommand(
        command: RustDesktopVisualVerification.discoveryCommand,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: 30,
        launchPlan: launchPlan
      )
      guard RustDesktopVisualVerification.isPresent(discovery) else {
        log("Rust desktop visual verification skipped: no blessed desktop scaffold.", level: .info)
        return []
      }

      log("Post-check: running Rust desktop visual verification.", level: .info)
      let startedAt = Date()
      let result = try await runVerifyCommand(
        command: RustDesktopVisualVerification.command,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: 120,
        launchPlan: launchPlan
      )
      let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
      recordRustDesktopVisualVerificationOutput(
        command: RustDesktopVisualVerification.command,
        result: result,
        sessionIndex: sessionIndex,
        attempt: attempt,
        durationMs: durationMs
      )

      let combinedOutput = result.stdout + "\n" + result.stderr
      guard result.exitCode == 0 else {
        let issue = """
          [verify] Rust desktop visual verification exited with code \(result.exitCode). Output (tail):
          ```
          \(tail(RustDesktopVisualVerification.redactedOutput(combinedOutput), max: 4000))
          ```
          """
        log("Rust desktop visual verification failed (exit \(result.exitCode)).", level: .error)
        return [issue]
      }
      guard RustDesktopVisualVerification.screenshotData(from: combinedOutput) != nil else {
        log("Rust desktop visual verification did not emit a screenshot artifact.", level: .error)
        return [
          "[verify] Rust desktop visual verification passed its process check but did not emit a screenshot artifact for audit."
        ]
      }

      log("Rust desktop visual verification passed.", level: .success)
      return []
    } catch {
      log(
        "Rust desktop visual verification failed: \(error.localizedDescription)",
        level: .error
      )
      return [
        "[verify] Rust desktop visual verification could not run: \(error.localizedDescription)"
      ]
    }
  }

  func recordRustDesktopVisualVerificationOutput(
    command: String,
    result: ProcessResult,
    sessionIndex: Int,
    attempt: Int,
    durationMs: Int
  ) {
    guard sessions.indices.contains(sessionIndex), let workspace else { return }
    let session = sessions[sessionIndex].session
    let combinedOutput = result.stdout + "\n" + result.stderr
    let redactedStdout = RustDesktopVisualVerification.redactedOutput(result.stdout)
    let contents = """
      Command:
      \(command)

      Exit code: \(result.exitCode)
      Duration: \(durationMs)ms

      [stdout]
      \(redactedStdout)

      [stderr]
      \(result.stderr)
      """

    do {
      let logURL = try workspace.writeSessionAuditArtifact(
        session: session,
        name: "rust-visual-verify-attempt-\(attempt).log",
        kind: "visual_verify_output",
        contents: contents,
        note: "Rust desktop visual verification output for attempt \(attempt)."
      )
      recordSessionAuditArtifactEvent(
        session: session,
        kind: "visual_verify_output_saved",
        artifactURL: logURL,
        note: "Saved Rust desktop visual verification output.",
        metadata: [
          "command": command,
          "attempt": "\(attempt)",
          "exitCode": "\(result.exitCode)",
          "durationMs": "\(durationMs)",
        ]
      )

      if let screenshot = RustDesktopVisualVerification.screenshotData(from: combinedOutput) {
        let screenshotURL = try workspace.writeSessionAuditArtifactData(
          session: session,
          name: "rust-desktop-visual-attempt-\(attempt).png",
          kind: "visual_screenshot",
          data: screenshot,
          note: "Rust desktop screenshot captured during visual verification attempt \(attempt)."
        )
        recordSessionAuditArtifactEvent(
          session: session,
          kind: "visual_screenshot_saved",
          artifactURL: screenshotURL,
          note: "Saved Rust desktop visual verification screenshot.",
          metadata: [
            "attempt": "\(attempt)",
            "exitCode": "\(result.exitCode)",
            "durationMs": "\(durationMs)",
          ]
        )
      }
    } catch {
      appendAuditEvent(
        kind: "visual_verify_output_save_failed",
        status: "failed",
        text: error.localizedDescription,
        metadata: [
          "command": command,
          "attempt": "\(attempt)",
          "exitCode": "\(result.exitCode)",
          "durationMs": "\(durationMs)",
        ]
      )
    }
  }
}
