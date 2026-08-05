import Testing

@testable import CompassCore

@Suite("VerifyFailureInsight")
struct VerifyFailureInsightTests {
  @Test
  func compilerErrorsWinOverCoverageMentions() {
    let detail = """
      error[E0425]: cannot find value `missing` in this scope
       --> crates/core/src/lib.rs:16:1
      """
    let verify = GeneratedProjectQuality.standardVerifyCommand
    let insight = VerifyFailureInsight(detail: detail, metadata: "command=\(verify) exitCode=2")

    #expect(insight.kind == .buildFailure)
    #expect(insight.repairDetail.contains("concrete file, symbol, module, or syntax error"))
  }

  @Test
  func cargoToolchainFetchErrorsArePackageManagerBootstrapFailures() {
    let detail = """
      cargo install cargo-llvm-cov --locked
      error: failed to download from https://crates.io
      network: Error when performing the request
      """
    let insight = VerifyFailureInsight(
      detail: detail,
      metadata: "command=\(GeneratedProjectQuality.standardVerifyCommand) exitCode=1"
    )

    #expect(insight.kind == .packageManagerBootstrap)
    #expect(insight.inspectDetail.contains("before project tests could run"))
    #expect(insight.repairDetail.contains("Do not ask Develop to rewrite app code"))
  }

  @Test
  func rustExpectedTokenErrorsAreBuildFailuresNotTests() {
    // Previously matched bare "expected" as a test failure.
    let detail = """
      error: expected type, found `}`
       --> crates/core/src/lib.rs:12:1
      """
    let insight = VerifyFailureInsight(detail: detail, metadata: "exitCode=1")
    #expect(insight.kind == .buildFailure)
  }

  @Test
  func missingSourcePathIsNotMissingTool() {
    // Bare "No such file or directory" used to force missingTool even for
    // ordinary compile/path errors inside project sources.
    let detail = """
      error: couldn't read crates/core/src/missing.rs: No such file or directory (os error 2)
      """
    let insight = VerifyFailureInsight(detail: detail, metadata: "exitCode=1")
    #expect(insight.kind != .missingTool)
    #expect(insight.kind == .buildFailure)
  }

  @Test
  func commandNotFoundStillMissingTool() {
    let insight = VerifyFailureInsight(
      detail: "bash: cargo-llvm-cov: command not found",
      metadata: "exitCode=127"
    )
    #expect(insight.kind == .missingTool)
  }

  @Test
  func assertionFailuresAreTestFailures() {
    let detail = """
      thread 'cli_tests::prints_help' panicked at crates/cli/tests/cli.rs:20:5:
      assertion failed: `(left == right)`
      """
    let insight = VerifyFailureInsight(detail: detail, metadata: "exitCode=101")
    #expect(insight.kind == .testFailure)
  }

  @Test
  func coverageArtifactFailuresClassifyAsCoverage() {
    let detail = "failed to load profdata for llvm-cov report"
    let insight = VerifyFailureInsight(detail: detail, metadata: "exitCode=1")
    #expect(insight.kind == .coverage)
  }

  @Test
  func timeoutsClassifyAsTimeout() {
    let insight = VerifyFailureInsight(
      detail: "verify command timed out after 120s",
      metadata: nil
    )
    #expect(insight.kind == .timeout)
  }
}

@Suite("ClipboardHelpText")
struct ClipboardHelpTextTests {
  @Test
  func allUserFacingMatchesWiredConstants() {
    let wired = Set(ClipboardHelpText.allUserFacing)
    #expect(wired.count == ClipboardHelpText.allUserFacing.count)
    #expect(wired.contains(ClipboardHelpText.projectSnapshot))
    #expect(wired.contains(ClipboardHelpText.liveFailure))
    #expect(wired.contains(ClipboardHelpText.runtimeSettings))
    #expect(!wired.contains("Copy a concise setup note."))
  }
}
