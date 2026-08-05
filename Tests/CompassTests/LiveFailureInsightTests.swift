import Testing

@testable import CompassCore

@Suite("LiveFailureInsight")
struct LiveFailureInsightTests {
  private func failedLine(text: String, detail: String? = nil) -> LiveLine {
    LiveLine(level: .error, text: text, detail: detail, status: .failed)
  }

  @Test
  func runtimeTransportMapsToRuntimeBridge() {
    let insight = LiveFailureInsight(
      line: failedLine(text: "bash failed", detail: "Runtime transport failed: connection reset")
    )
    #expect(insight?.kind == .runtimeBridge)
    #expect(insight?.badge == "Workspace")
  }

  @Test
  func vsockUnreachableMapsToRuntimeBridge() {
    let insight = LiveFailureInsight(
      line: failedLine(
        text: "Guest agent did not become reachable over vsock within 5 minutes."
      )
    )
    #expect(insight?.kind == .runtimeBridge)
  }

  @Test
  func bareTransportWordDoesNotForceRuntimeBridge() {
    // Previously matched any detail containing "transport", which misclassified
    // unrelated wording (e.g. networking libs or copy about data transport).
    let insight = LiveFailureInsight(
      line: failedLine(
        text: "Verify failed",
        detail: "HTTP transport layer returned 503 from the package registry"
      )
    )
    #expect(insight?.kind != .runtimeBridge)
  }

  @Test
  func providerFailureStillClassifiesMLX() {
    let insight = LiveFailureInsight(
      line: failedLine(text: "Local model generation failed", detail: "mlx runtime error")
    )
    #expect(insight?.kind == .providerFailure)
  }

  @Test
  func missingResultClassifiesSubmitEnvelope() {
    let insight = LiveFailureInsight(
      line: failedLine(text: "Develop ended without a phase submit envelope")
    )
    #expect(insight?.kind == .missingResult)
  }

  @Test
  func nonFailedLineReturnsNil() {
    let line = LiveLine(level: .info, text: "ok", status: .completed)
    #expect(LiveFailureInsight(line: line) == nil)
  }
}
