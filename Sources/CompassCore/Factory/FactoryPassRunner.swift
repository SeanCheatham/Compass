import Foundation

/// Shared factory pass helpers used by the UI (`CompassProject`) and headless
/// (`HeadlessCompassRunner`) adapters.
///
/// Hosts still own agent execution, session recording, pause/stop, and
/// `@Published` / event mapping. This type owns the pass policies and
/// post-verify gate sequence so both paths stay aligned.
public enum FactoryPassRunner {
  /// Resolve effective options from headless run flags.
  public static func options(from headless: HeadlessRunOptions) -> FactoryPassOptions {
    var options = FactoryPassOptions.headlessDefaults
    options.maxDevelopAttempts = headless.maxDevelopAttempts
    options.maxVerifyRepairAttempts = headless.maxVerifyRepairAttempts
    options.runCritic = headless.runCritic
    options.continueToDevelop = headless.runDevelop
    options.commitOnSuccess = headless.commitIterations
    options.macosFidelityCadence = headless.macosFidelityCadence
    return options
  }

  /// Cadence for headed macOS fidelity on this ship.
  public static func shouldEnableMacOSFidelity(
    state: PlanState,
    forceBeforeFullAudit: Bool = false,
    options: FactoryPassOptions = .uiDefaults
  ) -> Bool {
    let cadence =
      state.macosFidelityCadence
      ?? options.macosFidelityCadence
    let force = forceBeforeFullAudit && options.forceFidelityBeforeFullAudit
    return MacOSFidelityCadence.shouldEnableFidelity(
      successfulShipCount: state.successfulShipCount,
      cadence: cadence,
      force: force
    )
  }

  /// Runs the macOS product gate, optionally with headed fidelity enabled by cadence.
  public static func runMacOSVerifyIfNeeded(
    products: [GeneratedProduct],
    workingDirectory: URL,
    repoRoot: URL,
    workspace: CompassWorkspace,
    sessionNumber: Int,
    enableFidelity: Bool,
    timeout: TimeInterval = QualityCollectionTimeout.seconds()
  ) async -> (issue: String?, screenshotSaved: Bool) {
    guard GeneratedProducts.contains(products, .macos) else {
      return (nil, false)
    }

    let environment: [String: String] =
      enableFidelity
      ? MacOSFidelityCadence.environmentEnablingFidelity()
      : ProcessInfo.processInfo.environment

    let outcome = await MacOSVerifyGate.run(
      workingDirectory: workingDirectory,
      repoRoot: repoRoot,
      timeout: timeout,
      environment: environment
    )
    let result = outcome.result
    let combined = result.stdout + "\n" + result.stderr
    let fallbackNote = outcome.fallbackReason.map { " (VM unavailable: \($0))" } ?? ""
    _ = try? workspace.writeSessionAuditArtifact(
      session: sessionNumber,
      name: "macos-verify.log",
      kind: "log",
      contents: "$ \(GeneratedProjectQuality.macosVerifyCommand)\n\n" + combined,
      note: "macOS verify output (\(outcome.runtimeDescription)\(fallbackNote))"
        + (enableFidelity ? "; headed fidelity enabled." : ".")
    )
    let screenshotSaved = await MacOSUISmokeSupport.writeScreenshotAuditArtifact(
      workspace: workspace,
      session: sessionNumber,
      repoURL: workingDirectory
    ) != nil

    guard result.exitCode == 0 else {
      let tail = String(combined.suffix(4000))
      let issue = """
        [macos-verify] macOS verify `\(GeneratedProjectQuality.macosVerifyCommand)` on \(outcome.runtimeDescription)\(fallbackNote) exited with code \(result.exitCode). Output (tail):
        ```
        \(tail)
        ```
        """
      return (issue, screenshotSaved)
    }
    return (nil, screenshotSaved)
  }

  /// Record a successful Critic-approved ship and bump fidelity counter.
  public static func recordingSuccessfulShip(in state: PlanState) -> PlanState {
    var updated = state
    updated.successfulShipCount = max(0, state.successfulShipCount) + 1
    return updated
  }
}
