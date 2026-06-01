import Foundation

struct DraftReadinessGuide: Equatable, Sendable {
  static let detailLimit = 160
  static let draftPreviewLimit = 220
  static let identifierLimit = 1_000

  var status: Status
  var title: String
  var detail: String
  var scoreLabel: String
  var cues: [Cue]
  var coachingPrompts: [CoachingPrompt]
  var draftPreview: String
  var narrationIdentifier: String

  var allowsNarration: Bool {
    status != .ready && !draftPreview.isEmpty
  }

  var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  init(draft rawDraft: String) {
    let draft = DraftRefinementService.normalizeDraft(rawDraft)
    draftPreview = StringUtils.boundedText(draft, limit: Self.draftPreviewLimit)
    let outcome = Self.hasOutcomeSignal(in: draft)
    let why = Self.hasWhySignal(in: draft)
    let success = Self.hasSuccessSignal(in: draft)
    let vagueSuccess = !success && Self.hasVagueSuccessSignal(in: draft)

    cues = [
      Cue(
        kind: .outcome,
        isSatisfied: outcome,
        detail: outcome ? "Desired change is named." : "Name the change or problem."
      ),
      Cue(
        kind: .why,
        isSatisfied: why,
        detail: why ? "Reason is visible." : "Add why it matters."
      ),
      Cue(
        kind: .success,
        isSatisfied: success,
        detail: success
          ? "Done signal is visible."
          : vagueSuccess
            ? "Replace vague words like works or done with visible proof."
            : "Say how done should look."
      ),
    ]
    coachingPrompts = cues.filter { !$0.isSatisfied }.map { CoachingPrompt(kind: $0.kind) }

    let satisfiedCount = cues.filter(\.isSatisfied).count
    scoreLabel = "\(satisfiedCount) of \(cues.count)"

    if draft.isEmpty {
      status = .empty
      title = "Start with the outcome"
      detail = "Name the change you want Compass to make."
    } else if satisfiedCount == cues.count {
      status = .ready
      title = "Ready for Plan"
      detail = "This draft has enough signal for a focused first slice."
    } else {
      status = .needsDetail
      title = "Add one more signal"
      detail = Self.missingDetail(for: cues)
    }

    detail = Self.bounded(detail)
    narrationIdentifier = Self.narrationIdentifier(
      draft: draftPreview,
      title: title,
      detail: detail,
      scoreLabel: scoreLabel,
      status: status,
      cues: cues,
      coachingPrompts: coachingPrompts
    )
  }

  enum Status: Equatable, Sendable {
    case empty
    case needsDetail
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

  struct CoachingPrompt: Identifiable, Equatable, Sendable {
    var kind: Kind

    var id: Kind { kind }

    var question: String {
      switch kind {
      case .outcome:
        return "What should change?"
      case .why:
        return "Who is stuck, and why?"
      case .success:
        return "How will you know it worked?"
      }
    }

    var detail: String {
      switch kind {
      case .outcome:
        return "Name the screen, workflow, behavior, or problem Compass should improve."
      case .why:
        return "Mention the person, workflow pain, or risk this should relieve."
      case .success:
        return "Name a visible result, error, test, or check Compass can verify."
      }
    }

    var systemImage: String {
      kind.systemImage
    }
  }

  enum Kind: CaseIterable, Equatable, Sendable {
    case outcome
    case why
    case success

    var title: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .why:
        return "Why"
      case .success:
        return "Success signal"
      }
    }

