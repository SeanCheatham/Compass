import Foundation

public struct AgentSettingsGuide: Equatable, Sendable {
  public static let detailLimit = 280
  public static let rowDetailLimit = 190
  public static let identifierLimit = 1_600

  public enum Tone: String, Equatable, Sendable {
    case ready
    case blocked
    case optionalAttention
  }

  public enum RowStatus: String, Equatable, Sendable {
    case ready
    case blocked
    case off
    case attention
  }

  public struct Row: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var detail: String
    public var status: RowStatus
  }

  public struct RuntimeCoverage: Equatable, Sendable {
    public static let labelLimit = 52
    public static let detailLimit = 190

    public var readyCount: Int
    public var selectedCount: Int
    public var fraction: Double
    public var label: String
    public var detail: String
  }

  public var title: String
  public var detail: String
  public var actionLabel: String
  public var tone: Tone
  public var systemImageName: String
  public var runtimeCoverage: RuntimeCoverage
  public var rows: [Row]
  public var narrationIdentifier: String

  public init(settings: AgentRuntimeSettings, modelSnapshot: LocalModelSnapshot) {
    let cloudReady = settings.isCloudConfigured || (
      settings.textProvider == .openAICompatible && settings.hasCloudCredentials
    )
    let mlxReady = modelSnapshot.isRunnable
    let modelDownloading = modelSnapshot.status == .downloading
    let textReady = settings.isTextCapabilityRunnable(localModelReady: mlxReady)

    let cloudDetail: String
    let cloudStatus: RowStatus
    if settings.textProvider == .mlx {
      cloudDetail = "Cloud endpoint unused while text provider is MLX."
      cloudStatus = .off
    } else if cloudReady {
      cloudDetail =
        "\(settings.trimmedModel) via \(settings.cloudEndpointDisplay()) is ready for Plan/Develop/Critic."
      cloudStatus = .ready
    } else {
      cloudDetail =
        "Set API key, base URL, and model for the OpenAI-compatible cloud endpoint."
      cloudStatus = .blocked
    }

    let localDetail: String
    let localStatus: RowStatus
    if mlxReady {
      localDetail = "\(modelSnapshot.modelID) is ready for cheap local assist work."
      localStatus = .ready
    } else if modelDownloading {
      localDetail = "\(modelSnapshot.modelID) is downloading for optional local assist."
      localStatus = .attention
    } else {
      localDetail =
        "Optional: download \(modelSnapshot.modelID) for local assist (narration, compaction)."
      localStatus = settings.textProvider == .mlx ? .blocked : .off
    }

    rows = [
      Row(
        id: "cloud",
        label: "Cloud endpoint",
        detail: Self.boundedRowDetail(cloudDetail),
        status: cloudStatus
      ),
      Row(
        id: "mlxAssist",
        label: "Local assist",
        detail: Self.boundedRowDetail(localDetail),
        status: localStatus
      ),
      Row(
        id: "execution",
        label: "Execution",
        detail: Self.boundedRowDetail(
          textReady
            ? "Plan/Develop/Critic use the primary text provider. Deterministic tools handle files, shell, and verification."
            : "Configure cloud credentials or download MLX before the factory loop can start."
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

    let readyCount = [cloudStatus == .ready, localStatus == .ready, textReady].filter { $0 }.count
    runtimeCoverage = Self.coverage(
      readyCount: readyCount,
      selectedCount: 3,
      fraction: Double(readyCount) / 3.0,
      label: textReady
        ? (mlxReady ? "Hybrid runtime ready" : "Cloud runtime ready")
        : modelDownloading ? "Local model downloading" : "Runtime blocked",
      detail: textReady
        ? (mlxReady
          ? "Cloud handles factory turns; MLX assists with cheap local work."
          : "Cloud can run the factory loop. Download MLX later for local assist.")
        : modelDownloading && settings.textProvider == .mlx
          ? "Compass will unlock local runs when the blessed Qwen model finishes downloading."
          : "Configure an OpenAI-compatible endpoint (or MLX) before running Compass."
    )

    if textReady {
      title = mlxReady ? "Hybrid Runtime Ready" : "Cloud Runtime Ready"
      detail =
        mlxReady
        ? "Compass will use the OpenAI-compatible cloud endpoint for Plan/Develop/Critic and MLX for small assist tasks."
        : "Compass will use the configured OpenAI-compatible endpoint for factory turns. Local MLX assist is optional."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else if settings.textProvider == .mlx && modelDownloading {
      title = "Local Model Downloading"
      detail =
        "Compass is downloading the blessed Qwen model. Local runs remain blocked until the files are complete."
      actionLabel = modelSnapshot.statusLabel
      tone = .optionalAttention
      systemImageName = "arrow.down.circle"
    } else {
      title = "Runtime Not Ready"
      detail =
        settings.textProvider == .mlx
        ? "Download the blessed Qwen model before running Compass in MLX mode."
        : "Add an API key, base URL, and model for the OpenAI-compatible cloud endpoint."
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

public struct AgentSettingsClipboardPayload: Equatable, Sendable {
  public static let textLimit = 3_800

  public var text: String

  public init(
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
      "- Treat this packet as bounded runtime context.",
      "- Do not invent credentials, network endpoints, model names, files, or run outcomes.",
      "- Cloud turns use an OpenAI-compatible endpoint; MLX is optional local assist.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "Runtime coverage: \(guide.runtimeCoverage.label) - \(guide.runtimeCoverage.detail)",
      "",
      "Text provider: \(settings.textProvider.displayName)",
      "Cloud base URL: \(settings.cloudEndpointDisplay())",
      "Cloud model: \(settings.trimmedModel.isEmpty ? "(unset)" : settings.trimmedModel)",
      "Cloud key present: \(Self.yesNo(!settings.trimmedAPIKey.isEmpty))",
      "Cloud ready: \(Self.yesNo(settings.hasCloudCredentials))",
      "",
      "Local assist:",
      "Runnable: \(Self.yesNo(modelSnapshot.isRunnable))",
      "Runtime: \(modelSnapshot.runtimeName)",
      "Model: \(modelSnapshot.modelID)",
      "Status: \(modelSnapshot.statusLabel)",
      "Directory: \(modelSnapshot.directory.path)",
      "Context window tokens: \(settings.contextWindowTokens)",
      "Factory text ready: \(Self.yesNo(textReady))",
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

  public var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
  }
}

private enum AgentSettingsClipboardText {
  public static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
