import Foundation

public struct AgentRuntimeSidebarSummary: Equatable, Sendable {
  public static let valueLimit = 160

  public struct Line: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String
  }

  public var lines: [Line]

  public init(settings: AgentRuntimeSettings, modelSnapshot: LocalModelSnapshot) {
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
