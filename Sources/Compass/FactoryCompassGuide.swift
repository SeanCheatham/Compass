import Foundation

struct FactoryCompassGuide: Equatable {
  static let headlineLimit = 180
  static let detailLimit = 240
  static let handoffLimit = 2_600

  var title: String
  var headline: String
  var systemImage: String
  var tone: Tone
  var primaryActionTitle: String
  var primaryActionDetail: String
  var primaryActionIsEnabled: Bool
  var readinessTitle: String
  var readinessDetail: String
  var signalLabel: String
  var signalDetail: String
  var rustHealth: RustFactoryHealth?
  var previewSteps: [PreviewStep]
  var handoffText: String

  var controlLabel: String {
    switch tone {
    case .ready:
      return "Ready"
    case .info:
      return signalLabel
    case .warning:
      return signalLabel.isEmpty ? "Needs signal" : signalLabel
    case .failure:
      return "Needs repair"
    case .paused:
      return "Paused"
    }
  }

  init(runGuide: ProjectRunControlGuide, rustHealth: RustFactoryHealth? = nil) {
    title = Self.bounded(runGuide.readiness.title, limit: 44)
    headline = Self.bounded(runGuide.primaryHelp, limit: Self.headlineLimit)
    systemImage = runGuide.readiness.systemImage
    tone = Tone(badgeTone: runGuide.decisionBadge.tone)
    primaryActionTitle = Self.bounded(runGuide.primaryOption.title, limit: 64)
    primaryActionDetail = Self.bounded(runGuide.primaryOption.detail, limit: Self.detailLimit)
    primaryActionIsEnabled = runGuide.primaryOption.isEnabled
    readinessTitle = Self.bounded(runGuide.readiness.title, limit: 64)
    readinessDetail = Self.bounded(runGuide.readiness.detail, limit: Self.detailLimit)
    signalLabel = Self.bounded(runGuide.decisionBadge.label, limit: 48)
    signalDetail = Self.bounded(runGuide.decisionBadge.detail, limit: Self.detailLimit)
    self.rustHealth = rustHealth.map { health in
      var bounded = health
      bounded.title = Self.bounded(health.title, limit: 64)
      bounded.detail = Self.bounded(health.detail, limit: Self.detailLimit)
      bounded.nextAction = Self.bounded(health.nextAction, limit: Self.detailLimit)
      return bounded
    }
    previewSteps = runGuide.previewSteps.map { step in
      PreviewStep(
        id: step.id,
        title: Self.bounded(step.title, limit: 72),
        detail: Self.bounded(step.detail, limit: Self.detailLimit),
        systemImage: step.systemImage
      )
    }
    handoffText = Self.handoffText(
      title: title,
      headline: headline,
      readinessTitle: readinessTitle,
      readinessDetail: readinessDetail,
      signalLabel: signalLabel,
      signalDetail: signalDetail,
      primaryActionTitle: primaryActionTitle,
      primaryActionDetail: primaryActionDetail,
      primaryActionIsEnabled: primaryActionIsEnabled,
      rustHealth: self.rustHealth,
      previewSteps: previewSteps
    )
  }

  enum Tone: String, Equatable {
    case ready
    case info
    case warning
    case failure
    case paused

    init(badgeTone: ProjectRunControlGuide.DecisionBadge.Tone) {
      switch badgeTone {
      case .ready:
        self = .ready
      case .info:
        self = .info
      case .warning:
        self = .warning
      case .failure:
        self = .failure
      case .paused:
        self = .paused
      }
    }
  }

  struct PreviewStep: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
  }

  private static func handoffText(
    title: String,
    headline: String,
    readinessTitle: String,
    readinessDetail: String,
    signalLabel: String,
    signalDetail: String,
    primaryActionTitle: String,
    primaryActionDetail: String,
    primaryActionIsEnabled: Bool,
    rustHealth: RustFactoryHealth?,
    previewSteps: [PreviewStep]
  ) -> String {
    var sections = [
      "Compass Factory Brief",
      "",
      "Current state: \(title)",
      "Plain-English summary: \(headline)",
      "Readiness: \(readinessTitle) - \(readinessDetail)",
      "Run signal: \(signalLabel) - \(signalDetail)",
      "Recommended action: \(primaryActionTitle) (\(primaryActionIsEnabled ? "enabled" : "disabled"))",
      "Recommended action detail: \(primaryActionDetail)",
      rustHealth.map {
        "Rust factory health: \($0.title) - \($0.detail) Next action: \($0.nextAction)"
      },
      "",
      "Next run preview:",
    ].compactMap { $0 }

    if previewSteps.isEmpty {
      sections.append("- No preview steps are available.")
    } else {
      sections += previewSteps.map { step in
        "- \(step.title): \(step.detail)"
      }
    }

    return ProjectRunControlClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.handoffLimit
    )
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}
