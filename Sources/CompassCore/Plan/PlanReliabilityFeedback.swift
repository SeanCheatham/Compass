import Foundation

public struct PlanReliabilityFeedback: Equatable {
  public static let defaultNoticeLimit = 3
  public static let defaultDetailLimit = 220
  public static let defaultTailLimit = 260

  public var notices: [Notice]
  public var recentRunCues: [Int: RunCue]

  public var isEmpty: Bool {
    notices.isEmpty
  }

  public init(
    state: PlanState,
    sessions: [SessionRecord],
    historyItems: [PlanSessionHistoryItem]? = nil,
    noticeLimit: Int = Self.defaultNoticeLimit,
    detailLimit: Int = Self.defaultDetailLimit,
    tailLimit: Int = Self.defaultTailLimit
  ) {
    let sortedHistoryItems = historyItems ?? PlanSessionHistory.displayItems(for: sessions)
    var sessionByNumber: [Int: SessionRecord] = [:]
    for session in sessions {
      sessionByNumber[session.session] = session
    }

    // A later successful session retires cues from earlier ones — otherwise a single
    // failed session lingers forever, since successful sessions emit no notices to
    // displace it past `noticeLimit`.
    let latestSuccess =
      sessions
      .filter { $0.status == .succeeded }
      .max { Self.isOlder($0, than: $1) }

    let allNotices = sortedHistoryItems.flatMap { item in
      guard let session = sessionByNumber[item.sessionNumber] else {
        return [Notice]()
      }
      if let cutoff = latestSuccess, Self.isOlder(session, than: cutoff) {
        return [Notice]()
      }

      return Self.notices(
        for: session,
        item: item,
        state: state,
        detailLimit: detailLimit,
        tailLimit: tailLimit
      )
    }

    notices = Array(allNotices.prefix(max(0, noticeLimit)))

    var cueNotices: [Int: Notice] = [:]
    for notice in allNotices {
      if let existing = cueNotices[notice.sessionNumber],
        Self.priority(for: existing.kind) <= Self.priority(for: notice.kind)
      {
        continue
      }
      cueNotices[notice.sessionNumber] = notice
    }
    recentRunCues = cueNotices.mapValues { RunCue(notice: $0) }
  }

  public struct Notice: Identifiable, Equatable {
    public var id: String
    public var kind: Kind
    public var severity: Severity
    public var sessionNumber: Int
    public var title: String
    public var detail: String
    public var actionLabel: String
    public var metadata: String?
    public var systemImage: String
  }

  public struct RunCue: Equatable {
    public var kind: Kind
    public var severity: Severity
    public var label: String
    public var detail: String
    public var systemImage: String

    public init(notice: Notice) {
      kind = notice.kind
      severity = notice.severity
      label = notice.actionLabel
      detail = notice.detail
      systemImage = notice.systemImage
    }
  }

  public enum Kind: String, Equatable {
    case rejectedPlan
    case developBlocked
    case developFailed
    case failedVerify
    case dirtyWorktree
    case promotionFailed
    case resumeDevelop
  }

  public enum Severity: String, Equatable {
    case warning
    case failure
    case paused
  }

