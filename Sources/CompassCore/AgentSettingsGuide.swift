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

  struct RuntimeCoverage: Equatable, Sendable {
    static let labelLimit = 52
    static let detailLimit = 190

    var readyCount: Int
    var selectedCount: Int
    var fraction: Double
    var label: String
    var detail: String
  }

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var runtimeCoverage: RuntimeCoverage
  var rows: [Row]
  var narrationIdentifier: String

  init(settings: AgentRuntimeSettings, modelSnapshot: LocalModelSnapshot) {
    let textReady = settings.isTextCapabilityRunnable(
      localModelReady: modelSnapshot.isRunnable
    )
    let modelDownloading = modelSnapshot.status == .downloading
    rows = [
      Row(
        id: "mlxModel",
        label: "MLX model",
        detail: Self.boundedRowDetail(
          textReady
            ? "\(modelSnapshot.modelID) is ready for local runs."
            : modelDownloading
              ? "\(modelSnapshot.modelID) is downloading."
              : "\(modelSnapshot.modelID) must be downloaded before the factory loop can start."
        ),
        status: textReady ? .ready : modelDownloading ? .attention : .blocked
      ),
      Row(
        id: "execution",
        label: "Execution",
        detail: Self.boundedRowDetail(
          "Plan, Develop, and Critic all use the local model. Deterministic tools handle file access, edits, shell checks, and verification."
        ),
        status: textReady ? .ready : .blocked
      ),
      Row(
        id: "context",
        label: "Context window",
        detail: Self.boundedRowDetail("\(settings.contextWindowTokens) token working budget."),
        status: .ready
      ),
    ]

    runtimeCoverage = Self.coverage(
      readyCount: textReady ? 1 : 0,
      selectedCount: 1,
      fraction: textReady ? 1 : 0,
      label: textReady
        ? "Local runtime ready"
        : modelDownloading ? "Local model downloading" : "Local runtime blocked",
      detail: textReady
        ? "The local MLX model can handle the software-factory loop."
        : modelDownloading
          ? "Compass will unlock local runs when the blessed Qwen model finishes downloading."
          : "Download the blessed Qwen model before running Compass."
    )

    if textReady {
      title = "Local Runtime Ready"
      detail = "Compass will use MLX for narrow non-deterministic work and keep the rest of the factory loop deterministic."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else if modelDownloading {
      title = "Local Model Downloading"
      detail = "Compass is downloading the blessed Qwen model. Local runs remain blocked until the files are complete."
      actionLabel = modelSnapshot.statusLabel
      tone = .optionalAttention
      systemImageName = "arrow.down.circle"
    } else {
      title = "Local Model Missing"
      detail = "Compass is MLX-only in this build. The run loop is blocked until the blessed Qwen model is downloaded."
      actionLabel = "Blocked"
      tone = .blocked
      systemImageName = "text.bubble.badge.exclamationmark"
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      runtimeCoverage: runtimeCoverage,
      rows: rows,
      modelSnapshot: modelSnapshot
    )
  }

  private static func coverage(
    readyCount: Int,
    selectedCount: Int,
    fraction: Double,
    label: String,
    detail: String
  ) -> RuntimeCoverage {
    RuntimeCoverage(
      readyCount: readyCount,
      selectedCount: selectedCount,
      fraction: fraction,
      label: StringUtils.boundedText(label, limit: RuntimeCoverage.labelLimit),
      detail: StringUtils.boundedText(detail, limit: RuntimeCoverage.detailLimit)
    )
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
    runtimeCoverage: RuntimeCoverage,
    rows: [Row],
    modelSnapshot: LocalModelSnapshot
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "action:\(actionLabel)",
      "tone:\(tone.rawValue)",
      "image:\(systemImageName)",
      "coverage:\(runtimeCoverage.label):\(runtimeCoverage.readyCount)/\(runtimeCoverage.selectedCount)",
      "modelStatus:\(modelSnapshot.status.rawValue)",
      "modelID:\(modelSnapshot.modelID)",
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
    modelSnapshot: LocalModelSnapshot
  ) {
    let textReady = settings.isTextCapabilityRunnable(
      localModelReady: modelSnapshot.isRunnable
    )

    var sections: [String] = [
      "Compass Runtime Settings Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded local runtime context.",
      "- Do not invent credentials, network endpoints, model names, files, or run outcomes.",
      "- Compass is MLX-only; deterministic tools carry file edits, shell checks, and verification.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "Runtime coverage: \(guide.runtimeCoverage.label) - \(guide.runtimeCoverage.detail)",
      "",
      "Local model:",
      "Runnable: \(Self.yesNo(textReady))",
      "Runtime: \(modelSnapshot.runtimeName)",
      "Model: \(modelSnapshot.modelID)",
      "Status: \(modelSnapshot.statusLabel)",
      "Directory: \(modelSnapshot.directory.path)",
      "Context window tokens: \(settings.contextWindowTokens)",
      "",
      "Guide rows:",
    ]

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
