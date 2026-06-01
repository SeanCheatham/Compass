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
  func settingsClipboardPayloadRedactsCredentialsAndPackagesRouting() throws {
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-text-secret",
      model: "gpt-4o",
      planModelOverride: "planner-model",
      criticModelOverride: "critic-model",
      codemapModelOverride: "cheap-codemap",
      contextWindowTokens: 128_000,
      imageAssignment: MediaAssignment(
        provider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "mm-image-secret",
        model: "image-01"
      ),
      audioAssignment: MediaAssignment(
        provider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "",
        model: "speech-02-hd"
      )
    )
    let guide = AgentSettingsGuide(settings: settings, foundationModelsAvailable: false)

    let payload = AgentSettingsClipboardPayload(
      settings: settings,
      guide: guide,
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Compass Runtime Settings Handoff"))
    #expect(payload.text.contains("Never ask the user to paste an API key into chat"))
    #expect(payload.text.contains("Status: Core Agent Ready (optionalAttention)"))
    #expect(payload.text.contains("Provider: OpenAI API"))
    #expect(payload.text.contains("Runnable: yes"))
    #expect(payload.text.contains("Credential saved: saved"))
    #expect(payload.text.contains("Base URL: https://api.openai.com/v1"))
    #expect(payload.text.contains("Default model: gpt-4o"))
    #expect(payload.text.contains("Context window tokens: 128000"))
    #expect(payload.text.contains("Codemap model: cheap-codemap"))
    #expect(payload.text.contains("Phase routing: Plan=planner-model"))
    #expect(payload.text.contains("Develop=gpt-4o"))
    #expect(payload.text.contains("Critic=critic-model"))
    #expect(payload.text.contains("Image: provider MiniMax Token, credential saved"))
    #expect(payload.text.contains("Audio: provider MiniMax Token, credential missing"))
    #expect(payload.text.contains("Video: off"))
    #expect(payload.text.contains("[ready] Image"))
    #expect(payload.text.contains("[attention] Audio"))
    #expect(!payload.text.contains("sk-text-secret"))
    #expect(!payload.text.contains("mm-image-secret"))
    #expect(payload.text.count <= AgentSettingsClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func settingsClipboardPayloadNamesFoundationModelsMachineBlocker() {
    let settings = AgentRuntimeSettings(textProvider: .appleFoundationModels)
    let guide = AgentSettingsGuide(settings: settings, foundationModelsAvailable: false)

    let payload = AgentSettingsClipboardPayload(
      settings: settings,
      guide: guide,
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Status: Agent Setup Needs Text (blocked)"))
    #expect(payload.text.contains("Provider: Foundation Models"))
    #expect(payload.text.contains("Runnable: no"))
    #expect(payload.text.contains("Foundation Models available: no"))
    #expect(payload.text.contains("Credential requirement: not required"))
    #expect(payload.text.contains("Credential saved: not required"))
    #expect(payload.text.contains("Base URL: not used"))
    #expect(payload.text.contains("Default model: provider default"))
    #expect(payload.text.contains("[blocked] Text provider"))
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
