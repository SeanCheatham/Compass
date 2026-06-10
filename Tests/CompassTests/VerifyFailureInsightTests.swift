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
}
