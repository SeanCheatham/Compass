import Foundation

package struct AgentRuntimeSidebarSummary: Equatable, Sendable {
  package static let valueLimit = 160

  package struct Line: Identifiable, Equatable, Sendable {
    package var id: String
    package var label: String
    package var value: String
  }

  package var lines: [Line]

  package init(settings: AgentRuntimeSettings, modelSnapshot: LocalModelSnapshot) {
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
