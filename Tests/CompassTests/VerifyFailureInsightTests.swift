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
}
