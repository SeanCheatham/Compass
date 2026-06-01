import Foundation
import Testing

@testable import Compass

struct OnboardingReadinessGuideTests {
  @Test
  func readyGuideRequiresRunnableTextAndReadyVM() {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: true
    )

    #expect(guide.title == "Factory Ready")
    #expect(guide.actionLabel == "Ready")
    #expect(guide.tone == .ready)
    #expect(guide.steps.map(\.id) == ["text", "workspace", "firstRun"])
    #expect(guide.steps.allSatisfy { $0.isComplete })
    #expect(guide.unlockPreview.map(\.id) == ["plan", "develop", "review"])
    #expect(guide.unlockPreview.allSatisfy { $0.isUnlocked })
    #expect(guide.unlockPreview[0].detail.contains("rough goal"))
    #expect(guide.allowsNarration)
  }

  @Test
  func foundationModelsUnavailableBlocksTextProvider() {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Choose a Runnable Text Provider")
    #expect(guide.actionLabel == "Text blocked")
    #expect(guide.tone == .needsText)
    #expect(guide.detail.contains("Apple Intelligence is unavailable"))
    #expect(guide.steps[0].detail == "Apple Intelligence is unavailable on this Mac.")
    #expect(!guide.steps[0].isComplete)
    #expect(!guide.steps[2].isComplete)
    #expect(guide.unlockPreview.allSatisfy { !$0.isUnlocked })
    #expect(!guide.allowsNarration)
  }

  @Test
  func networkProviderNeedsAPIKeyBeforeRunControlsUnlock() {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(
        textProvider: .minimaxToken,
        apiKey: "",
        model: "MiniMax-M2.7"
      ),
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Finish Text Provider")
    #expect(
      guide.detail
        == "Add an API key for MiniMax Token before Compass can ask an agent to plan or develop.")
    #expect(guide.steps[0].detail == "Add a MiniMax Token API key.")
    #expect(!guide.steps[0].isComplete)
  }

  @Test
  func readyTextExplainsVMPreparationProgress() {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        apiKey: "sk-test",
        model: "gpt-4o"
      ),
      vmReadiness: .downloadingIPSW(fractionCompleted: 0.42),
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Preparing Private Workspace")
    #expect(guide.actionLabel == "VM in progress")
    #expect(guide.tone == .inProgress)
    #expect(guide.steps[0].isComplete)
    #expect(!guide.steps[1].isComplete)
    #expect(guide.steps[1].detail == "Downloading restore image (42%)")
  }

  @Test
  func runtimeSettingsTreatFoundationModelsAvailabilityAsReadinessInput() {
    let foundationModels = AgentRuntimeSettings(textProvider: .appleFoundationModels)
    #expect(foundationModels.isTextCapabilityRunnable(foundationModelsAvailable: true))
    #expect(!foundationModels.isTextCapabilityRunnable(foundationModelsAvailable: false))

    let networkMissingKey = AgentRuntimeSettings(
      textProvider: .openAI,
      apiKey: "",
      model: "gpt-4o"
    )
    #expect(!networkMissingKey.isTextCapabilityRunnable(foundationModelsAvailable: true))

    let networkReady = AgentRuntimeSettings(
      textProvider: .openAI,
      apiKey: "sk-test",
      model: "gpt-4o"
    )
    #expect(networkReady.isTextCapabilityRunnable(foundationModelsAvailable: false))
  }

  @Test
  func setupClipboardPayloadPackagesBlockedSetupForReuse() throws {
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-secret-should-not-copy",
      model: "gpt-4o"
    )
    let guide = OnboardingReadinessGuide(
      settings: settings,
      vmReadiness: .error(detail: String(repeating: "install failed ", count: 40)),
      foundationModelsAvailable: false
    )

    let payload = OnboardingSetupClipboardPayload(
      guide: guide,
      settings: settings,
      vmReadiness: .error(detail: String(repeating: "install failed ", count: 40)),
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Compass Setup Handoff"))
    #expect(payload.text.contains("Do not invent credentials"))
    #expect(payload.text.contains("Never ask the user to paste an API key into chat"))
    #expect(payload.text.contains("Status: Prepare Private Workspace (needsWorkspace)"))
    #expect(payload.text.contains("Run controls: locked"))
    #expect(payload.text.contains("Provider: OpenAI API"))
    #expect(payload.text.contains("Runnable: yes"))
    #expect(payload.text.contains("Credential saved: yes"))
    #expect(payload.text.contains("Base URL: https://api.openai.com/v1"))
    #expect(payload.text.contains("Model: gpt-4o"))
    #expect(payload.text.contains("Private workspace:"))
    #expect(payload.text.contains("Ready: no"))
    #expect(payload.text.contains("[complete] Text provider"))
    #expect(payload.text.contains("[blocked] Private workspace"))
    #expect(payload.text.contains("After setup:"))
    #expect(payload.text.contains("[locked] Plan"))
    #expect(payload.text.contains("[locked] Verify + review"))
    #expect(!payload.text.contains("sk-secret-should-not-copy"))
    #expect(payload.text.count <= OnboardingSetupClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func setupClipboardPayloadNamesUnavailableFoundationModelsWithoutNetworkFields() {
    let settings = AgentRuntimeSettings(textProvider: .appleFoundationModels)
    let guide = OnboardingReadinessGuide(
      settings: settings,
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: false
    )

    let payload = OnboardingSetupClipboardPayload(
      guide: guide,
      settings: settings,
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Status: Choose a Runnable Text Provider (needsText)"))
    #expect(payload.text.contains("Run controls: locked"))
    #expect(payload.text.contains("Provider: Foundation Models"))
    #expect(payload.text.contains("Runnable: no"))
    #expect(payload.text.contains("Foundation Models available: no"))
    #expect(payload.text.contains("Credential requirement: No API key required"))
    #expect(payload.text.contains("Credential saved: not required"))
    #expect(payload.text.contains("[blocked] Text provider"))
    #expect(payload.text.contains("[complete] Private workspace"))
    #expect(!payload.text.contains("Base URL:"))
    #expect(!payload.text.contains("Model:"))
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalSetupPolish() async throws {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: true
    )

    try await withMockFoundationModels(response: "Compass is ready to start a safe run.") {
      let prompt = OnboardingReadinessGuideNarrator.prompt(for: guide)
      #expect(prompt.contains("Unlocks:"))
      #expect(prompt.contains("Plan - Turn a rough goal"))

      let generatedNarration = await OnboardingReadinessGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(narration.text == "Compass is ready to start a safe run.")
    }
  }

  @Test
  func narratorRejectsStructuredOrLinkedOutput() async {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      vmReadiness: .ready(sshDestination: "compass@10.0.0.42"),
      foundationModelsAvailable: true
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await OnboardingReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await OnboardingReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
