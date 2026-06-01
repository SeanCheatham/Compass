import Foundation

struct AgentRuntimeSidebarSummary: Equatable, Sendable {
  static let valueLimit = 160

  struct Line: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var value: String
  }

  var lines: [Line]

  init(settings: AgentRuntimeSettings, foundationModelsAvailable: Bool) {
    var lines: [Line] = [
      Line(id: "text", label: "Text", value: Self.textProviderValue(settings)),
      Line(
        id: "status",
        label: "Status",
        value: Self.textStatusValue(
          settings: settings,
          foundationModelsAvailable: foundationModelsAvailable
        )
      ),
    ]

    if settings.textProvider.requiresCredentials {
      lines.append(
        Line(
          id: "endpoint",
          label: "Endpoint",
          value: Self.endpointValue(settings.baseURL)
        )
      )
    }

    lines.append(
      Line(id: "model", label: "Model", value: Self.modelValue(settings))
    )
    lines.append(
      Line(id: "tools", label: "Tools", value: Self.optionalToolsValue(settings))
    )

    self.lines = lines.map { line in
      Line(
        id: line.id,
        label: line.label,
        value: StringUtils.boundedText(line.value, limit: Self.valueLimit)
      )
    }
  }

  private static func textProviderValue(_ settings: AgentRuntimeSettings) -> String {
    if settings.textProvider == .appleFoundationModels {
      return "\(settings.textProvider.displayName) on-device"
    }
    return settings.textProvider.displayName
  }

  private static func textStatusValue(
    settings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool
  ) -> String {
    if settings.isTextCapabilityRunnable(foundationModelsAvailable: foundationModelsAvailable) {
      return "Text ready"
    }
    if settings.textProvider == .appleFoundationModels {
      return "Apple Intelligence unavailable"
    }
    return "\(settings.textProvider.displayName) needs API key"
  }

  private static func endpointValue(_ url: URL) -> String {
    url.host() ?? url.absoluteString
  }

  private static func modelValue(_ settings: AgentRuntimeSettings) -> String {
    if settings.textProvider == .appleFoundationModels {
      return "Apple Intelligence system model"
    }
    let phaseModels = AgentPhase.allCases.map { "\($0.sidebarLabel)=\(settings.model(for: $0))" }
    let uniqueModels = Set(AgentPhase.allCases.map { settings.model(for: $0) })
    if uniqueModels.count > 1 {
      return phaseModels.joined(separator: "; ")
    }
    let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
    if !model.isEmpty { return model }
    return settings.textProvider.defaultModel(for: .text) ?? "Provider default"
  }

  private static func optionalToolsValue(_ settings: AgentRuntimeSettings) -> String {
    let values = [
      capabilityStatus(label: "Search", assignment: settings.webSearchAssignment),
      capabilityStatus(label: "Vision", assignment: settings.imageUnderstandingAssignment),
      capabilityStatus(label: "Image", assignment: settings.imageAssignment),
      capabilityStatus(label: "Audio", assignment: settings.audioAssignment),
      capabilityStatus(label: "Video", assignment: settings.videoAssignment),
    ].compactMap { $0 }

    guard !values.isEmpty else { return "Optional tools off" }
    return values.joined(separator: "; ")
  }

  private static func capabilityStatus(
    label: String,
    assignment: CapabilityAssignment?
  ) -> String? {
    guard let assignment else { return nil }
    let hasKey = !assignment.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasKey
      ? "\(label) ready via \(assignment.provider.displayName)"
      : "\(label) needs key"
  }
}

extension AgentPhase {
  fileprivate var sidebarLabel: String {
    switch self {
    case .plan: return "Plan"
    case .develop: return "Develop"
    case .reflect: return "Reflect"
    case .critic: return "Critic"
    }
  }
}
