import Foundation

struct AgentSettingsGuide: Equatable, Sendable {
  static let detailLimit = 280
  static let rowDetailLimit = 190
  static let identifierLimit = 1_600

  enum Tone: String, Equatable, Sendable {
    case ready
    case blocked
    case optionalAttention
  }

  enum RowStatus: String, Equatable, Sendable {
    case ready
    case blocked
    case off
    case attention
  }

  struct Row: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var status: RowStatus
  }

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var rows: [Row]
  var narrationIdentifier: String

  init(settings: AgentRuntimeSettings, foundationModelsAvailable: Bool) {
    let textReady = settings.isTextCapabilityRunnable(
      foundationModelsAvailable: foundationModelsAvailable
    )
    rows = Self.rows(
      settings: settings,
      foundationModelsAvailable: foundationModelsAvailable,
      textReady: textReady
    )

    let textBlocked = rows.contains { $0.id == "text" && $0.status == .blocked }
    let optionalNeedsAttention = rows.contains { $0.status == .attention }
    if textBlocked {
      title = "Agent Setup Needs Text"
      detail = Self.textBlockedDetail(
        settings: settings,
        foundationModelsAvailable: foundationModelsAvailable
      )
      actionLabel = "Fix Text"
      tone = .blocked
      systemImageName = "text.bubble.badge.exclamationmark"
    } else if optionalNeedsAttention {
      title = "Core Agent Ready"
      detail =
        "Text can run now. One or more optional media tools are selected but need an API key before agents can use them."
      actionLabel = "Optional setup"
      tone = .optionalAttention
      systemImageName = "checkmark.seal"
    } else if rows.contains(where: { $0.status == .ready && Self.isMediaRowID($0.id) }) {
      title = "Agent Stack Ready"
      detail = "Text can run, and every selected optional media tool has credentials."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else {
      title = "Core Agent Ready"
      detail =
        "Text can run now. Optional Image, Audio, and Video tools can stay off until a project needs generated media."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      rows: rows,
      settings: settings,
      foundationModelsAvailable: foundationModelsAvailable
    )
  }

  private static func rows(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool,
    textReady: Bool
  ) -> [Row] {
    [
      textRow(
        settings: settings,
        foundationModelsAvailable: foundationModelsAvailable,
        textReady: textReady
      ),
      phaseRoutingRow(settings: settings, textReady: textReady),
      mediaRow(capability: .image, assignment: settings.imageAssignment),
      mediaRow(capability: .audio, assignment: settings.audioAssignment),
      mediaRow(capability: .video, assignment: settings.videoAssignment),
    ]
  }

  private static func textRow(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool,
    textReady: Bool
  ) -> Row {
    let detail: String
    let status: RowStatus
    if settings.textProvider == .appleFoundationModels {
      if foundationModelsAvailable {
        detail =
          "Apple Intelligence is available on this Mac; Text can run on device with no API key."
        status = .ready
      } else {
        detail =
          "Apple Intelligence is unavailable on this Mac. Switch Text to MiniMax Token or OpenAI API."
        status = .blocked
      }
    } else if textReady {
      detail =
        "\(settings.textProvider.displayName) has an API key and will use \(textModelName(settings))."
      status = .ready
    } else {
      detail =
        "Add a \(settings.textProvider.displayName) API key before Plan or Develop can run."
      status = .blocked
    }

    return Row(
      id: "text",
      label: "Text provider",
      detail: boundedRowDetail(detail),
      status: status
    )
  }

  private static func phaseRoutingRow(
    settings: AgentRuntimeSettings,
    textReady: Bool
  ) -> Row {
    let detail: String
    let status: RowStatus
    if !textReady {
      detail = "Model roles appear once Text can reach a runnable provider."
      status = .blocked
    } else if settings.textProvider == .appleFoundationModels {
      detail =
        "Plan, Develop, Reflect, and Critic share the on-device model; deterministic checks carry the safety load."
      status = .ready
    } else {
      let overrides = AgentPhase.allCases.compactMap { phase -> String? in
        guard let override = phaseOverride(for: phase, settings: settings) else { return nil }
        return "\(phase.displayLabel)=\(override)"
      }
      if overrides.isEmpty {
        detail =
          "Plan, Develop, Reflect, and Critic use \(textModelName(settings)); set Critic only when you want an independent reviewer."
      } else {
        detail =
          "Overrides: \(overrides.joined(separator: ", ")). Empty phases use \(textModelName(settings))."
      }
      status = .ready
    }

    return Row(
      id: "phaseRouting",
      label: "Model roles",
      detail: boundedRowDetail(detail),
      status: status
    )
  }

  private static func mediaRow(
    capability: AgentCapability,
    assignment: MediaAssignment?
  ) -> Row {
    guard let assignment else {
      return Row(
        id: capability.rawValue,
        label: capability.displayName,
        detail: boundedRowDetail(
          "\(capability.displayName) tools are off; core planning and code work are unaffected."
        ),
        status: .off
      )
    }

    let hasKey = !assignment.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let detail =
      hasKey
      ? "\(assignment.provider.displayName) is ready with \(assignment.model)."
      : "\(assignment.provider.displayName) is selected for \(capability.displayName), but its API key is missing. Core runs still work."

    return Row(
      id: capability.rawValue,
      label: capability.displayName,
      detail: boundedRowDetail(detail),
      status: hasKey ? .ready : .attention
    )
  }

  private static func textBlockedDetail(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool
  ) -> String {
    if settings.textProvider == .appleFoundationModels, !foundationModelsAvailable {
      return
        "The run loop is blocked because Apple Intelligence is unavailable on this Mac. Choose MiniMax Token or OpenAI API for Text, or enable Apple Intelligence if this Mac supports it."
    }
    return "The run loop is blocked until the selected Text provider has an API key."
  }

  private static func textModelName(_ settings: AgentRuntimeSettings) -> String {
    let trimmed = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return settings.textProvider.defaultModel(for: .text) ?? "the provider default"
  }

  private static func phaseOverride(
    for phase: AgentPhase,
    settings: AgentRuntimeSettings
  ) -> String? {
    let raw: String?
    switch phase {
    case .plan: raw = settings.planModelOverride
    case .develop: raw = settings.developModelOverride
    case .reflect: raw = settings.reflectModelOverride
    case .critic: raw = settings.criticModelOverride
    }
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func isMediaRowID(_ id: String) -> Bool {
    id == AgentCapability.image.rawValue
      || id == AgentCapability.audio.rawValue
      || id == AgentCapability.video.rawValue
  }

  private static func boundedRowDetail(_ detail: String) -> String {
    StringUtils.boundedText(detail, limit: Self.rowDetailLimit)
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    actionLabel: String,
    tone: Tone,
    systemImageName: String,
    rows: [Row],
    settings: AgentRuntimeSettings,
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
      "rows:\(rows.map { "\($0.id):\($0.status.rawValue):\($0.detail)" }.joined(separator: ","))",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

extension AgentPhase {
  fileprivate var displayLabel: String {
    switch self {
    case .plan: return "Plan"
    case .develop: return "Develop"
    case .reflect: return "Reflect"
    case .critic: return "Critic"
    }
  }
}
