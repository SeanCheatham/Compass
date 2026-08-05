import Foundation

public struct DraftReadinessGuide: Equatable, Sendable {
  public static let detailLimit = 160
  public static let draftPreviewLimit = 220
  public static let identifierLimit = 1_000
  public static let entryPlaceholder = "Describe the change, why it matters, and how success should look"

  public var status: Status
  public var title: String
  public var detail: String
  public var scoreLabel: String
  public var cues: [Cue]
  public var coachingPrompts: [CoachingPrompt]
  public var draftPreview: String
  public var narrationIdentifier: String

  public var allowsNarration: Bool {
    status != .ready && !draftPreview.isEmpty
  }

  public var missingSignalTitles: [String] {
    cues.filter { !$0.isSatisfied }.map(\.title)
  }

  public var satisfiedSignalTitles: [String] {
    cues.filter(\.isSatisfied).map(\.title)
  }

  public var missingSignalText: String {
    missingSignalTitles.isEmpty ? "none" : missingSignalTitles.joined(separator: ", ")
  }

  public var satisfiedSignalText: String {
    satisfiedSignalTitles.isEmpty ? "none" : satisfiedSignalTitles.joined(separator: ", ")
  }

  public init(draft rawDraft: String) {
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

  public enum Status: Equatable, Sendable {
    case empty
    case needsDetail
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

  public struct CoachingPrompt: Identifiable, Equatable, Sendable {
    public var kind: Kind

    public var id: Kind { kind }

    public var question: String {
      switch kind {
      case .outcome:
        return "What should change?"
      case .why:
        return "Who is stuck, and why?"
      case .success:
        return "How will you know it worked?"
      }
    }

    public var detail: String {
      switch kind {
      case .outcome:
        return "Name the screen, workflow, behavior, or problem Compass should improve."
      case .why:
        return "Mention the person, workflow pain, or risk this should relieve."
      case .success:
        return "Name a visible result, error, test, or check Compass can verify."
      }
    }

    public var systemImage: String {
      kind.systemImage
    }
  }

  public enum Kind: CaseIterable, Equatable, Sendable {
    case outcome
    case why
    case success

    public var title: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .why:
        return "Why"
      case .success:
        return "Success signal"
      }
    }

    public var systemImage: String {
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

public struct DraftIntakeGuide: Equatable, Sendable {
  public static let maxEntries = 6
  public static let draftTextLimit = 220
  public static let identifierLimit = 1_200
  public static let planScopeDetailLimit = 260

  private var allEntries: [Entry]
  public var entries: [Entry]

  public var isEmpty: Bool {
    allEntries.isEmpty
  }

  public var allowsNarration: Bool {
    !allEntries.isEmpty
  }

  public var totalEntryCount: Int {
    allEntries.count
  }

  public var hiddenEntryCount: Int {
    max(0, totalEntryCount - entries.count)
  }

  public var isCapped: Bool {
    hiddenEntryCount > 0
  }

  public var narrationIdentifier: String {
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

  public var status: Status {
    guard !allEntries.isEmpty else { return .empty }
    return readyCount == totalEntryCount ? .ready : .needsDetail
  }

  public var title: String {
    switch status {
    case .empty:
      return "No queued drafts"
    case .needsDetail:
      return "Draft queue needs detail"
    case .ready:
      return "Draft queue ready"
    }
  }

  public var detail: String {
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

  public var scoreLabel: String {
    guard !allEntries.isEmpty else { return "0 queued" }
    return "\(readyCount) of \(totalEntryCount) ready"
  }

  public var entryCountLabel: String {
    Self.countLabel(totalEntryCount, singular: "queued draft", plural: "queued drafts")
  }

  public var hiddenCountSentence: String {
    hiddenEntryCount == 1 ? "1 more draft remains" : "\(hiddenEntryCount) more drafts remain"
  }

  public var planScope: PlanScope {
    PlanScope(
      entries: allEntries,
      visibleEntryNumbers: Set(entries.map(\.number))
    )
  }

  public var nextAction: NextAction {
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

  public var readyCount: Int {
    planScope.readyCount
  }

  public var missingSignalTitles: [String] {
    DraftReadinessGuide.Kind.allCases.compactMap { kind in
      let isMissing = allEntries.contains { entry in
        entry.readiness.cues.contains { $0.kind == kind && !$0.isSatisfied }
      }
      return isMissing ? kind.title : nil
    }
  }

  public init(drafts: String) {
    allEntries = Self.extractDraftEntries(from: drafts)
      .enumerated()
      .map { offset, text in
        Entry(number: offset + 1, draft: text)
      }
    entries = Array(allEntries.prefix(Self.maxEntries))
  }

  public var promptText: String {
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

  public enum Status: Equatable, Sendable {
    case empty
    case needsDetail
    case ready
  }

  public struct NextAction: Equatable, Sendable {
    public var kind: NextActionKind
    public var title: String
    public var detail: String
    public var systemImage: String
  }

  public enum NextActionKind: Equatable, Sendable {
    case startDraft
    case clarifyDrafts
    case planReadyDrafts
    case sendToPlan
  }

  public struct Entry: Identifiable, Equatable, Sendable {
    public var number: Int
    public var draft: String
    public var readiness: DraftReadinessGuide

    public var id: Int { number }

    public init(number: Int, draft: String) {
      self.number = number
      self.draft = StringUtils.boundedText(draft, limit: DraftIntakeGuide.draftTextLimit)
      readiness = DraftReadinessGuide(draft: draft)
    }

    public var promptText: String {
      """
      Draft \(number): \(readiness.title) (\(readiness.scoreLabel))
      Text: \(draft)
      Signals present: \(signalList(satisfied: true))
      Missing signals: \(signalList(satisfied: false))
      """
    }

    public var satisfiedSignalTitles: [String] {
      signalTitles(satisfied: true)
    }

    public var missingSignalTitles: [String] {
      signalTitles(satisfied: false)
    }

    public var satisfiedSignalText: String {
      signalList(satisfied: true)
    }

    public var missingSignalText: String {
      signalList(satisfied: false)
    }

    public var isReadyForPlan: Bool {
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

  public struct PlanScope: Equatable, Sendable {
    public var readyEntryNumbers: [Int]
    public var waitingEntries: [WaitingEntry]
    public var summary: String
    public var detail: String

    public var readyCount: Int {
      readyEntryNumbers.count
    }

    public var waitingCount: Int {
      waitingEntries.count
    }

    public var hasReadyEntries: Bool {
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

    public struct WaitingEntry: Equatable, Sendable {
      public var number: Int
      public var missingSignalText: String
      public var isVisible: Bool
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
