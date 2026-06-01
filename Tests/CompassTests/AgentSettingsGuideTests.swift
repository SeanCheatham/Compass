import Foundation
import Testing

@testable import Compass

struct AgentSettingsGuideTests {
  @Test
  func foundationModelsUnavailableBlocksTextButKeepsMediaOptional() {
    let guide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Agent Setup Needs Text")
    #expect(guide.actionLabel == "Fix Text")
    #expect(guide.tone == .blocked)
    #expect(guide.rows.map(\.id) == ["text", "phaseRouting", "image", "audio", "video"])
    #expect(guide.rows[0].status == .blocked)
    #expect(guide.rows[0].detail.contains("Apple Intelligence is unavailable"))
    #expect(guide.rows[2].status == .off)
    #expect(guide.rows[2].detail.contains("core planning and code work are unaffected"))
  }

  @Test
  func networkTextReadyWithMissingOptionalMediaKeyShowsOptionalAttention() throws {
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-text",
      model: "gpt-4o",
      imageAssignment: MediaAssignment(
        provider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "",
        model: "image-01"
      )
    )

    let guide = AgentSettingsGuide(settings: settings, foundationModelsAvailable: false)

    #expect(guide.title == "Core Agent Ready")
    #expect(guide.actionLabel == "Optional setup")
    #expect(guide.tone == .optionalAttention)
    #expect(guide.rows[0].status == .ready)
    #expect(guide.rows[2].status == .attention)
    #expect(guide.rows[2].detail.contains("API key is missing"))
  }

  @Test
  func phaseRoutingNamesOverridesAndDefaultFallback() throws {
    let guide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(
        textProvider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "mm-key",
        model: "MiniMax-M2.7",
        planModelOverride: "planner",
        criticModelOverride: "critic"
      ),
      foundationModelsAvailable: false
    )

    let phaseRow = try #require(guide.rows.first { $0.id == "phaseRouting" })
    #expect(phaseRow.status == .ready)
    #expect(phaseRow.detail.contains("Plan=planner"))
    #expect(phaseRow.detail.contains("Critic=critic"))
    #expect(phaseRow.detail.contains("Empty phases use MiniMax-M2.7"))
  }

  @Test
  func fullyConfiguredOptionalMediaMarksAgentStackReady() throws {
    let guide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        baseURL: try #require(URL(string: "https://api.openai.com/v1")),
        apiKey: "sk-text",
        model: "gpt-4o",
        imageAssignment: MediaAssignment(
          provider: .minimaxToken,
          baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
          apiKey: "mm-image",
          model: "image-01"
        )
      ),
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Agent Stack Ready")
    #expect(guide.tone == .ready)
    #expect(guide.rows[2].status == .ready)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalSettingsPolish() async throws {
    let guide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        apiKey: "",
        model: "gpt-4o"
      ),
      foundationModelsAvailable: true
    )

    try await withMockFoundationModels(
      response: "Add the Text API key, then Compass can unlock the core agent run."
    ) {
      let generatedNarration = await AgentSettingsGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text == "Add the Text API key, then Compass can unlock the core agent run.")
    }
  }

  @Test
  func narratorRejectsStructuredBulletedOrLinkedOutput() async {
    let guide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: true
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await AgentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Add a hidden provider") {
      let narration = await AgentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await AgentSettingsGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
