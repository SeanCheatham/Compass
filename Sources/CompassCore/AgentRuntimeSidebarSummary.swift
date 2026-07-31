import Foundation

struct AgentRuntimeSidebarSummary: Equatable, Sendable {
  static let valueLimit = 160

  struct Line: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var value: String
  }

  var lines: [Line]

  init(settings: AgentRuntimeSettings, modelSnapshot: LocalModelSnapshot) {
    let primaryModel: String
    switch settings.textProvider {
    case .openAICompatible:
      primaryModel =
        settings.trimmedModel.isEmpty ? "(cloud model unset)" : settings.trimmedModel
    case .mlx:
      primaryModel = modelSnapshot.modelID
    }

    let rawLines = [
      Line(id: "provider", label: "Provider", value: settings.textProvider.displayName),
      Line(id: "model", label: "Model", value: primaryModel),
      Line(
        id: "assist",
        label: "Local assist",
        value: modelSnapshot.statusLabel
      ),
      Line(
        id: "context",
        label: "Context",
        value: "\(settings.contextWindowTokens) tokens"
      ),
    ]

    lines = rawLines.map { line in
      Line(
        id: line.id,
        label: line.label,
        value: StringUtils.boundedText(line.value, limit: Self.valueLimit)
      )
    }
  }
}
