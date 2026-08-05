import Testing

@testable import CompassCore

@Suite("DevelopFailureInsight")
struct DevelopFailureInsightTests {
  @Test
  func missingResultFromSubmitEnvelope() {
    let insight = DevelopFailureInsight(
      detail: "Develop ended without a phase submit envelope."
    )
    #expect(insight.kind == .missingResult)
    #expect(insight.guideTitle.contains("Finish"))
    #expect(insight.repairDetail.contains("develop_submit"))
  }

  @Test
  func missingResultFromMaxIterations() {
    let insight = DevelopFailureInsight(detail: "Agent exceeded max iterations")
    #expect(insight.kind == .missingResult)
  }

  @Test
  func malformedToolCall() {
    let insight = DevelopFailureInsight(
      detail: "Tool outline had undecodable args: missing required field `path`"
    )
    #expect(insight.kind == .malformedToolCall)
    #expect(insight.repairDetail.contains("required fields"))
  }

  @Test
  func providerFailureFromMLX() {
    let insight = DevelopFailureInsight(detail: "Local model generation failed: mlx runtime error")
    #expect(insight.kind == .providerFailure)
    #expect(insight.repairTitle.contains("MLX"))
  }

  @Test
  func providerFailureFromStreamError() {
    let insight = DevelopFailureInsight(detail: "Chat completions stream failed")
    #expect(insight.kind == .providerFailure)
  }

  @Test
  func bareProviderWordDoesNotForceProviderFailure() {
    // Previously matched any detail containing "provider", which misclassified
    // unrelated tool/route wording.
    let insight = DevelopFailureInsight(
      detail: "Credential provider setting is unavailable for this route"
    )
    #expect(insight.kind == .generic)
  }

  @Test
  func genericFallback() {
    let insight = DevelopFailureInsight(detail: "Unexpected develop failure: disk full")
    #expect(insight.kind == .generic)
    #expect(insight.inspectDetail.contains("disk full"))
  }

  @Test
  func emptyDetailUsesFallbackCopy() {
    let insight = DevelopFailureInsight(detail: "")
    #expect(insight.kind == .generic)
    #expect(insight.inspectDetail == "Develop failed without captured detail.")
  }
}