  private static func notices(
    for session: SessionRecord,
    item: PlanSessionHistoryItem,
    state: PlanState,
    detailLimit: Int,
    tailLimit: Int
  ) -> [Notice] {
    if let rejectionText = planRejectionText(in: session, detailLimit: detailLimit) {
      return [
        Notice(
          id: "\(Kind.rejectedPlan.rawValue)-\(session.session)",
          kind: .rejectedPlan,
          severity: .failure,
          sessionNumber: session.session,
          title: "Plan rejected",
          detail: rejectionText,
          actionLabel: "Retry Plan",
          metadata: "#\(session.session)",
          systemImage: "exclamationmark.triangle.fill"
        )
      ]
    }

    if session.status == .awaitingApproval, state.immediate != nil {
      return [
        Notice(
          id: "\(Kind.resumeDevelop.rawValue)-\(session.session)",
          kind: .resumeDevelop,
          severity: .paused,
          sessionNumber: session.session,
          title: "Develop ready",
          detail: item.planExcerpt
            ?? boundedPrefix(state.immediate?.plan, limit: detailLimit)
            ?? "Plan is ready; Develop has not started.",
          actionLabel: "Resume Develop",
          metadata: "#\(session.session)",
          systemImage: "play.circle.fill"
        )
      ]
    }

    var results: [Notice] = []

    if let blockerText = developBlockedText(in: session, detailLimit: detailLimit) {
      results.append(
        Notice(
          id: "\(Kind.developBlocked.rawValue)-\(session.session)",
          kind: .developBlocked,
          severity: .warning,
          sessionNumber: session.session,
          title: "Develop blocked",
          detail: blockerText,
          actionLabel: retryDevelopLabel(for: state),
          metadata: "#\(session.session)",
          systemImage: "hand.raised.fill"
        )
      )
    } else if let failureText = developFailureText(in: session, detailLimit: detailLimit) {
      results.append(
        Notice(
          id: "\(Kind.developFailed.rawValue)-\(session.session)",
          kind: .developFailed,
          severity: .failure,
          sessionNumber: session.session,
          title: "Develop failed",
          detail: failureText,
          actionLabel: retryDevelopLabel(for: state),
          metadata: "#\(session.session)",
          systemImage: "xmark.octagon.fill"
        )
      )
    }

    if let failedVerify = item.failedVerify {
      results.append(
        Notice(
          id: "\(Kind.failedVerify.rawValue)-\(session.session)",
          kind: .failedVerify,
          severity: .failure,
          sessionNumber: session.session,
          title: "Verify failed",
          detail: boundedSuffix(failedVerify.tail, limit: tailLimit)
            ?? "Verify failed without captured output.",
          actionLabel: retryDevelopLabel(for: state),
          metadata: verifyMetadata(failedVerify, limit: detailLimit),
          systemImage: "checkmark.seal.fill"
        )
      )
    }

    if let dirtyWorktree = dirtyWorktreeCue(in: session, detailLimit: detailLimit) {
      results.append(
        Notice(
          id: "\(Kind.dirtyWorktree.rawValue)-\(session.session)",
          kind: .dirtyWorktree,
          severity: dirtyWorktree.severity,
          sessionNumber: session.session,
          title: "Worktree dirty",
          detail: dirtyWorktree.detail,
          actionLabel: "Clean Worktree",
          metadata: dirtyWorktree.metadata,
          systemImage: "pencil.and.outline"
        )
      )
    }

    if let promotionFailure = promotionFailureCue(in: session, detailLimit: detailLimit) {
      results.append(
        Notice(
          id: "\(Kind.promotionFailed.rawValue)-\(session.session)",
          kind: .promotionFailed,
          severity: .failure,
          sessionNumber: session.session,
          title: "Promotion failed",
          detail: promotionFailure.detail,
          actionLabel: "Resolve Promotion",
          metadata: promotionFailure.metadata,
          systemImage: "arrow.triangle.branch"
        )
      )
    }

    return results
  }

  private static func isOlder(_ lhs: SessionRecord, than rhs: SessionRecord) -> Bool {
    if lhs.startedAt == rhs.startedAt {
      return lhs.session < rhs.session
    }
    return lhs.startedAt < rhs.startedAt
  }

  public static func priority(for kind: Kind) -> Int {
    switch kind {
    case .rejectedPlan:
      return 0
    case .failedVerify:
      return 1
    case .dirtyWorktree:
      return 2
    case .promotionFailed:
      return 3
    case .developBlocked:
      return 4
    case .developFailed:
      return 5
    case .resumeDevelop:
      return 6
    }
  }

  private static func planRejectionText(in session: SessionRecord, detailLimit: Int) -> String? {
    if session.status == .rejectedByPlan {
      return boundedPrefix(firstNonEmpty(rejectionCandidateTexts(in: session)), limit: detailLimit)
        ?? "Plan was rejected before state.json changed."
    }

    guard
      let text = firstMatchingText(
        in: rejectionCandidateTexts(in: session),
        containsAny: [
          "refusing to overwrite state.json",
          "placeholder verify command",
          "failure-masking verify command",
          "plan tried to",
          "plan transition",
          "not executable enough for develop",
          "plan should replace the verify command",
          "planned command is wrong or out of scope",
          "returned no immediate work while",
          "verify was skipped because develop reported",
          "must collect test coverage",
          "rejected plan",
        ])
    else {
      return nil
    }

    return boundedPrefix(text, limit: detailLimit)
  }

