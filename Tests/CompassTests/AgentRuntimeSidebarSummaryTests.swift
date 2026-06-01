import Foundation
import Testing

@testable import Compass

struct AgentRuntimeSidebarSummaryTests {
  @Test
  func foundationModelsSummaryDoesNotLeakNetworkDefaults() {
    let summary = AgentRuntimeSidebarSummary(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: true
    )

    #expect(summary.lines.map(\.id) == ["text", "status", "model", "tools"])
    #expect(summary.lineValue("text") == "Foundation Models on-device")
    #expect(summary.lineValue("status") == "Text ready")
    #expect(summary.lineValue("model") == "Apple Intelligence system model")
    #expect(summary.lineValue("tools") == "Optional tools off")
    #expect(!summary.joinedText.contains("api.minimax.io"))
    #expect(!summary.joinedText.contains("MiniMax-M2.7"))
  }

  @Test
  func foundationModelsUnavailableSummaryNamesAppleIntelligence() {
    let summary = AgentRuntimeSidebarSummary(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: false
    )

    #expect(summary.lineValue("status") == "Apple Intelligence unavailable")
  }

  @Test
  func networkProviderSummaryIncludesEndpointModelAndMissingKeyStatus() throws {
    let summary = AgentRuntimeSidebarSummary(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        baseURL: try #require(URL(string: "https://api.openai.com/v1")),
        apiKey: " \n ",
        model: "gpt-4o"
      ),
      foundationModelsAvailable: true
    )

    #expect(summary.lines.map(\.id) == ["text", "status", "endpoint", "model", "tools"])
    #expect(summary.lineValue("text") == "OpenAI API")
    #expect(summary.lineValue("status") == "OpenAI API needs API key")
    #expect(summary.lineValue("endpoint") == "api.openai.com")
    #expect(summary.lineValue("model") == "gpt-4o")
  }

  @Test
  func optionalMediaSummaryDistinguishesReadyAndMissingKeys() throws {
    let summary = AgentRuntimeSidebarSummary(
      settings: AgentRuntimeSettings(
        textProvider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "mm-text",
        model: "MiniMax-M2.7",
        webSearchAssignment: CapabilityAssignment(
          provider: .minimaxToken,
          baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
          apiKey: "mm-search",
          model: ""
        ),
        imageAssignment: MediaAssignment(
          provider: .minimaxToken,
          baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
          apiKey: "mm-image",
          model: "image-01"
        ),
        audioAssignment: MediaAssignment(
          provider: .minimaxToken,
          baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
          apiKey: "",
          model: "speech-02-hd"
        )
      ),
      foundationModelsAvailable: false
    )

    #expect(
      summary.lineValue("tools")
        == "Search ready via MiniMax Token; Image ready via MiniMax Token; Audio needs key")
  }

  @Test
  func summaryValuesStayBounded() throws {
    let summary = AgentRuntimeSidebarSummary(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        baseURL: try #require(URL(string: "https://api.openai.com/v1")),
        apiKey: "sk-test",
        model: String(repeating: "model-", count: 80)
      ),
      foundationModelsAvailable: false
    )

    #expect(summary.lines.allSatisfy { $0.value.count <= AgentRuntimeSidebarSummary.valueLimit })
  }
}

extension AgentRuntimeSidebarSummary {
  fileprivate func lineValue(_ id: String) -> String? {
    lines.first { $0.id == id }?.value
  }

  fileprivate var joinedText: String {
    lines.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
  }
}
