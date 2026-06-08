import Foundation

struct ProjectLessonsGuide: Equatable, Sendable {
  static let detailLimit = 240
  static let lessonsPreviewLimit = 1_200
  static let identifierLimit = 1_200

  var status: Status
  var title: String
  var detail: String
  var scoreLabel: String
  var nextAction: NextAction
  var cues: [Cue]
  var entryCount: Int
  var lessonsPreview: String
  var narrationIdentifier: String

  var isEmpty: Bool {
    status == .empty
  }

  var allowsNarration: Bool {
    !isEmpty
  }

  var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  init(lessons rawLessons: String) {
    let lessons = Self.normalizedLessons(rawLessons)
    lessonsPreview = StringUtils.boundedText(lessons, limit: Self.lessonsPreviewLimit)
    entryCount = Self.entryCount(in: rawLessons)

    let learning = Self.hasLearningSignal(in: lessons)
    let proof = Self.hasProofSignal(in: lessons)
    let decision = Self.hasDecisionSignal(in: lessons)
    let reuse = Self.hasReuseSignal(in: lessons)

    cues = [
      Cue(
        kind: .learning,
        isSatisfied: learning,
        detail: learning ? "The lesson names what changed or was learned." : "Name the learning."
      ),
      Cue(
        kind: .proof,
        isSatisfied: proof,
        detail: proof ? "Verification or evidence is visible." : "Name the proof or signal."
      ),
      Cue(
        kind: .decision,
        isSatisfied: decision,
        detail: decision
          ? "A decision, guardrail, or preference is visible."
          : "Name the decision or guardrail."
      ),
      Cue(
        kind: .reuse,
        isSatisfied: reuse,
        detail: reuse
          ? "Future-use guidance is visible."
          : "Say when Compass should reuse this lesson."
      ),
    ]

    let satisfiedCount = cues.filter(\.isSatisfied).count
    scoreLabel = "\(satisfiedCount) of \(cues.count) signals"
    let missingSignals = cues.filter { !$0.isSatisfied }.map(\.title)
    let missingSignalText = missingSignals.isEmpty ? "none" : missingSignals.joined(separator: ", ")

    if lessons.isEmpty {
      status = .empty
      title = "Lessons empty"
      detail =
        "Captured lessons will help future runs avoid repeated mistakes and preserve good decisions."
      nextAction = NextAction(
        title: "Capture a first lesson",
        detail: "Add what changed, the proof behind it, and how Compass should reuse it later.",
        systemImage: "square.and.pencil"
      )
    } else if learning && proof && decision && reuse {
      status = .ready
      title = "Lessons reusable"
      detail = "Learning, proof, decision, and future-use guidance are visible."
      nextAction = NextAction(
        title: "Reuse in Plan",
        detail: "Compass can treat these lessons as project memory during future planning.",
        systemImage: "checkmark.seal"
      )
    } else {
      status = .needsFocus
      title = "Lessons need context"
      detail = "Missing: \(missingSignalText)."
      nextAction = NextAction(
        title: "Tighten lessons",
        detail: "Add the missing signals so future runs know how to apply the learning.",
        systemImage: "text.magnifyingglass"
      )
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      scoreLabel: scoreLabel,
      status: status,
      cues: cues,
      entryCount: entryCount,
      lessonsPreview: lessonsPreview
    )
  }

  enum Status: Equatable, Sendable {
    case empty
    case needsFocus
    case ready
  }

  struct Cue: Identifiable, Equatable, Sendable {
    var kind: Kind
    var isSatisfied: Bool
    var detail: String

    var id: Kind { kind }

    var title: String {
      kind.title
    }

    var systemImage: String {
      isSatisfied ? "checkmark.circle.fill" : kind.systemImage
    }
  }

  struct NextAction: Equatable, Sendable {
    var title: String
    var detail: String
    var systemImage: String
  }

  enum Kind: CaseIterable, Equatable, Sendable {
    case learning
    case proof
    case decision
    case reuse

    var title: String {
      switch self {
      case .learning:
        return "Learning"
      case .proof:
        return "Proof"
      case .decision:
        return "Decision"
      case .reuse:
        return "Reuse cue"
      }
    }

    var systemImage: String {
      switch self {
      case .learning:
        return "lightbulb"
      case .proof:
        return "checkmark.seal"
      case .decision:
        return "slider.horizontal.3"
      case .reuse:
        return "arrow.triangle.2.circlepath"
      }
    }
  }

  private static func hasLearningSignal(in lessons: String) -> Bool {
    containsAnyWord(
      in: lessons,
      [
        "changed",
        "discovered",
        "fixed",
        "found",
        "improved",
        "learned",
        "lesson",
        "noticed",
        "solved",
      ]
    ) || lessons.localizedCaseInsensitiveContains("because")
  }

  private static func hasProofSignal(in lessons: String) -> Bool {
    containsAnyWord(
      in: lessons,
      [
        "evidence",
        "failed",
        "log",
        "passed",
        "proof",
        "screenshot",
        "test",
        "tests",
        "verified",
        "verify",
      ]
    )
  }

  private static func hasDecisionSignal(in lessons: String) -> Bool {
    containsAnyWord(
      in: lessons,
      [
        "avoid",
        "decision",
        "guardrail",
        "must",
        "never",
        "prefer",
        "preserve",
        "should",
      ]
    )
  }

  private static func hasReuseSignal(in lessons: String) -> Bool {
    containsAnyWord(
      in: lessons,
      [
        "again",
        "before",
        "future",
        "next",
        "reuse",
        "when",
      ]
    ) || lessons.localizedCaseInsensitiveContains("next time")
  }

  private static func normalizedLessons(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func entryCount(in text: String) -> Int {
    let entries =
      text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return entries.count
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
    entryCount: Int,
    lessonsPreview: String
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "score:\(scoreLabel)",
      "status:\(status)",
      "entries:\(entryCount)",
      "present:\(cues.filter(\.isSatisfied).map(\.title).joined(separator: ","))",
      "missing:\(cues.filter { !$0.isSatisfied }.map(\.title).joined(separator: ","))",
      "lessons:\(lessonsPreview)",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

struct ProjectLessonsClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_200

  var text: String

  init(guide: ProjectLessonsGuide) {
    guard !guide.isEmpty else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Project Lessons Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded project memory. Do not invent decisions, proof, "
        + "files, commands, outcomes, or future requirements.",
      "- Use lessons to avoid repeated mistakes and preserve confirmed preferences.",
      "- If a lesson is missing proof or reuse guidance, keep that gap visible.",
      "",
      "Status: \(guide.title)",
      "Score: \(guide.scoreLabel)",
      "Entries: \(guide.entryCount)",
      "Detail: \(guide.detail)",
      "Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)",
      "Signals present: \(guide.satisfiedSignalText)",
      "Missing signals: \(guide.missingSignalText)",
      "",
      "Lessons:",
      guide.lessonsPreview,
    ]

    if !guide.cues.isEmpty {
      sections.append("")
      sections.append("Signal map:")
      for cue in guide.cues {
        sections.append(
          "- [\(cue.isSatisfied ? "present" : "missing")] \(cue.title): \(cue.detail)")
      }
    }

    text = ProjectLessonsClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum ProjectLessonsClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