  private static func developBlockedText(in session: SessionRecord, detailLimit: Int) -> String? {
    guard session.status == .failed else { return nil }
    guard
      firstMatchingText(
        in: session.notes + optionalTexts(session.feedback),
        containsAny: [
          "develop reported it was blocked",
          "blocked but did not request verify bypass",
          "develop blocked",
          "blocked",
        ]) != nil
    else {
      return nil
    }

    return boundedPrefix(session.feedback, limit: detailLimit)
      ?? boundedPrefix(
        firstMatchingText(in: session.notes, containsAny: ["blocked"]), limit: detailLimit)
      ?? "Develop reported it was blocked."
  }

  private static func developFailureText(in session: SessionRecord, detailLimit: Int) -> String? {
    guard session.status == .failed else { return nil }
    let matchingNote = firstMatchingText(
      in: session.notes,
      containsAny: [
        "develop reported failure:",
        "develop failed",
        "phase submit missing",
        "phase submit envelope",
        "ended without submit_result",
        "model stopped without calling submit_result",
        "agent exceeded max iterations",
        "agent exceeded wall-clock timeout",
        "had undecodable args",
        "tool call decode",
        "local model generation failed",
      ])
    if let matchingNote {
      return boundedPrefix(session.feedback, limit: detailLimit)
        ?? boundedPrefix(
          strippedDevelopFailurePrefix(from: matchingNote),
          limit: detailLimit
        ) ?? "Develop reported failure."
    }

    guard session.verifyOutput == nil,
      !hasPostCheckRecoveryCue(in: session)
    else { return nil }
    return boundedPrefix(session.feedback, limit: detailLimit)
  }

  private struct ParsedPostCheckCue {
    public var detail: String
    public var metadata: String?
    public var severity: Severity
  }

  private static func dirtyWorktreeCue(in session: SessionRecord, detailLimit: Int)
    -> ParsedPostCheckCue?
  {
    guard
      let text = firstMatchingText(
        in: session.notes + optionalTexts(session.feedback),
        containsAny: [
          "uncommitted or untracked changes remain after develop ran",
          "`git status --porcelain` failed unexpectedly",
        ])
    else {
      return nil
    }

    let statusCheckFailed = text.lowercased().contains(
      "`git status --porcelain` failed unexpectedly")
    return ParsedPostCheckCue(
      detail: boundedPrefix(text, limit: detailLimit)
        ?? (statusCheckFailed
          ? "Working-tree status check failed." : "Develop left uncommitted or untracked changes."),
      metadata: dirtyWorktreeMetadata(
        from: text, sessionNumber: session.session, limit: detailLimit),
      severity: statusCheckFailed ? .failure : .warning
    )
  }

  private static func promotionFailureCue(in session: SessionRecord, detailLimit: Int)
    -> ParsedPostCheckCue?
  {
    guard
      let text = firstMatchingText(
        in: session.notes + optionalTexts(session.feedback),
        containsAny: [
          "develop sandbox produced no commit to promote",
          "failed to promote develop sandbox branch",
        ])
    else {
      return nil
    }

    return ParsedPostCheckCue(
      detail: boundedPrefix(text, limit: detailLimit) ?? "Develop sandbox promotion failed.",
      metadata: promotionFailureMetadata(
        from: text, sessionNumber: session.session, limit: detailLimit),
      severity: .failure
    )
  }

  private static func hasPostCheckRecoveryCue(in session: SessionRecord) -> Bool {
    dirtyWorktreeCue(in: session, detailLimit: defaultDetailLimit) != nil
      || promotionFailureCue(in: session, detailLimit: defaultDetailLimit) != nil
  }

  private static func retryDevelopLabel(for state: PlanState) -> String {
    state.immediate == nil ? "Plan Next Step" : "Retry Develop"
  }

