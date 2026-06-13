import Testing

@testable import CompassCore

@Suite("VerifyFailureInsight")
struct VerifyFailureInsightTests {
  @Test
  func compilerErrorsWinOverCoverageMentions() {
    let detail = """
      > tessera verify . --json
      tessera typecheck: src/display-name.tes:2:1: syntax error: expected expression.
      """
    let insight = VerifyFailureInsight(
      detail: detail,
      metadata: "command=tessera verify . --json exitCode=2"
    )

    #expect(insight.kind == .buildFailure)
    #expect(insight.repairDetail.contains("syntax error"))
  }

  @Test
  func missingTesseraCommandIsMissingToolFailure() {
    let detail = """
      zsh: command not found: tessera
      """
    let insight = VerifyFailureInsight(
      detail: detail,
      metadata: "command=tessera verify . --json exitCode=127"
    )

    #expect(insight.kind == .missingTool)
    #expect(insight.inspectDetail.contains("could not start cleanly"))
    #expect(insight.repairDetail.contains("missing tool"))
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
