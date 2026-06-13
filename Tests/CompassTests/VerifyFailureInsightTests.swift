import Testing

@testable import CompassCore

@Suite("VerifyFailureInsight")
struct VerifyFailureInsightTests {
  @Test
  func compilerErrorsWinOverCoverageMentions() {
    let detail = """
      > pnpm typecheck && pnpm test -- --coverage && pnpm build
      packages/core typecheck: src/index.ts(16,1): error TS1005: '}' expected.
      """
    let insight = VerifyFailureInsight(detail: detail, metadata: "command=pnpm verify exitCode=2")

    #expect(insight.kind == .buildFailure)
    #expect(insight.repairDetail.contains("syntax error"))
  }

  @Test
  func corepackFetchErrorsArePackageManagerBootstrapFailures() {
    let detail = """
      Preparing pnpm@9.15.4 for immediate activation...
      Internal Error: Error when performing the request to https://registry.npmjs.org/pnpm/-/pnpm-9.15.4.tgz
      """
    let insight = VerifyFailureInsight(detail: detail, metadata: "command=pnpm verify exitCode=1")

    #expect(insight.kind == .packageManagerBootstrap)
    #expect(insight.inspectDetail.contains("before project tests could run"))
    #expect(insight.repairDetail.contains("Do not ask Develop to rewrite app code"))
  }

  @Test
  func tesseraExpectedActualFailuresAreTestFailures() {
    let detail = """
      Tessera test display-name at tests/display-name.json: expected JSON "Grace!" but got "Ada!" (expected "Grace!", got "Ada!")
      """
    let insight = VerifyFailureInsight(
      detail: detail,
      metadata: "command=tessera verify . --json exitCode=1"
    )

    #expect(insight.kind == .testFailure)
    #expect(insight.inspectDetail.contains("display-name"))
  }
}
