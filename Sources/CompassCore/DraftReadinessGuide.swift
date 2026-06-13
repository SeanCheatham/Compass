import Foundation

package struct DraftReadinessGuide: Equatable, Sendable {
  package static let detailLimit = 160
  package static let draftPreviewLimit = 220
  package static let identifierLimit = 1_000
  package static let entryPlaceholder = "Describe the change, why it matters, and how success should look"

  package var status: Status
  package var title: String
  package var detail: String
  package var scoreLabel: String
  package var cues: [Cue]
  package var coachingPrompts: [CoachingPrompt]
  package var draftPreview: String
  package var narrationIdentifier: String

  package var allowsNarration: Bool {
    status != .ready && !draftPreview.isEmpty
  }

  package var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  package var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  package var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  package var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  package init(draft rawDraft: String) {
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

  package enum Status: Equatable, Sendable {
    case empty
    case needsDetail
    case ready
  }

  package struct Cue: Identifiable, Equatable, Sendable {
    var kind: Kind
    var isSatisfied: Bool
    var detail: String

    package var id: Kind { kind }

    var title: String {
      kind.title
    }

    var systemImage: String {
      isSatisfied ? "checkmark.circle.fill" : kind.systemImage
    }
  }

  package struct CoachingPrompt: Identifiable, Equatable, Sendable {
    var kind: Kind

    package var id: Kind { kind }

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

  package enum Kind: CaseIterable, Equatable, Sendable {
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

package struct DraftIntakeGuide: Equatable, Sendable {
  package static let maxEntries = 6
  package static let draftTextLimit = 220
  package static let identifierLimit = 1_200
  package static let planScopeDetailLimit = 260

  private var allEntries: [Entry]
  package var entries: [Entry]

  package var isEmpty: Bool {
    allEntries.isEmpty
  }

  package var allowsNarration: Bool {
    !allEntries.isEmpty
  }

  package var totalEntryCount: Int {
    allEntries.count
  }

  package var hiddenEntryCount: Int {
    max(0, totalEntryCount - entries.count)
  }

  package var isCapped: Bool {
    hiddenEntryCount > 0
  }

  package var narrationIdentifier: String {
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

  package var status: Status {
    guard !allEntries.isEmpty else { return .empty }
    return readyCount == totalEntryCount ? .ready : .needsDetail
  }

  package var title: String {
    switch status {
    case .empty:
      return "No queued drafts"
    case .needsDetail:
      return "Draft queue needs detail"
    case .ready:
      return "Draft queue ready"
    }
  }

  package var detail: String {
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

  package var scoreLabel: String {
    guard !allEntries.isEmpty else { return "0 queued" }
    return "\(readyCount) of \(totalEntryCount) ready"
  }

  package var entryCountLabel: String {
    Self.countLabel(totalEntryCount, singular: "queued draft", plural: "queued drafts")
  }

  package var hiddenCountSentence: String {
    hiddenEntryCount == 1 ? "1 more draft remains" : "\(hiddenEntryCount) more drafts remain"
  }

  package var planScope: PlanScope {
    PlanScope(
      entries: allEntries,
      visibleEntryNumbers: Set(entries.map(\.number))
    )
  }

  package var nextAction: NextAction {
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
        detail: "\(planScope.detail)\(scope)",
        systemImage: "arrow.forward.circle"
      )
    case .needsDetail:
      if readyCount > 0 {
        return NextAction(
          kind: .planReadyDrafts,
          title: readyCount == 1 ? "Plan the ready draft" : "Plan ready drafts",
          detail: planScope.detail,
          systemImage: "arrowshape.turn.up.right.circle"
        )
      }
      return NextAction(
        kind: .clarifyDrafts,
        title: "Clarify before Plan",
        detail: planScope.detail,
        systemImage: "questionmark.circle"
      )
    }
  }

  package var readyCount: Int {
    planScope.readyCount
  }

  package var missingSignalTitles: [String] {
    DraftReadinessGuide.Kind.allCases.compactMap { kind in
      let isMissing = allEntries.contains { entry in
        entry.readiness.cues.contains { $0.kind == kind && !$0.isSatisfied }
      }
      return isMissing ? kind.title : nil
    }
  }

  package init(drafts: String) {
    allEntries = Self.extractDraftEntries(from: drafts)
      .enumerated()
      .map { offset, text in
        Entry(number: offset + 1, draft: text)
      }
    entries = Array(allEntries.prefix(Self.maxEntries))
  }

  package var promptText: String {
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

  package enum Status: Equatable, Sendable {
    case empty
    case needsDetail
    case ready
  }

  package struct NextAction: Equatable, Sendable {
    var kind: NextActionKind
    var title: String
    var detail: String
    var systemImage: String
  }

  package enum NextActionKind: Equatable, Sendable {
    case startDraft
    case clarifyDrafts
    case planReadyDrafts
    case sendToPlan
  }

  package struct Entry: Identifiable, Equatable, Sendable {
    var number: Int
    var draft: String
    var readiness: DraftReadinessGuide

    package var id: Int { number }

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

    var isReadyForPlan: Bool {
      readiness.status == .ready
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

  package struct PlanScope: Equatable, Sendable {
    var readyEntryNumbers: [Int]
    var waitingEntries: [WaitingEntry]
    var summary: String
    var detail: String

    var readyCount: Int {
      readyEntryNumbers.count
    }

    var waitingCount: Int {
      waitingEntries.count
    }

    var hasReadyEntries: Bool {
      readyCount > 0
    }

    fileprivate init(entries: [Entry], visibleEntryNumbers: Set<Int>) {
      readyEntryNumbers =
        entries
        .filter(\.isReadyForPlan)
        .map(\.number)
      waitingEntries =
        entries
        .filter { !$0.isReadyForPlan }
        .map {
          WaitingEntry(
            number: $0.number,
            missingSignalText: $0.missingSignalText,
            isVisible: visibleEntryNumbers.contains($0.number)
          )
        }

      summary = Self.summary(
        readyCount: readyEntryNumbers.count, waitingCount: waitingEntries.count)
      detail = StringUtils.boundedText(
        Self.detail(
          readyEntryNumbers: readyEntryNumbers,
          waitingEntries: waitingEntries,
          visibleEntryNumbers: visibleEntryNumbers
        ),
        limit: DraftIntakeGuide.planScopeDetailLimit
      )
    }

    struct WaitingEntry: Equatable, Sendable {
      var number: Int
      var missingSignalText: String
      var isVisible: Bool
    }

    private static func summary(readyCount: Int, waitingCount: Int) -> String {
      switch (readyCount, waitingCount) {
      case (0, 0):
        return "No queued drafts."
      case (0, _):
        return
          "\(countLabel(waitingCount, singular: "draft needs", plural: "drafts need")) detail before Plan."
      case (_, 0):
        return
          "\(countLabel(readyCount, singular: "draft is", plural: "drafts are")) ready for Plan."
      default:
        return
          "\(countLabel(readyCount, singular: "draft is", plural: "drafts are")) ready for Plan; \(countLabel(waitingCount, singular: "draft needs", plural: "drafts need")) detail."
      }
    }

    private static func detail(
      readyEntryNumbers: [Int],
      waitingEntries: [WaitingEntry],
      visibleEntryNumbers: Set<Int>
    ) -> String {
      let visibleReadyEntryNumbers = readyEntryNumbers.filter { visibleEntryNumbers.contains($0) }
      let hiddenReadyCount = readyEntryNumbers.count - visibleReadyEntryNumbers.count
      let visibleWaitingEntries = waitingEntries.filter(\.isVisible)
      let hiddenWaitingCount = waitingEntries.count - visibleWaitingEntries.count

      if readyEntryNumbers.isEmpty, waitingEntries.isEmpty {
        return "Add one clear direction above before planning."
      }

      if readyEntryNumbers.isEmpty {
        return
          "Clarify before Plan: \(waitingSentence(for: visibleWaitingEntries, hiddenCount: hiddenWaitingCount))."
      }

      if waitingEntries.isEmpty {
        let hiddenSuffix =
          hiddenReadyCount > 0
          ? " \(countLabel(hiddenReadyCount, singular: "hidden ready draft remains", plural: "hidden ready drafts remain")) in the raw queue."
          : ""
        return
          "Plan can use \(draftNumberList(visibleReadyEntryNumbers)) while preserving queue order.\(hiddenSuffix)"
      }

      let readyTarget =
        visibleReadyEntryNumbers.isEmpty
        ? countLabel(readyEntryNumbers.count, singular: "ready draft", plural: "ready drafts")
        : draftNumberList(visibleReadyEntryNumbers)
      return
        "Plan can use \(readyTarget) first; keep the rest queued: \(waitingSentence(for: visibleWaitingEntries, hiddenCount: hiddenWaitingCount))."
    }

    private static func waitingSentence(
      for entries: [WaitingEntry],
      hiddenCount: Int
    ) -> String {
      let visible = entries.prefix(3).map { entry in
        "Draft #\(entry.number) needs \(entry.missingSignalText)"
      }
      let extraVisibleCount = entries.count - visible.count
      let hiddenLabel =
        hiddenCount > 0
        ? countLabel(hiddenCount, singular: "hidden draft needs", plural: "hidden drafts need")
          + " detail"
        : nil
      let extraVisibleLabel =
        extraVisibleCount > 0
        ? countLabel(extraVisibleCount, singular: "draft also needs", plural: "drafts also need")
          + " detail"
        : nil
      let hiddenAndExtra = [extraVisibleLabel, hiddenLabel].compactMap(\.self)

      if hiddenAndExtra.isEmpty {
        return visible.joined(separator: "; ")
      }
      if visible.isEmpty {
        return hiddenAndExtra.joined(separator: "; ")
      }
      return visible.joined(separator: "; ") + "; " + hiddenAndExtra.joined(separator: "; ")
    }

    private static func draftNumberList(_ numbers: [Int]) -> String {
      let labels = numbers.map { "Draft #\($0)" }
      switch labels.count {
      case 0:
        return "no drafts"
      case 1:
        return labels[0]
      case 2:
        return labels.joined(separator: " or ")
      default:
        return labels.dropLast().joined(separator: ", ") + ", or \(labels.last ?? "")"
      }
    }

    private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
      count == 1 ? "1 \(singular)" : "\(count) \(plural)"
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

package struct DraftIntakeClipboardPayload: Equatable, Sendable {
  package static let textLimit = 3_500

  package var text: String

  package init(guide: DraftIntakeGuide) {
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
      "Plan scope: \(guide.planScope.summary)",
      "Plan scope detail: \(guide.planScope.detail)",
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

  package var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum DraftIntakeClipboardText {
  package static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
