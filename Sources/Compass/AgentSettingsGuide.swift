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
        "Text can run now. One or more optional tools are selected but need an API key before agents can use them."
      actionLabel = "Optional setup"
      tone = .optionalAttention
      systemImageName = "checkmark.seal"
    } else if rows.contains(where: { $0.status == .ready && Self.isOptionalToolRowID($0.id) }) {
      title = "Agent Stack Ready"
      detail = "Text can run, and every selected optional tool has credentials."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else {
      title = "Core Agent Ready"
      detail =
        "Text can run now. Optional search, vision, and media tools can stay off until a project needs them."
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
      optionalToolRow(capability: .webSearch, assignment: settings.webSearchAssignment),
      optionalToolRow(
        capability: .imageUnderstanding,
        assignment: settings.imageUnderstandingAssignment
      ),
      optionalToolRow(capability: .image, assignment: settings.imageAssignment),
      optionalToolRow(capability: .audio, assignment: settings.audioAssignment),
      optionalToolRow(capability: .video, assignment: settings.videoAssignment),
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

  private static func optionalToolRow(
    capability: AgentCapability,
    assignment: CapabilityAssignment?
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
    let modelDetail = assignment.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let readyDetail =
      modelDetail.isEmpty
      ? "\(assignment.provider.displayName) is ready."
      : "\(assignment.provider.displayName) is ready with \(modelDetail)."
    let detail =
      hasKey
      ? readyDetail
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

  private static func isOptionalToolRowID(_ id: String) -> Bool {
    id == AgentCapability.webSearch.rawValue
      || id == AgentCapability.imageUnderstanding.rawValue
      || id == AgentCapability.image.rawValue
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

struct AgentSettingsClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_800

  var text: String

  init(
    settings: AgentRuntimeSettings,
    guide: AgentSettingsGuide,
    foundationModelsAvailable: Bool
  ) {
    let textReady = settings.isTextCapabilityRunnable(
      foundationModelsAvailable: foundationModelsAvailable
    )

    var sections: [String] = [
      "Compass Runtime Settings Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded runtime configuration context. Do not invent "
        + "API keys, endpoints, model names, provider assignments, files, or run outcomes.",
      "- Never ask the user to paste an API key into chat. Credentials are reported "
        + "only as saved, missing, or not required.",
      "- Text readiness is load-bearing for Plan and Develop. Search, vision, and "
        + "media capabilities are optional unless the current project explicitly needs them.",
      "- Foundation Models availability is a local machine fact; ask the user to verify "
        + "Settings or choose a network Text provider instead of assuming availability.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "",
      "Text:",
      "Provider: \(settings.textProvider.displayName)",
      "Runnable: \(Self.yesNo(textReady))",
      "Foundation Models available: \(Self.yesNo(foundationModelsAvailable))",
      "Credential requirement: \(Self.credentialRequirementLabel(settings.textProvider))",
      "Credential saved: \(Self.credentialSavedLabel(settings.apiKey, provider: settings.textProvider))",
      "Base URL: \(Self.baseURLLabel(settings.baseURL, provider: settings.textProvider))",
      "Default model: \(Self.modelLabel(settings.model, provider: settings.textProvider, capability: .text))",
      "Context window tokens: \(settings.contextWindowTokens)",
      "Codemap model: \(Self.codemapModelLabel(settings))",
      "Phase routing: \(Self.phaseRoutingLabel(settings))",
      "",
      "Optional tools:",
    ]

    sections.append(
      Self.capabilityLine(capability: .webSearch, assignment: settings.webSearchAssignment)
    )
    sections.append(
      Self.capabilityLine(
        capability: .imageUnderstanding,
        assignment: settings.imageUnderstandingAssignment
      )
    )
    sections.append(Self.capabilityLine(capability: .image, assignment: settings.imageAssignment))
    sections.append(Self.capabilityLine(capability: .audio, assignment: settings.audioAssignment))
    sections.append(Self.capabilityLine(capability: .video, assignment: settings.videoAssignment))

    sections.append("")
    sections.append("Guide rows:")
    for row in guide.rows {
      sections.append("- [\(row.status.rawValue)] \(row.label): \(row.detail)")
    }

    text = AgentSettingsClipboardText.boundedMultilineText(
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

  private static func credentialRequirementLabel(_ provider: AgentProviderKind) -> String {
    provider.requiresCredentials ? "API key required" : "not required"
  }

  private static func credentialSavedLabel(_ apiKey: String, provider: AgentProviderKind) -> String
  {
    guard provider.requiresCredentials else { return "not required" }
    return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "saved"
  }

  private static func baseURLLabel(_ baseURL: URL, provider: AgentProviderKind) -> String {
    guard provider.requiresCredentials else { return "not used" }
    return baseURL.absoluteString
  }

  private static func modelLabel(
    _ model: String,
    provider: AgentProviderKind,
    capability: AgentCapability
  ) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return provider.defaultModel(for: capability) ?? "provider default"
  }

  private static func phaseRoutingLabel(_ settings: AgentRuntimeSettings) -> String {
    let parts = AgentPhase.allCases.map { phase in
      "\(phase.displayLabel)=\(phaseModelLabel(phase, settings: settings))"
    }
    return parts.joined(separator: ", ")
  }

  private static func phaseModelLabel(
    _ phase: AgentPhase,
    settings: AgentRuntimeSettings
  ) -> String {
    let override: String?
    switch phase {
    case .plan: override = settings.planModelOverride
    case .develop: override = settings.developModelOverride
    case .reflect: override = settings.reflectModelOverride
    case .critic: override = settings.criticModelOverride
    }
    let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty { return trimmed }
    return Self.modelLabel(settings.model, provider: settings.textProvider, capability: .text)
  }

  private static func codemapModelLabel(_ settings: AgentRuntimeSettings) -> String {
    let override =
      settings.codemapModelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    if !override.isEmpty { return override }
    return
      "default (\(Self.modelLabel(settings.model, provider: settings.textProvider, capability: .text)))"
  }

  private static func capabilityLine(
    capability: AgentCapability,
    assignment: CapabilityAssignment?
  ) -> String {
    guard let assignment else {
      return "- \(capability.displayName): off"
    }

    var parts = [
      "- \(capability.displayName): provider \(assignment.provider.displayName)",
      "credential \(Self.credentialSavedLabel(assignment.apiKey, provider: assignment.provider))",
      "base URL \(assignment.baseURL.absoluteString)",
    ]
    let model = assignment.model.trimmingCharacters(in: .whitespacesAndNewlines)
    if !model.isEmpty || assignment.provider.usesModelField(for: capability) {
      parts.append(
        "model \(Self.modelLabel(assignment.model, provider: assignment.provider, capability: capability))"
      )
    }
    return parts.joined(separator: ", ")
  }
}

private enum AgentSettingsClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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