    var systemImage: String {
      switch self {
      case .outcome:
        return "target"
      case .why:
        return "person.crop.circle.badge.questionmark"
      case .success:
        return "checkmark.seal"
      }
    }
  }

  private static func hasOutcomeSignal(in draft: String) -> Bool {
    draft.split(whereSeparator: \.isWhitespace).count >= 3
  }

  private static func hasWhySignal(in draft: String) -> Bool {
    containsAnyWord(
      in: draft,
      [
        "because",
        "confusing",
        "customer",
        "customers",
        "hard",
        "non-engineer",
        "pain",
        "slow",
        "user",
        "users",
      ]
    )
      || draft.localizedCaseInsensitiveContains("so that")
      || draft.localizedCaseInsensitiveContains("why it matters")
  }

  private static func hasSuccessSignal(in draft: String) -> Bool {
    containsAnyWord(
      in: draft,
      [
        "appears",
        "check",
        "checks",
        "error",
        "fails",
        "passes",
        "shows",
        "test",
        "tests",
        "verify",
        "visible",
      ]
    )
      || draft.localizedCaseInsensitiveContains("no longer")
  }

  private static func hasVagueSuccessSignal(in draft: String) -> Bool {
    let normalized =
      draft
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let vaguePhrases = [
      "all done",
      "complete",
      "completed",
      "done",
      "everything works",
      "it works",
      "looks good",
      "works",
    ]

    return vaguePhrases.contains { phrase in
      containsWord(phrase, in: normalized)
    }
  }

  private static func missingDetail(for cues: [Cue]) -> String {
    let missing = cues.filter { !$0.isSatisfied }.map(\.title)
    guard !missing.isEmpty else {
      return "This draft has enough signal for a focused first slice."
    }
    return "Missing: \(missing.joined(separator: ", "))."
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

  private static func bounded(_ text: String) -> String {
    guard text.count > detailLimit else { return text }
    guard detailLimit > 3 else { return String(text.prefix(detailLimit)) }
    return String(text.prefix(detailLimit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private static func narrationIdentifier(
    draft: String,
    title: String,
    detail: String,
    scoreLabel: String,
    status: Status,
    cues: [Cue],
    coachingPrompts: [CoachingPrompt]
  ) -> String {
    let raw = [
      "draft:\(draft)",
      "title:\(title)",
      "detail:\(detail)",
      "score:\(scoreLabel)",
      "status:\(status)",
      "present:\(cues.filter(\.isSatisfied).map(\.title).joined(separator: ","))",
      "missing:\(cues.filter { !$0.isSatisfied }.map(\.title).joined(separator: ","))",
      "questions:\(coachingPrompts.map(\.question).joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

struct DraftIntakeGuide: Equatable, Sendable {
  static let maxEntries = 6
  static let draftTextLimit = 220
  static let identifierLimit = 1_200

  private var allEntries: [Entry]
  var entries: [Entry]

  var isEmpty: Bool {
    allEntries.isEmpty
  }

  var allowsNarration: Bool {
    !allEntries.isEmpty
  }

  var totalEntryCount: Int {
    allEntries.count
  }

  var hiddenEntryCount: Int {
    max(0, totalEntryCount - entries.count)
  }

  var isCapped: Bool {
    hiddenEntryCount > 0
  }

  var narrationIdentifier: String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "status:\(status)",
      "score:\(scoreLabel)",
      "next:\(nextAction.title) - \(nextAction.detail)",
      "total:\(totalEntryCount)",
      "hidden:\(hiddenEntryCount)",
      "entries:\(entries.map(\.narrationIdentifierFragment).joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }

  var status: Status {
    guard !allEntries.isEmpty else { return .empty }
    return readyCount == totalEntryCount ? .ready : .needsDetail
  }

  var title: String {
    switch status {
    case .empty:
      return "No queued drafts"
    case .needsDetail:
      return "Draft queue needs detail"
    case .ready:
      return "Draft queue ready"
    }
  }

  var detail: String {
    switch status {
    case .empty:
      return "Add one clear direction above when you are ready."
    case .ready:
      if isCapped {
        return
          "All \(entryCountLabel) have the outcome, why, and done signal. Showing first \(entries.count) in the checklist."
      }
      return "Every queued draft names the outcome, why it matters, and how done should look."
    case .needsDetail:
      let missing =
        missingSignalTitles.isEmpty
        ? "more detail"
        : missingSignalTitles.joined(separator: ", ")
      let capNotice =
        isCapped
        ? " Showing first \(entries.count); \(hiddenCountSentence) in the raw draft list."
        : ""
      return
        "\(entryCountLabel). \(scoreLabel).\(capNotice) Missing across queue: \(missing)."
    }
  }

  var scoreLabel: String {
    guard !allEntries.isEmpty else { return "0 queued" }
    return "\(readyCount) of \(totalEntryCount) ready"
  }

  var entryCountLabel: String {
    Self.countLabel(totalEntryCount, singular: "queued draft", plural: "queued drafts")
  }

  var hiddenCountSentence: String {
    hiddenEntryCount == 1 ? "1 more draft remains" : "\(hiddenEntryCount) more drafts remain"
  }

  var nextAction: NextAction {
    switch status {
    case .empty:
      return NextAction(
        kind: .startDraft,
        title: "Add a first draft",
        detail:
          "Write one direction above; Compass will check whether it names the outcome, why, and proof.",
        systemImage: "square.and.pencil"
      )
    case .ready:
      let scope = isCapped ? " The visible checklist is ready; preserve hidden raw drafts." : ""
      return NextAction(
        kind: .sendToPlan,
        title: "Send the queue to Plan",
        detail:
          "Turn the first ready direction into a commit-sized handoff, then keep the queue ordered.\(scope)",
        systemImage: "arrow.forward.circle"
      )
    case .needsDetail:
      if readyCount > 0 {
        return NextAction(
          kind: .planReadyDrafts,
          title: readyCount == 1 ? "Plan the ready draft" : "Plan ready drafts",
          detail:
            "\(Self.countLabel(readyCount, singular: "draft is", plural: "drafts are")) ready; keep the rest queued for the missing signals.",
          systemImage: "arrowshape.turn.up.right.circle"
        )
      }
      let missing =
        missingSignalTitles.isEmpty
        ? "the missing details"
        : missingSignalTitles.joined(separator: ", ")
      return NextAction(
        kind: .clarifyDrafts,
        title: "Clarify before Plan",
        detail: "Add \(missing.lowercased()) so Plan can make a focused first slice.",
        systemImage: "questionmark.circle"
      )
    }
  }

  var readyCount: Int {
    allEntries.filter { $0.readiness.status == .ready }.count
  }

  var missingSignalTitles: [String] {
    DraftReadinessGuide.Kind.allCases.compactMap { kind in
      let isMissing = allEntries.contains { entry in
        entry.readiness.cues.contains { $0.kind == kind && !$0.isSatisfied }
      }
      return isMissing ? kind.title : nil
    }
  }

  init(drafts: String) {
    allEntries = Self.extractDraftEntries(from: drafts)
      .enumerated()
      .map { offset, text in
        Entry(number: offset + 1, draft: text)
      }
    entries = Array(allEntries.prefix(Self.maxEntries))
  }

  var promptText: String {
    guard !allEntries.isEmpty else {
      return "_(no draft readiness signals)_"
    }

    var sections = entries.map(\.promptText)
    if isCapped {
      sections.append(
        """
        Readiness map note: Showing first \(entries.count) of \(totalEntryCount) drafts. \(hiddenCountSentence) in the raw drafts above; preserve them instead of assuming they were checked here.
        """
      )
    }
    return sections.joined(separator: "\n\n")
  }

  enum Status: Equatable, Sendable {
    case empty
    case needsDetail
    case ready
  }

  struct NextAction: Equatable, Sendable {
    var kind: NextActionKind
    var title: String
    var detail: String
    var systemImage: String
  }

  enum NextActionKind: Equatable, Sendable {
    case startDraft
    case clarifyDrafts
    case planReadyDrafts
    case sendToPlan
  }

  struct Entry: Identifiable, Equatable, Sendable {
    var number: Int
    var draft: String
    var readiness: DraftReadinessGuide

    var id: Int { number }

    init(number: Int, draft: String) {
      self.number = number
      self.draft = StringUtils.boundedText(draft, limit: DraftIntakeGuide.draftTextLimit)
      readiness = DraftReadinessGuide(draft: draft)
    }

    var promptText: String {
      """
      Draft \(number): \(readiness.title) (\(readiness.scoreLabel))
      Text: \(draft)
      Signals present: \(signalList(satisfied: true))
      Missing signals: \(signalList(satisfied: false))
      """
    }

    var satisfiedSignalTitles: [String] {
      signalTitles(satisfied: true)
    }

    var missingSignalTitles: [String] {
      signalTitles(satisfied: false)
    }

    var satisfiedSignalText: String {
      signalList(satisfied: true)
    }

    var missingSignalText: String {
      signalList(satisfied: false)
    }

    fileprivate var narrationIdentifierFragment: String {
      [
        "draft\(number):\(draft)",
        "status:\(readiness.title)",
        "score:\(readiness.scoreLabel)",
        "present:\(satisfiedSignalText)",
        "missing:\(missingSignalText)",
      ].joined(separator: ";")
    }

    private func signalTitles(satisfied: Bool) -> [String] {
      readiness.cues
        .filter { $0.isSatisfied == satisfied }
        .map(\.title)
    }

    private func signalList(satisfied: Bool) -> String {
      let signals = readiness.cues
        .filter { $0.isSatisfied == satisfied }
        .map(\.title)
      return signals.isEmpty ? "none" : signals.joined(separator: ", ")
    }
  }

  private static func extractDraftEntries(from drafts: String) -> [String] {
    let normalized =
      drafts
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)

    let listEntries = extractListEntries(from: lines)
    if !listEntries.isEmpty {
      return listEntries
    }

    return normalized.components(separatedBy: "\n\n")
      .map(normalizedDraftText)
      .filter { !$0.isEmpty }
  }

  private static func extractListEntries(from lines: [String]) -> [String] {
    var entries: [String] = []
    var current: [String] = []
    var sawListEntry = false

    func flush() {
      let text = normalizedDraftText(current.joined(separator: " "))
      if !text.isEmpty {
        entries.append(text)
      }
      current.removeAll()
    }

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }

      if let listEntry = PlainTextListPrefix.strippedEntry(from: trimmed) {
        sawListEntry = true
        flush()
        current.append(listEntry)
      } else if sawListEntry {
        current.append(trimmed)
      }
    }

    flush()
    return sawListEntry ? entries : []
  }

  private static func normalizedDraftText(_ text: String) -> String {
    StringUtils.boundedText(text, limit: Int.max)
  }

  private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
    count == 1 ? "1 \(singular)" : "\(count) \(plural)"
  }
}

struct DraftIntakeClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_500

  var text: String

  init(guide: DraftIntakeGuide) {
    guard !guide.isEmpty else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Draft Queue Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded draft-intake context. Do not invent user intent, "
        + "files, commands, success criteria, or extra scope.",
      "- Ready drafts can be turned into one commit-sized Immediate Work handoff.",
      "- Drafts missing signals need clarification or rewriting before load-bearing Plan work.",
      "- If the queue is capped, preserve hidden raw drafts instead of assuming they were checked.",
      "",
      "Status: \(guide.title)",
      "Score: \(guide.scoreLabel)",
      "Detail: \(guide.detail)",
      "Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)",
      "Queue: \(guide.entryCountLabel)",
    ]

    if guide.isCapped {
      sections.append("Visible checklist: first \(guide.entries.count) of \(guide.totalEntryCount)")
      sections.append("Hidden drafts: \(guide.hiddenCountSentence) in the raw draft list.")
    }

    if !guide.missingSignalTitles.isEmpty {
      sections.append("")
      sections.append("Missing across queue: \(guide.missingSignalTitles.joined(separator: ", "))")
    }

    sections.append("")
    sections.append("Drafts:")
    for entry in guide.entries {
      sections.append("Draft #\(entry.number)")
      sections.append("Text: \(entry.draft)")
      sections.append("Readiness: \(entry.readiness.title) (\(entry.readiness.scoreLabel))")
      sections.append("Signals present: \(entry.satisfiedSignalText)")
      sections.append("Missing signals: \(entry.missingSignalText)")

      if !entry.readiness.coachingPrompts.isEmpty {
        sections.append("Clarify before planning:")
        for prompt in entry.readiness.coachingPrompts {
          sections.append("- \(prompt.question) \(prompt.detail)")
        }
      }
    }

    text = DraftIntakeClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum DraftIntakeClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
