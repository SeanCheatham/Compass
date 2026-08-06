import Foundation

public struct ProjectVisionGuide: Equatable, Sendable {
  public static let detailLimit = 220
  public static let visionPreviewLimit = 1_200

  public var status: Status
  public var title: String
  public var detail: String
  public var scoreLabel: String
  public var nextAction: NextAction
  public var cues: [Cue]
  public var visionPreview: String

  public var isEmpty: Bool {
    status == .empty
  }

  public var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  public var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  public var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  public var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  public init(brief: ProjectBrief, ledger: RequirementLedger = .empty) {
    visionPreview = StringUtils.boundedText(
      brief.renderedMarkdown(),
      limit: Self.visionPreviewLimit
    )

    let audience = brief.hasAudience
    let problem = brief.hasProblem
    let requirements = brief.hasRequirements
    let reconciled = ledger.reconciled(with: brief)
    let verificationReady =
      requirements && reconciled.entries.allSatisfy(\.status.countsAsComplete)

    cues = [
      Cue(
        kind: .audience,
        isSatisfied: audience,
        detail: audience ? "Who this helps is named." : "Name who this helps."
      ),
      Cue(
        kind: .problem,
        isSatisfied: problem,
        detail: problem ? "The pain or opportunity is named." : "Name the pain to remove."
      ),
      Cue(
        kind: .requirements,
        isSatisfied: requirements,
        detail: requirements
          ? "At least one product requirement is listed."
          : "Add one or more product requirements."
      ),
      Cue(
        kind: .verification,
        isSatisfied: verificationReady,
        detail: verificationReady
          ? "All product requirements are satisfied by audit."
          : (requirements
            ? "Requirements still need a successful audit."
            : "Add requirements before verification can finish.")
      ),
    ]

    let satisfiedCount = cues.filter(\.isSatisfied).count
    scoreLabel = "\(satisfiedCount) of \(cues.count) signals"
    let missingSignals = cues.filter { !$0.isSatisfied }.map(\.title)
    let missingSignalText = missingSignals.isEmpty ? "none" : missingSignals.joined(separator: ", ")

    if brief.isEmpty {
      status = .empty
      title = "Brief empty"
      detail =
        "Write who the software helps, what pain it removes, and the product requirements to deliver."
      nextAction = NextAction(
        title: "Add a first brief",
        detail:
          "Start with audience, problem, and one product requirement — or use Random idea.",
        systemImage: "square.and.pencil"
      )
    } else if audience && problem && requirements && verificationReady {
      status = .ready
      title = "Requirements verified"
      detail = "Audience, problem, and product requirements are set and audited as satisfied."
      nextAction = NextAction(
        title: "Keep shipping",
        detail: "The factory can treat the brief as a verified product contract.",
        systemImage: "checkmark.seal.fill"
      )
    } else if audience && problem && requirements {
      status = .ready
      title = "Brief ready"
      detail = "Audience, problem, and product requirements are set. Audit still pending or unsatisfied."
      nextAction = NextAction(
        title: "Run the factory loop",
        detail: "Compass audits requirements after slices ship and before declaring done.",
        systemImage: "checkmark.seal"
      )
    } else {
      status = .needsFocus
      title = "Brief needs focus"
      detail = "Missing: \(missingSignalText)."
      nextAction = NextAction(
        title: "Clarify the brief",
        detail:
          "Add the missing signals before treating the brief as load-bearing product intent.",
        systemImage: "questionmark.circle"
      )
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
  }

  public enum Status: Equatable, Sendable {
    case empty
    case needsFocus
    case ready
  }

  public struct Cue: Identifiable, Equatable, Sendable {
    public var kind: Kind
    public var isSatisfied: Bool
    public var detail: String

    public var id: Kind { kind }

    public var title: String {
      kind.title
    }

    public var systemImage: String {
      isSatisfied ? "checkmark.circle.fill" : kind.systemImage
    }
  }

  public struct NextAction: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var systemImage: String
  }

  public enum Kind: CaseIterable, Equatable, Sendable {
    case audience
    case problem
    case requirements
    case verification

    public var title: String {
      switch self {
      case .audience:
        return "Audience"
      case .problem:
        return "Problem"
      case .requirements:
        return "Requirements"
      case .verification:
        return "Verified"
      }
    }

    public var systemImage: String {
      switch self {
      case .audience:
        return "person.2"
      case .problem:
        return "exclamationmark.bubble"
      case .requirements:
        return "checklist"
      case .verification:
        return "checkmark.seal"
      }
    }
  }
}

public struct ProjectVisionClipboardPayload: Equatable, Sendable {
  public static let textLimit = 3_500

  public var text: String

  public init(guide: ProjectVisionGuide) {
    guard !guide.isEmpty else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Project Brief Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded product intent. Do not invent users, requirements, "
        + "or project decisions.",
      "- Use the brief to choose humane, product-aligned slices; keep missing signals "
        + "visible instead of silently filling them in.",
      "- Product requirements are user-owned. Preserve them unless the user updates "
        + "the brief.",
      "",
      "Status: \(guide.title)",
      "Score: \(guide.scoreLabel)",
      "Detail: \(guide.detail)",
      "Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)",
      "Signals present: \(guide.satisfiedSignalText)",
      "Missing signals: \(guide.missingSignalText)",
      "",
      "Brief:",
      guide.visionPreview,
    ]

    if !guide.cues.isEmpty {
      sections.append("")
      sections.append("Signal map:")
      for cue in guide.cues {
        sections.append(
          "- [\(cue.isSatisfied ? "present" : "missing")] \(cue.title): \(cue.detail)")
      }
    }

    text = ProjectVisionClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  public var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum ProjectVisionClipboardText {
  public static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
