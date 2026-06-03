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
  func readyTextExplainsWorkspacePreparationProgress() {
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
    #expect(guide.actionLabel == "Workspace in progress")
    #expect(guide.detail.contains("private workspace"))
    #expect(!guide.detail.contains("Shared VM"))
    #expect(guide.tone == .inProgress)
    #expect(guide.steps[0].isComplete)
    #expect(!guide.steps[1].isComplete)
    #expect(guide.steps[1].detail == "Downloading macOS (42%)")
  }

  @Test
  func readyTextExplainsWorkspaceRequirementBeforeRunControlsUnlock() {
    let guide = OnboardingReadinessGuide(
      settings: AgentRuntimeSettings(
        textProvider: .openAI,
        apiKey: "sk-test",
        model: "gpt-4o"
      ),
      vmReadiness: .notProvisioned,
      foundationModelsAvailable: false
    )

    #expect(guide.title == "Prepare Private Workspace")
    #expect(guide.actionLabel == "Workspace needed")
    #expect(guide.detail.contains("private workspace"))
    #expect(guide.steps[1].label == "Private workspace")
    #expect(guide.steps[1].detail.contains("Prepare the private workspace once"))
    #expect(guide.steps[2].detail.contains("private workspace"))
    #expect(!guide.detail.contains("Shared VM"))
    #expect(!guide.steps[1].detail.contains("Shared VM"))
  }

  @Test
  func workspaceSetupStatusAvoidsHeadlessFirstBootJargon() {
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      apiKey: "sk-test",
      model: "gpt-4o"
    )
    let guide = OnboardingReadinessGuide(
      settings: settings,
      vmReadiness: .guestPrepping,
      foundationModelsAvailable: false
    )
    let payload = OnboardingSetupClipboardPayload(
      guide: guide,
      settings: settings,
      vmReadiness: .guestPrepping,
      foundationModelsAvailable: false
    )

    #expect(guide.steps[1].detail == "Finishing workspace setup")
    #expect(guide.narrationIdentifier.contains("Finishing workspace setup"))
    #expect(payload.text.contains("Status: Finishing workspace setup"))
    #expect(!guide.steps[1].detail.contains("headless"))
    #expect(!payload.text.contains("headless first-boot"))
  }

  @Test
  func workspaceBlockedDetailsUsePrivateWorkspaceCopy() {
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      apiKey: "sk-test",
      model: "gpt-4o"
    )
    let readiness = SharedCompassVMReadiness.error(
      detail: "SSH probe to compass@10.0.0.42 failed while mounting guest disk"
    )
    let guide = OnboardingReadinessGuide(
      settings: settings,
      vmReadiness: readiness,
      foundationModelsAvailable: false
    )
    let payload = OnboardingSetupClipboardPayload(
      guide: guide,
      settings: settings,
      vmReadiness: readiness,
      foundationModelsAvailable: false
    )

    #expect(readiness.privateWorkspaceStatusSummary.contains("secure connection"))
    #expect(guide.steps[1].detail.contains("secure connection"))
    #expect(guide.steps[1].detail.contains("workspace disk"))
    #expect(payload.text.contains("workspace disk"))

    for text in [readiness.privateWorkspaceStatusSummary, guide.steps[1].detail, payload.text] {
      #expect(!text.contains("Shared VM"))
      #expect(!text.contains("SSH"))
      #expect(!text.contains("IPSW"))
      #expect(!text.contains("guest"))
      #expect(!text.contains("compass@10.0.0.42"))
    }
  }

  @Test
  func workspaceRecoveryCopyAvoidsConnectionJargon() {
    let resetCopy = [
      OnboardingWorkspaceRecoveryCopy.resetButtonTitle,
      OnboardingWorkspaceRecoveryCopy.resetHelp,
      OnboardingWorkspaceRecoveryCopy.resetAlertTitle,
      OnboardingWorkspaceRecoveryCopy.resetAlertDetail,
      OnboardingWorkspaceRecoveryCopy.rebuildButtonTitle,
      OnboardingWorkspaceRecoveryCopy.rebuildAlertTitle,
      OnboardingWorkspaceRecoveryCopy.rebuildAlertDetail,
    ].joined(separator: "\n")

    #expect(resetCopy.contains("private workspace"))
    #expect(resetCopy.contains("cached macOS download"))
    #expect(resetCopy.contains("secure connection keys"))
    #expect(!resetCopy.contains("SSH"))
    #expect(!resetCopy.contains("stale"))
    #expect(!resetCopy.contains("auxiliary"))
    #expect(!resetCopy.contains("platform identity"))
    #expect(!resetCopy.contains("artifacts"))
    #expect(OnboardingWorkspaceRecoveryCopy.localRestoreButtonTitle == "Use downloaded restore file")
    #expect(!OnboardingWorkspaceRecoveryCopy.localRestoreButtonTitle.contains("IPSW"))
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
    #expect(payload.text.contains("If Text or the private workspace is blocked"))
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
    #expect(!payload.text.contains("If Text or the Shared VM is blocked"))
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
