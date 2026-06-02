import Foundation

extension SharedCompassVMReadiness {
  var onboardingWorkspaceStatusSummary: String {
    switch self {
    case .unavailable(let reason):
      return "Unavailable. \(reason)"
    case .notProvisioned:
      return "Not prepared"
    case .downloadingIPSW(let fraction):
      let pct = Int((Swift.min(1, Swift.max(0, fraction)) * 100).rounded())
      return "Downloading restore image (\(pct)%)"
    case .installing(let fraction):
      let pct = Int((Swift.min(1, Swift.max(0, fraction)) * 100).rounded())
      return "Installing macOS (\(pct)%)"
    case .guestPrepping:
      return "Finishing workspace setup"
    case .provisioningDevTools(let fraction):
      let pct = Int((Swift.min(1, Swift.max(0, fraction)) * 100).rounded())
      return "Installing developer tools (\(pct)%)"
    case .ready:
      return "Ready"
    case .error(let detail):
      return "Error. \(detail)"
    }
  }
}

struct OnboardingReadinessGuide: Equatable, Sendable {
  static let detailLimit = 260
  static let identifierLimit = 1_200

  enum Tone: String, Equatable, Sendable {
    case ready
    case needsText
    case needsWorkspace
    case inProgress
  }

  struct Step: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImageName: String
    var isComplete: Bool
  }

  struct UnlockPreview: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImageName: String
    var isUnlocked: Bool
  }

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var steps: [Step]
  var unlockPreview: [UnlockPreview]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    tone != .needsText
  }

  init(
    settings: AgentRuntimeSettings,
    vmReadiness: SharedCompassVMReadiness,
    foundationModelsAvailable: Bool
  ) {
    let textReady = settings.isTextCapabilityRunnable(
      foundationModelsAvailable: foundationModelsAvailable
    )
    let vmReady = vmReadiness.isReady
    let vmInProgress = Self.vmIsInProgress(vmReadiness)

    if textReady && vmReady {
      title = "Factory Ready"
      detail =
        "Compass has a runnable Text provider and a private macOS workspace, so it can plan, develop, verify, and review safely."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else if !textReady {
      title =
        settings.textProvider == .appleFoundationModels
        ? "Choose a Runnable Text Provider"
        : "Finish Text Provider"
      detail = Self.textDetail(
        settings: settings,
        foundationModelsAvailable: foundationModelsAvailable
      )
      actionLabel = "Text blocked"
      tone = .needsText
      systemImageName = "text.bubble.badge.exclamationmark"
    } else if vmInProgress {
      title = "Preparing Private Workspace"
      detail =
        "Text is ready. Compass is still preparing the private workspace so Develop can edit inside an isolated macOS environment."
      actionLabel = "Workspace in progress"
      tone = .inProgress
      systemImageName = vmReadiness.systemImage
    } else {
      title = "Prepare Private Workspace"
      detail =
        "Text is ready. Prepare the private workspace before Compass starts agent work, so edits and commands run outside your host checkout."
      actionLabel = "Workspace needed"
      tone = .needsWorkspace
      systemImageName = vmReadiness.systemImage
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    steps = Self.steps(
      settings: settings,
      vmReadiness: vmReadiness,
      foundationModelsAvailable: foundationModelsAvailable,
      textReady: textReady,
      vmReady: vmReady
    )
    unlockPreview = Self.unlockPreview(isUnlocked: textReady && vmReady)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      steps: steps,
      unlockPreview: unlockPreview,
      settings: settings,
      vmReadiness: vmReadiness,
      foundationModelsAvailable: foundationModelsAvailable
    )
  }

  private static func textDetail(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool
  ) -> String {
    if settings.textProvider == .appleFoundationModels, !foundationModelsAvailable {
      return
        "Apple Intelligence is unavailable on this Mac, so the default on-device Text provider cannot run. Switch Text to MiniMax Token or OpenAI API in Settings, or enable Apple Intelligence if supported."
    }
    return
      "Add an API key for \(settings.textProvider.displayName) before Compass can ask an agent to plan or develop."
  }

  private static func steps(
    settings: AgentRuntimeSettings,
    vmReadiness: SharedCompassVMReadiness,
    foundationModelsAvailable: Bool,
    textReady: Bool,
    vmReady: Bool
  ) -> [Step] {
    [
      Step(
        id: "text",
        label: "Text provider",
        detail: textStepDetail(
          settings: settings,
          foundationModelsAvailable: foundationModelsAvailable,
          isReady: textReady
        ),
        systemImageName: settings.textProvider.requiresCredentials
          ? "key.fill" : "cpu",
        isComplete: textReady
      ),
      Step(
        id: "workspace",
        label: "Private workspace",
        detail: vmStepDetail(vmReadiness),
        systemImageName: vmReadiness.systemImage,
        isComplete: vmReady
      ),
      Step(
        id: "firstRun",
        label: "First run",
        detail: textReady && vmReady
          ? "Run controls are unlocked for a scoped Plan or full loop."
          : "Run controls stay locked until Text and the private workspace are both ready.",
        systemImageName: "play.circle",
        isComplete: textReady && vmReady
      ),
    ]
  }

  private static func unlockPreview(isUnlocked: Bool) -> [UnlockPreview] {
    [
      UnlockPreview(
        id: "plan",
        label: "Plan",
        detail: "Turn a rough goal into one executable next slice.",
        systemImageName: "map",
        isUnlocked: isUnlocked
      ),
      UnlockPreview(
        id: "develop",
        label: "Develop",
        detail: "Edit and run commands inside the private workspace.",
        systemImageName: "hammer.fill",
        isUnlocked: isUnlocked
      ),
      UnlockPreview(
        id: "review",
        label: "Verify + review",
        detail: "Save the check result and decide whether to continue.",
        systemImageName: "checkmark.seal",
        isUnlocked: isUnlocked
      ),
    ]
  }

  private static func textStepDetail(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool,
    isReady: Bool
  ) -> String {
    if settings.textProvider == .appleFoundationModels {
      return foundationModelsAvailable
        ? "Apple Intelligence is available on this Mac; no API key is needed."
        : "Apple Intelligence is unavailable on this Mac."
    }

    return isReady
      ? "\(settings.textProvider.displayName) has a saved API key."
      : "Add a \(settings.textProvider.displayName) API key."
  }

  private static func vmStepDetail(_ readiness: SharedCompassVMReadiness) -> String {
    switch readiness {
    case .ready:
      return "Private workspace is ready for sandboxed Develop work."
    case .notProvisioned:
      return "Prepare the private workspace once; first install downloads about 14 GB."
    case .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return readiness.onboardingWorkspaceStatusSummary
    case .unavailable(let reason):
      return "Private workspace is unavailable: \(reason)"
    case .error(let detail):
      return "Private workspace needs attention: \(detail)"
    }
  }

  private static func vmIsInProgress(_ readiness: SharedCompassVMReadiness) -> Bool {
    switch readiness {
    case .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return true
    case .unavailable, .notProvisioned, .ready, .error:
      return false
    }
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    actionLabel: String,
    tone: Tone,
    systemImageName: String,
    steps: [Step],
    unlockPreview: [UnlockPreview],
    settings: AgentRuntimeSettings,
    vmReadiness: SharedCompassVMReadiness,
    foundationModelsAvailable: Bool
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "action:\(actionLabel)",
      "tone:\(tone.rawValue)",
      "image:\(systemImageName)",
      "provider:\(settings.textProvider.rawValue)",
      "textReady:\(settings.isTextCapabilityRunnable(foundationModelsAvailable: foundationModelsAvailable))",
      "fmAvailable:\(foundationModelsAvailable)",
      "vm:\(vmReadiness.onboardingWorkspaceStatusSummary)",
      "steps:\(steps.map { "\($0.id):\($0.isComplete)" }.joined(separator: ","))",
      "unlocks:\(unlockPreview.map { "\($0.id):\($0.isUnlocked)" }.joined(separator: ","))",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

struct OnboardingSetupClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_200

  var text: String

  init(
    guide: OnboardingReadinessGuide,
    settings: AgentRuntimeSettings,
    vmReadiness: SharedCompassVMReadiness,
    foundationModelsAvailable: Bool
  ) {
    let textReady = settings.isTextCapabilityRunnable(
      foundationModelsAvailable: foundationModelsAvailable
    )
    let vmReady = vmReadiness.isReady

    var sections: [String] = [
      "Compass Setup Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded onboarding context. Do not invent credentials, "
        + "device support, files, commands, outcomes, or extra setup state.",
      "- Never ask the user to paste an API key into chat. This packet only reports "
        + "whether a credential is saved.",
      "- Use the checklist and raw readiness fields to identify the next safe setup action.",
      "- If Text or the private workspace is blocked, ask for the missing user-verifiable fact "
        + "instead of assuming the environment can run.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "Run controls: \(textReady && vmReady ? "unlocked" : "locked")",
      "",
      "Text provider:",
      "Provider: \(settings.textProvider.displayName)",
      "Runnable: \(Self.yesNo(textReady))",
      "Foundation Models available: \(Self.yesNo(foundationModelsAvailable))",
      "Credential requirement: \(Self.credentialRequirementLabel(settings))",
      "Credential saved: \(Self.credentialSavedLabel(settings))",
    ]

    if settings.textProvider.requiresCredentials {
      sections.append("Base URL: \(settings.baseURL.absoluteString)")
      sections.append("Model: \(Self.modelLabel(settings.model))")
    }

    sections.append("")
    sections.append("Private workspace:")
    sections.append("Status: \(vmReadiness.onboardingWorkspaceStatusSummary)")
    sections.append("Ready: \(Self.yesNo(vmReady))")

    sections.append("")
    sections.append("Checklist:")
    for step in guide.steps {
      sections.append(
        "- \(step.isComplete ? "[complete]" : "[blocked]") \(step.label): \(step.detail)"
      )
    }

    sections.append("")
    sections.append("After setup:")
    for unlock in guide.unlockPreview {
      sections.append(
        "- \(unlock.isUnlocked ? "[unlocked]" : "[locked]") \(unlock.label): \(unlock.detail)"
      )
    }

    text = OnboardingSetupClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
  }

  private static func credentialSavedLabel(_ settings: AgentRuntimeSettings) -> String {
    guard settings.textProvider.requiresCredentials else { return "not required" }
    return settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "no" : "yes"
  }

  private static func credentialRequirementLabel(_ settings: AgentRuntimeSettings) -> String {
    settings.textProvider.requiresCredentials ? "API key required" : "No API key required"
  }

  private static func modelLabel(_ model: String) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "not set" : trimmed
  }
}

private enum OnboardingSetupClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
