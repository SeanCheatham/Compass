import Foundation

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

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var steps: [Step]
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
        "Text is ready. Compass is still preparing the Shared VM so Develop can edit inside an isolated macOS environment."
      actionLabel = "VM in progress"
      tone = .inProgress
      systemImageName = vmReadiness.systemImage
    } else {
      title = "Prepare Private Workspace"
      detail =
        "Text is ready. Provision the Shared VM before Compass starts agent work, so edits and commands run outside your host checkout."
      actionLabel = "VM needed"
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
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      steps: steps,
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
        "Foundation Models is selected, but the on-device model is unavailable on this Mac. Switch Text to MiniMax Token or OpenAI API in Settings, or enable Apple Intelligence if supported."
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
          : "Run controls stay locked until Text and the Shared VM are both ready.",
        systemImageName: "play.circle",
        isComplete: textReady && vmReady
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
        ? "Foundation Models is available on this Mac; no API key is needed."
        : "Foundation Models is selected but unavailable on this Mac."
    }

    return isReady
      ? "\(settings.textProvider.displayName) has a saved API key."
      : "Add a \(settings.textProvider.displayName) API key."
  }

  private static func vmStepDetail(_ readiness: SharedCompassVMReadiness) -> String {
    switch readiness {
    case .ready:
      return "Shared VM is ready for sandboxed Develop work."
    case .notProvisioned:
      return "Provision the Shared VM once; first install downloads about 14 GB."
    case .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return readiness.statusSummary
    case .unavailable(let reason):
      return "Shared VM is unavailable: \(reason)"
    case .error(let detail):
      return "Shared VM needs attention: \(detail)"
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
      "vm:\(vmReadiness.statusSummary)",
      "steps:\(steps.map { "\($0.id):\($0.isComplete)" }.joined(separator: ","))",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}
