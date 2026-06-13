import Foundation

package struct ProjectVisionGuide: Equatable, Sendable {
  package static let detailLimit = 220
  package static let visionPreviewLimit = 1_200
  package static let identifierLimit = 1_200

  package var status: Status
  package var title: String
  package var detail: String
  package var scoreLabel: String
  package var nextAction: NextAction
  package var cues: [Cue]
  package var visionPreview: String
  package var narrationIdentifier: String

  package var isEmpty: Bool {
    status == .empty
  }

  package var allowsNarration: Bool {
    status != .empty
  }

  package var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  package var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  package var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  package var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  package init(vision rawVision: String) {
    let vision = Self.normalizedVision(rawVision)
    visionPreview = StringUtils.boundedText(vision, limit: Self.visionPreviewLimit)

    let audience = Self.hasAudienceSignal(in: vision)
    let problem = Self.hasProblemSignal(in: vision)
    let success = Self.hasSuccessSignal(in: vision)
    let guardrails = Self.hasGuardrailSignal(in: vision)

    cues = [
      Cue(
        kind: .audience,
        isSatisfied: audience,
        detail: audience ? "The person or team is visible." : "Name who this helps."
      ),
      Cue(
        kind: .problem,
        isSatisfied: problem,
        detail: problem ? "The pain or opportunity is visible." : "Name the pain to remove."
      ),
      Cue(
        kind: .success,
        isSatisfied: success,
        detail: success ? "A visible outcome is named." : "Say how success should look."
      ),
      Cue(
        kind: .guardrails,
        isSatisfied: guardrails,
        detail: guardrails
          ? "Constraints or non-goals are visible."
          : "Add platform, privacy, must-have, or non-goal guardrails."
      ),
    ]

    let satisfiedCount = cues.filter(\.isSatisfied).count
    scoreLabel = "\(satisfiedCount) of \(cues.count) signals"
    let missingSignals = cues.filter { !$0.isSatisfied }.map(\.title)
    let missingSignalText = missingSignals.isEmpty ? "none" : missingSignals.joined(separator: ", ")

    if vision.isEmpty {
      status = .empty
      title = "Vision empty"
      detail =
        "Write who the software helps, what pain it removes, how success should look, and any must-have guardrails."
      nextAction = NextAction(
        title: "Add a first vision",
        detail: "Start with audience, problem, one visible success signal, and one guardrail.",
        systemImage: "square.and.pencil"
      )
    } else if audience && problem && success && guardrails {
      status = .ready
      title = "Vision ready"
      detail = "Audience, problem, success, and guardrails are visible."
      nextAction = NextAction(
        title: "Use vision in Plan",
        detail: "Compass can use this as product intent while choosing and reviewing slices.",
        systemImage: "checkmark.seal"
      )
    } else if audience && problem && success {
      status = .grounded
      title = "Vision grounded"
      detail =
        "Core intent is visible. Add guardrails such as platform, privacy, non-goals, or must-have constraints."
      nextAction = NextAction(
        title: "Add guardrails",
        detail: "Name what Compass must preserve, avoid, or prioritize while building.",
        systemImage: "slider.horizontal.3"
      )
    } else {
      status = .needsFocus
      title = "Vision needs focus"
      detail = "Missing: \(missingSignalText)."
      nextAction = NextAction(
        title: "Clarify the vision",
        detail:
          "Add the missing signals before treating the vision as load-bearing product intent.",
        systemImage: "questionmark.circle"
      )
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      scoreLabel: scoreLabel,
      status: status,
      cues: cues,
      visionPreview: visionPreview
    )
  }

  package enum Status: Equatable, Sendable {
    case empty
    case needsFocus
    case grounded
    case ready
  }

  package struct Cue: Identifiable, Equatable, Sendable {
    package var kind: Kind
    package var isSatisfied: Bool
    package var detail: String

    package var id: Kind { kind }

    package var title: String {
      kind.title
    }

    package var systemImage: String {
      isSatisfied ? "checkmark.circle.fill" : kind.systemImage
    }
  }

  package struct NextAction: Equatable, Sendable {
    package var title: String
    package var detail: String
    package var systemImage: String
  }

  package enum Kind: CaseIterable, Equatable, Sendable {
    case audience
    case problem
    case success
    case guardrails

    var title: String {
      switch self {
      case .audience:
        return "Audience"
      case .problem:
        return "Problem"
      case .success:
        return "Success signal"
      case .guardrails:
        return "Guardrails"
      }
    }

    var systemImage: String {
      switch self {
      case .audience:
        return "person.2"
      case .problem:
        return "exclamationmark.bubble"
      case .success:
        return "checkmark.seal"
      case .guardrails:
        return "slider.horizontal.3"
      }
    }
  }

  private static func hasAudienceSignal(in vision: String) -> Bool {
    containsAnyWord(
      in: vision,
      [
        "admin",
        "client",
        "customer",
        "customers",
        "developer",
        "developers",
        "non-developer",
        "non-engineer",
        "operator",
        "operators",
        "owner",
        "people",
        "person",
        "student",
        "team",
        "teams",
        "user",
        "users",
      ]
    ) || vision.localizedCaseInsensitiveContains("for ")
  }

  private static func hasProblemSignal(in vision: String) -> Bool {
    containsAnyWord(
      in: vision,
      [
        "blocked",
        "confusing",
        "error",
        "errors",
        "friction",
        "hard",
        "lost",
        "manual",
        "need",
        "needs",
        "pain",
        "problem",
        "risk",
        "slow",
        "stuck",
      ]
    )
      || vision.localizedCaseInsensitiveContains("because")
      || vision.localizedCaseInsensitiveContains("so that")
  }

  private static func hasSuccessSignal(in vision: String) -> Bool {
    containsAnyWord(
      in: vision,
      [
        "appears",
        "done",
        "metric",
        "metrics",
        "passes",
        "shows",
        "success",
        "succeeds",
        "test",
        "tests",
        "verify",
        "visible",
      ]
    )
      || vision.localizedCaseInsensitiveContains("no longer")
      || vision.localizedCaseInsensitiveContains("when ")
  }

  private static func hasGuardrailSignal(in vision: String) -> Bool {
    containsAnyWord(
      in: vision,
      [
        "apple",
        "avoid",
        "budget",
        "constraint",
        "deadline",
        "foundation",
        "guardrail",
        "macos",
        "must",
        "native",
        "never",
        "non-goal",
        "offline",
        "privacy",
        "secure",
        "security",
        "should",
      ]
    )
  }

  private static func normalizedVision(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func containsAnyWord(in text: String, _ words: [String]) -> Bool {
    words.contains { word in
      containsWord(word, in: text)
    }
  }

  private static func containsWord(_ word: String, in text: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: word)
    let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
    return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    scoreLabel: String,
    status: Status,
    cues: [Cue],
    visionPreview: String
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "score:\(scoreLabel)",
      "status:\(status)",
      "present:\(cues.filter(\.isSatisfied).map(\.title).joined(separator: ","))",
      "missing:\(cues.filter { !$0.isSatisfied }.map(\.title).joined(separator: ","))",
      "vision:\(visionPreview)",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

package struct ProjectVisionClipboardPayload: Equatable, Sendable {
  package static let textLimit = 3_500

  package var text: String

  package init(guide: ProjectVisionGuide) {
    guard !guide.isEmpty else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Project Vision Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded product intent. Do not invent users, requirements, "
        + "technical constraints, success criteria, or project decisions.",
      "- Use the vision to choose humane, product-aligned slices; keep missing signals "
        + "visible instead of silently filling them in.",
      "- Guardrails are constraints and non-goals. Preserve them unless the user updates "
        + "the vision.",
      "",
      "Status: \(guide.title)",
      "Score: \(guide.scoreLabel)",
      "Detail: \(guide.detail)",
      "Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)",
      "Signals present: \(guide.satisfiedSignalText)",
      "Missing signals: \(guide.missingSignalText)",
      "",
      "Vision:",
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

  package var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum ProjectVisionClipboardText {
  package static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
