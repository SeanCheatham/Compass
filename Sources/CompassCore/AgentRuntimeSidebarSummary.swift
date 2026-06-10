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
    let rawLines = [
      Line(id: "runtime", label: "Runtime", value: modelSnapshot.runtimeName),
      Line(
        id: "status",
        label: "Status",
        value: modelSnapshot.statusLabel
      ),
      Line(
        id: "model",
        label: "Model",
        value: modelSnapshot.modelID
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