  private static func strippedDevelopFailurePrefix(from text: String) -> String {
    let prefix = "develop reported failure:"
    guard text.lowercased().hasPrefix(prefix) else {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
    return String(text[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func verifyMetadata(
    _ failedVerify: PlanSessionHistoryItem.FailedVerify, limit: Int
  ) -> String {
    [
      boundedPrefix(failedVerify.command, limit: min(limit, 96)),
      failedVerify.exitCodeText,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }

  private static func dirtyWorktreeMetadata(from text: String, sessionNumber: Int, limit: Int)
    -> String?
  {
    let descriptor: String
    if let count = porcelainStatusLineCount(in: text) {
      descriptor = "\(count) pending \(count == 1 ? "change" : "changes")"
    } else {
      descriptor = "git status"
    }

    return boundedPrefix("#\(sessionNumber) · \(descriptor)", limit: min(limit, 96))
  }

  private static func promotionFailureMetadata(from text: String, sessionNumber: Int, limit: Int)
    -> String?
  {
    let descriptor = promotionBranchName(in: text) ?? "promotion"
    return boundedPrefix("#\(sessionNumber) · \(descriptor)", limit: min(limit, 96))
  }

  private static func porcelainStatusLineCount(in text: String) -> Int? {
    guard text.lowercased().contains("`git status --porcelain` output:"),
      let statusBlock = fencedCodeBlocks(in: text).last
    else {
      return nil
    }

    let count =
      statusBlock
      .split(whereSeparator: \.isNewline)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .count
    return count > 0 ? count : nil
  }

  private static func promotionBranchName(in text: String) -> String? {
    let prefix = "Failed to promote Develop sandbox branch "
    guard let range = text.range(of: prefix, options: .caseInsensitive) else {
      return nil
    }

    let suffix = text[range.upperBound...]
    guard
      let branch = suffix.split(separator: ":", maxSplits: 1).first?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !branch.isEmpty
    else {
      return nil
    }
    return branch
  }

  private static func fencedCodeBlocks(in text: String) -> [String] {
    let parts = text.components(separatedBy: "```")
    guard parts.count >= 3 else { return [] }

    return stride(from: 1, to: parts.count, by: 2).map { parts[$0] }
  }

  private static func rejectionCandidateTexts(in session: SessionRecord) -> [String] {
    session.notes + optionalTexts(session.feedback)
  }

  private static func optionalTexts(_ value: String?) -> [String] {
    guard let value else { return [] }
    return [value]
  }

  private static func firstNonEmpty(_ values: [String]) -> String? {
    values.first { normalizedText($0) != nil }
  }

  private static func firstMatchingText(in values: [String], containsAny needles: [String])
    -> String?
  {
    values.first { value in
      let normalized = value.lowercased()
      return needles.contains { normalized.contains($0) }
    }
  }

  private static func boundedPrefix(_ value: String?, limit: Int) -> String? {
    guard let normalized = normalizedText(value), limit > 0 else {
      return nil
    }

    guard normalized.count > limit else {
      return normalized
    }

    guard limit > 3 else {
      return String(normalized.prefix(limit))
    }

    return normalized.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private static func boundedSuffix(_ value: String?, limit: Int) -> String? {
    guard let normalized = normalizedText(value), limit > 0 else {
      return nil
    }

    guard normalized.count > limit else {
      return normalized
    }

    guard limit > 3 else {
      return String(normalized.suffix(limit))
    }

    return "..."
      + normalized.suffix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizedText(_ value: String?) -> String? {
    let normalized =
      value?
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    return normalized.isEmpty ? nil : normalized
  }
}

public struct ProjectReliabilityStatus: Equatable {
  public static let defaultDetailLimit = 180

  public var primaryCue: String
  public var severity: PlanReliabilityFeedback.Severity
  public var countLabel: String
  public var actionLabel: String
  public var metadata: String?
  public var detail: String
  public var systemImage: String
  public var noticeCount: Int
  public var primaryKind: PlanReliabilityFeedback.Kind?

  public var isEmpty: Bool {
    noticeCount == 0
  }

  public init(
    feedback: PlanReliabilityFeedback,
    detailLimit: Int = Self.defaultDetailLimit
  ) {
    guard let primaryNotice = Self.primaryNotice(in: feedback.notices) else {
      primaryCue = ""
      severity = .warning
      countLabel = Self.countLabel(for: 0)
      actionLabel = ""
      metadata = nil
      detail = ""
      systemImage = "checkmark.circle"
      noticeCount = 0
      primaryKind = nil
      return
    }

    primaryCue = primaryNotice.title
    severity = primaryNotice.severity
    countLabel = Self.countLabel(for: feedback.notices.count)
    actionLabel = primaryNotice.actionLabel
    metadata = primaryNotice.metadata
    detail = Self.boundedDetail(primaryNotice.detail, limit: detailLimit)
    systemImage = primaryNotice.systemImage
    noticeCount = feedback.notices.count
    primaryKind = primaryNotice.kind
  }

  private static func primaryNotice(in notices: [PlanReliabilityFeedback.Notice])
    -> PlanReliabilityFeedback.Notice?
  {
    notices.enumerated().min { lhs, rhs in
      let leftPriority = PlanReliabilityFeedback.priority(for: lhs.element.kind)
      let rightPriority = PlanReliabilityFeedback.priority(for: rhs.element.kind)
      if leftPriority != rightPriority {
        return leftPriority < rightPriority
      }
      return lhs.offset < rhs.offset
    }?.element
  }

  private static func countLabel(for count: Int) -> String {
    "\(count) \(count == 1 ? "cue" : "cues")"
  }

  private static func boundedDetail(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }

    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

public struct ProjectSidebarStatus: Equatable {
  public static let defaultSubtitleLimit = 86

  public var title: String
  public var subtitle: String
  public var badgeLabel: String
  public var countLabel: String
  public var actionLabel: String
  public var metadata: String?
  public var systemImage: String
  public var severity: PlanReliabilityFeedback.Severity
  public var cueCount: Int
  public var phaseLabel: String
  public var showsProgress: Bool
  public var helpText: String
  public var accessibilityLabel: String
  public var accessibilityHint: String

  public var hasReliabilityCue: Bool {
    cueCount > 0
  }

  public init(
    reliabilityStatus: ProjectReliabilityStatus,
    immediateTitle: String,
    phase: LoopPhase,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    pauseMode: PauseMode = .immediate,
    subtitleLimit: Int = Self.defaultSubtitleLimit
  ) {
    phaseLabel = Self.phaseLabel(
      phase: phase,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      pauseMode: pauseMode
    )
    showsProgress = isRunning || isAutoPlaying

    guard !reliabilityStatus.isEmpty else {
      title = ""
      subtitle = Self.boundedText(immediateTitle, limit: subtitleLimit)
      badgeLabel = ""
      countLabel = reliabilityStatus.countLabel
      actionLabel = ""
      metadata = nil
      systemImage = reliabilityStatus.systemImage
      severity = reliabilityStatus.severity
      cueCount = 0
      helpText = Self.joinedText([phaseLabel, subtitle], separator: " · ")
      accessibilityLabel = Self.joinedText([phaseLabel, subtitle], separator: ", ")
      accessibilityHint = ""
      return
    }

    title = reliabilityStatus.primaryCue
    subtitle = Self.boundedText(reliabilityStatus.detail, limit: subtitleLimit)
    badgeLabel = reliabilityStatus.primaryCue
    countLabel = reliabilityStatus.countLabel
    actionLabel = reliabilityStatus.actionLabel
    metadata = reliabilityStatus.metadata
    systemImage = reliabilityStatus.systemImage
    severity = reliabilityStatus.severity
    cueCount = reliabilityStatus.noticeCount

    helpText = Self.joinedText(
      [
        phaseLabel,
        reliabilityStatus.primaryCue,
        reliabilityStatus.actionLabel,
        reliabilityStatus.metadata,
        reliabilityStatus.countLabel,
        reliabilityStatus.detail,
      ],
      separator: " · "
    )
    accessibilityLabel = Self.joinedText(
      [
        phaseLabel,
        reliabilityStatus.primaryCue,
        reliabilityStatus.actionLabel,
        reliabilityStatus.metadata,
        reliabilityStatus.countLabel,
      ],
      separator: ", "
    )
    accessibilityHint = subtitle
  }

  private static func phaseLabel(
    phase: LoopPhase,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    pauseMode: PauseMode
  ) -> String {
    if isPaused && isRunning {
      switch pauseMode {
      case .immediate:
        return "Pausing"
      case .afterIteration:
        return "Pausing after iteration"
      }
    }

    if isAutoPlaying {
      return "Auto - \(phase.rawValue)"
    }

    if isPaused {
      return LoopPhase.paused.rawValue
    }

    return phase.rawValue
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    let normalized =
      value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalized.isEmpty, limit > 0 else { return "" }
    guard normalized.count > limit else { return normalized }
    guard limit > 3 else { return String(normalized.prefix(limit)) }

    return normalized.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private static func joinedText(_ values: [String?], separator: String) -> String {
    values
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: separator)
  }
}
