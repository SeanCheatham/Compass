import Foundation

struct DraftReadinessGuide: Equatable, Sendable {
  static let detailLimit = 160

  var status: Status
  var title: String
  var detail: String
  var scoreLabel: String
  var cues: [Cue]

  init(draft rawDraft: String) {
    let draft = DraftRefinementService.normalizeDraft(rawDraft)
    let outcome = Self.hasOutcomeSignal(in: draft)
    let why = Self.hasWhySignal(in: draft)
    let success = Self.hasSuccessSignal(in: draft)

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
        detail: success ? "Done signal is visible." : "Say how done should look."
      ),
    ]

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
        "done",
        "error",
        "fails",
        "passes",
        "shows",
        "test",
        "tests",
        "verify",
        "visible",
        "when",
        "works",
      ]
    )
      || draft.localizedCaseInsensitiveContains("no longer")
      || draft.localizedCaseInsensitiveContains("success looks like")
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
      let escaped = NSRegularExpression.escapedPattern(for: word)
      let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
      return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }

  private static func bounded(_ text: String) -> String {
    guard text.count > detailLimit else { return text }
    guard detailLimit > 3 else { return String(text.prefix(detailLimit)) }
    return String(text.prefix(detailLimit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct DraftIntakeGuide: Equatable, Sendable {
  static let maxEntries = 6
  static let draftTextLimit = 220
  static let identifierLimit = 1_200

  var entries: [Entry]

  var isEmpty: Bool {
    entries.isEmpty
  }

  var allowsNarration: Bool {
    !entries.isEmpty
  }

  var narrationIdentifier: String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "status:\(status)",
      "score:\(scoreLabel)",
      "entries:\(entries.map(\.narrationIdentifierFragment).joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }

  var status: Status {
    guard !entries.isEmpty else { return .empty }
    return readyCount == entries.count ? .ready : .needsDetail
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
      return "Every queued draft names the outcome, why it matters, and how done should look."
    case .needsDetail:
      let missing =
        missingSignalTitles.isEmpty
        ? "more detail"
        : missingSignalTitles.joined(separator: ", ")
      return
        "\(Self.countLabel(entries.count, singular: "queued draft", plural: "queued drafts")). \(scoreLabel). Missing across queue: \(missing)."
    }
  }

  var scoreLabel: String {
    guard !entries.isEmpty else { return "0 queued" }
    return "\(readyCount) of \(entries.count) ready"
  }

  var entryCountLabel: String {
    Self.countLabel(entries.count, singular: "queued draft", plural: "queued drafts")
  }

  var readyCount: Int {
    entries.filter { $0.readiness.status == .ready }.count
  }

  var missingSignalTitles: [String] {
    DraftReadinessGuide.Kind.allCases.compactMap { kind in
      let isMissing = entries.contains { entry in
        entry.readiness.cues.contains { $0.kind == kind && !$0.isSatisfied }
      }
      return isMissing ? kind.title : nil
    }
  }

  init(drafts: String) {
    entries = Self.extractDraftEntries(from: drafts)
      .prefix(Self.maxEntries)
      .enumerated()
      .map { offset, text in
        Entry(number: offset + 1, draft: text)
      }
  }

  var promptText: String {
    guard !entries.isEmpty else {
      return "_(no draft readiness signals)_"
    }

    return entries.map(\.promptText).joined(separator: "\n\n")
  }

  enum Status: Equatable, Sendable {
    case empty
    case needsDetail
    case ready
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
