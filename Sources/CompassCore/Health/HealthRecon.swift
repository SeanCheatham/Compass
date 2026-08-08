import Foundation

/// Deterministic health recon: packages, surfaces, baseline `cargo test` via VM bash.
public enum HealthRecon {
  public static func run(
    repoURL: URL,
    bashRunner: AgentBashRunner,
    timeout: TimeInterval = 600,
    onLive: (@Sendable (LiveEvent) -> Void)? = nil
  ) async -> HealthReconResult {
    var notes: [String] = []
    var packageNames: [String] = []
    var surfaces = HealthSurfaceInventory()

    let metaCommand =
      "cargo metadata --no-deps --format-version 1 2>/dev/null | head -c 200000"
    let meta = await runMirroredBash(
      command: metaCommand,
      label: "health recon metadata",
      repoURL: repoURL,
      bashRunner: bashRunner,
      timeout: min(timeout, 120),
      onLive: onLive
    )
    if let meta, meta.exitCode == 0 {
      let parsed = parseMetadata(from: meta.stdout)
      packageNames = parsed.names
      surfaces.binaries = parsed.binaries
      surfaces.libraries = parsed.libraries
    } else {
      notes.append("cargo metadata failed or unavailable")
    }

    surfaces.docPaths = discoverDocPaths(in: repoURL)

    let testCommand =
      "cargo test --workspace -- --nocapture 2>&1 | tee /tmp/compass-health-baseline.log | tail -c 80000"
    let testResult = await runMirroredBash(
      command: testCommand,
      label: "health recon baseline",
      repoURL: repoURL,
      bashRunner: bashRunner,
      timeout: timeout,
      onLive: onLive
    )
    let baseline: HealthTestRunSummary
    if let testResult {
      let combined = testResult.stdout + testResult.stderr
      baseline = HealthTestRunSummary(
        success: testResult.exitCode == 0,
        passed: countMatches(#"(\d+) passed"#, in: combined),
        failed: countMatches(#"(\d+) failed"#, in: combined),
        ignored: countMatches(#"(\d+) ignored"#, in: combined),
        stdout: String(testResult.stdout.suffix(20_000)),
        stderr: String(testResult.stderr.suffix(8_000))
      )
      if !baseline.success {
        notes.append("baseline cargo test failed — treat as health signal")
      }
    } else {
      baseline = HealthTestRunSummary(success: false, stderr: "baseline cargo test did not run")
      notes.append("baseline cargo test did not run")
    }

    var targets: [HealthRankedTarget] = []
    for name in packageNames.prefix(12) {
      targets.append(
        HealthRankedTarget(
          path: "crates/\(name)/src",
          functionHint: nil,
          reason: "package \(name)",
          priority: 1
        ))
    }
    for doc in surfaces.docPaths.prefix(6) {
      targets.append(
        HealthRankedTarget(path: doc, reason: "doc surface", priority: 2)
      )
    }
    if targets.isEmpty {
      targets.append(
        HealthRankedTarget(path: "src", reason: "default crate root", priority: 1))
    }

    return HealthReconResult(
      packageNames: packageNames,
      baselineTests: baseline,
      rankedTargets: targets,
      surfaces: surfaces,
      notes: notes
    )
  }

  private static func discoverDocPaths(in repoURL: URL) -> [String] {
    var paths: [String] = []
    let fm = FileManager.default
    for name in ["README.md", "README", "README.txt", "CHANGELOG.md"] {
      let url = repoURL.appending(path: name)
      if fm.fileExists(atPath: url.path) {
        paths.append(name)
      }
    }
    let docs = repoURL.appending(path: "docs")
    if let enumerator = fm.enumerator(
      at: docs,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) {
      var count = 0
      for case let fileURL as URL in enumerator {
        guard count < 24 else { break }
        let rel = fileURL.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        if rel.hasSuffix(".md") {
          paths.append(rel)
          count += 1
        }
      }
    }
    return paths
  }

  private static func runMirroredBash(
    command: String,
    label: String,
    repoURL: URL,
    bashRunner: AgentBashRunner,
    timeout: TimeInterval,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) async -> ProcessResult? {
    let correlationID = UUID().uuidString
    let timeoutMs = Int(timeout * 1000)
    onLive?(
      LiveEvent(
        level: .raw,
        text: label,
        detail: "\(command) (macOS VM, timeout \(timeoutMs)ms)",
        kind: .command,
        status: .running,
        correlationID: correlationID,
        metadata: [
          "tool": "bash",
          "command": command,
          "timeoutMs": "\(timeoutMs)",
          "phase": AgentPhase.health.rawValue,
        ],
        payload: .bash(
          command: command,
          cwd: "/workspace",
          output: nil,
          isError: nil
        )
      )
    )

    do {
      let result = try await bashRunner.run(
        command: command,
        workingDirectory: repoURL,
        timeout: timeout
      )
      let failed = result.exitCode != 0
      let combined = result.stdout + result.stderr
      let capped = AgentExecutor.capTail(combined, bytes: AgentExecutor.payloadMaxTerminalBytes)
      onLive?(
        LiveEvent(
          level: failed ? .error : .success,
          text: label,
          detail: failed
            ? "exit \(result.exitCode)\n\(String(combined.suffix(2000)))"
            : (combined.isEmpty ? "exit 0" : String(combined.suffix(2000))),
          kind: .command,
          status: failed ? .failed : .completed,
          correlationID: correlationID,
          metadata: [
            "tool": "bash",
            "command": command,
            "exitCode": "\(result.exitCode)",
            "isError": failed ? "true" : "false",
            "phase": AgentPhase.health.rawValue,
          ],
          payload: .bash(
            command: command,
            cwd: "/workspace",
            output: capped.isEmpty ? "exit \(result.exitCode)" : capped,
            isError: failed
          )
        )
      )
      return result
    } catch {
      onLive?(
        LiveEvent(
          level: .error,
          text: label,
          detail: error.localizedDescription,
          kind: .command,
          status: .failed,
          correlationID: correlationID,
          metadata: [
            "tool": "bash",
            "command": command,
            "isError": "true",
            "phase": AgentPhase.health.rawValue,
          ],
          payload: .bash(
            command: command,
            cwd: "/workspace",
            output: error.localizedDescription,
            isError: true
          )
        )
      )
      return nil
    }
  }

  private static func parseMetadata(from metadataJSON: String) -> (
    names: [String], binaries: [String], libraries: [String]
  ) {
    guard let data = metadataJSON.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let packages = obj["packages"] as? [[String: Any]]
    else { return ([], [], []) }
    var names: [String] = []
    var binaries: [String] = []
    var libraries: [String] = []
    for package in packages {
      if let name = package["name"] as? String {
        names.append(name)
      }
      guard let targets = package["targets"] as? [[String: Any]] else { continue }
      for target in targets {
        let name = target["name"] as? String ?? ""
        let kinds = target["kind"] as? [String] ?? []
        if kinds.contains("bin") { binaries.append(name) }
        if kinds.contains("lib") || kinds.contains("rlib") { libraries.append(name) }
      }
    }
    return (names.sorted(), Array(Set(binaries)).sorted(), Array(Set(libraries)).sorted())
  }

  private static func countMatches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
      let r = Range(match.range(at: 1), in: text)
    else { return 0 }
    return Int(text[r]) ?? 0
  }
}
