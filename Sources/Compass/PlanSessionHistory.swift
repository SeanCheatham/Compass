import Foundation

struct PlanSessionHistoryItem: Identifiable, Equatable {
  struct FailedVerify: Equatable {
    var command: String
    var exitCodeText: String
    var tail: String
  }

  struct RuntimeRouteDescriptor: Equatable {
    static let badgeTextLimit = 120
    static let helpTextLimit = 260
    static let identifierLimit = 64
    static let titleLimit = 80

    var snapshotAvailabilityIdentifier: String
    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    var supportClassificationIdentifier: String
    var omittedSupportTokenCount: Int
    var fallbackStateIdentifier: String
    var badgeText: String
    var helpText: String

    private init(
      snapshotAvailabilityIdentifier: String,
      selectedPreferenceIdentifier: String,
      selectedPreferenceTitle: String,
      effectiveRouteIdentifier: String,
      effectiveRouteTitle: String,
      supportClassificationIdentifier: String,
      omittedSupportTokenCount: Int,
      fallbackStateIdentifier: String,
      badgeText: String,
      helpText: String
    ) {
      self.snapshotAvailabilityIdentifier = snapshotAvailabilityIdentifier
      self.selectedPreferenceIdentifier = selectedPreferenceIdentifier
      self.selectedPreferenceTitle = selectedPreferenceTitle
      self.effectiveRouteIdentifier = effectiveRouteIdentifier
      self.effectiveRouteTitle = effectiveRouteTitle
      self.supportClassificationIdentifier = supportClassificationIdentifier
      self.omittedSupportTokenCount = omittedSupportTokenCount
      self.fallbackStateIdentifier = fallbackStateIdentifier
      self.badgeText = badgeText
      self.helpText = helpText
    }

    static let unavailable = Self(
      snapshotAvailabilityIdentifier: "missing",
      selectedPreferenceIdentifier: "unknown",
      selectedPreferenceTitle: "Unknown",
      effectiveRouteIdentifier: "unknown",
      effectiveRouteTitle: "Unknown route",
      supportClassificationIdentifier: "not-inspected",
      omittedSupportTokenCount: 0,
      fallbackStateIdentifier: "unknown",
      badgeText: "",
      helpText: ""
    )

    init(snapshot: SessionExecutionEnvironmentSnapshot?) {
      guard let snapshot else {
        self = Self.unavailable
        return
      }

      let selectedPreferenceIdentifier = Self.preferenceIdentifier(
        snapshot.selectedPreferenceIdentifier
      )
      let effectiveRouteIdentifier = Self.routeIdentifier(
        snapshot.effectiveRouteIdentifier
      )
      let supportClassificationIdentifier = Self.supportClassificationIdentifier(
        snapshot.supportClassificationIdentifier
      )
      let fallbackStateIdentifier = Self.fallbackStateIdentifier(for: snapshot)
      let omittedSupportTokenCount = max(0, snapshot.omittedSupportTokenCount)
      let selectedPreferenceTitle = Self.preferenceTitle(
        identifier: selectedPreferenceIdentifier,
        fallback: snapshot.selectedPreferenceTitle
      )
      let effectiveRouteTitle = Self.routeTitle(
        identifier: effectiveRouteIdentifier,
        fallback: snapshot.effectiveRouteTitle
      )

      self = Self(
        snapshotAvailabilityIdentifier: "available",
        selectedPreferenceIdentifier: selectedPreferenceIdentifier,
        selectedPreferenceTitle: selectedPreferenceTitle,
        effectiveRouteIdentifier: effectiveRouteIdentifier,
        effectiveRouteTitle: effectiveRouteTitle,
        supportClassificationIdentifier: supportClassificationIdentifier,
        omittedSupportTokenCount: omittedSupportTokenCount,
        fallbackStateIdentifier: fallbackStateIdentifier,
        badgeText: Self.badgeText(
          selectedPreferenceTitle: selectedPreferenceTitle,
          effectiveRouteTitle: effectiveRouteTitle,
          supportClassificationIdentifier: supportClassificationIdentifier,
          omittedSupportTokenCount: omittedSupportTokenCount,
          fallbackStateIdentifier: fallbackStateIdentifier
        ),
        helpText: Self.helpText(
          selectedPreferenceTitle: selectedPreferenceTitle,
          effectiveRouteTitle: effectiveRouteTitle,
          supportClassificationIdentifier: supportClassificationIdentifier,
          omittedSupportTokenCount: omittedSupportTokenCount,
          fallbackStateIdentifier: fallbackStateIdentifier
        )
      )
    }

    var isSnapshotAvailable: Bool {
      snapshotAvailabilityIdentifier == "available"
    }

    var isSharedVMRoute: Bool {
      isSnapshotAvailable && effectiveRouteIdentifier == "shared-vm"
    }

    var isNativeRoute: Bool {
      isSnapshotAvailable && effectiveRouteIdentifier == "native-macos"
    }

    var systemImage: String {
      isSharedVMRoute ? "macwindow.on.rectangle" : "desktopcomputer"
    }

    private static func badgeText(
      selectedPreferenceTitle: String,
      effectiveRouteTitle: String,
      supportClassificationIdentifier: String,
      omittedSupportTokenCount: Int,
      fallbackStateIdentifier: String
    ) -> String {
      boundedText(
        [
          effectiveRouteTitle,
          selectedPreferenceTitle,
          supportClassificationIdentifier,
          "omitted \(omittedSupportTokenCount)",
          fallbackStateIdentifier,
        ].joined(separator: " · "),
        limit: badgeTextLimit
      )
    }

    private static func helpText(
      selectedPreferenceTitle: String,
      effectiveRouteTitle: String,
      supportClassificationIdentifier: String,
      omittedSupportTokenCount: Int,
      fallbackStateIdentifier: String
    ) -> String {
      boundedText(
        [
          "Selected preference: \(selectedPreferenceTitle)",
          "Effective route: \(effectiveRouteTitle)",
          "Support: \(supportClassificationIdentifier)",
          "Omitted token count: \(omittedSupportTokenCount)",
          "Fallback: \(fallbackStateIdentifier)",
        ].joined(separator: "; "),
        limit: helpTextLimit
      )
    }

    private static func fallbackStateIdentifier(
      for snapshot: SessionExecutionEnvironmentSnapshot
    ) -> String {
      let fallbackReason =
        snapshot.fallbackReason?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return fallbackReason.isEmpty ? "direct" : "fallback"
    }

    private static func preferenceTitle(identifier: String, fallback: String) -> String {
      switch identifier {
      case AgentExecutionEnvironmentPreference.sharedVM.rawValue:
        return AgentExecutionEnvironmentPreference.sharedVM.title
      default:
        return sanitizedTitle(fallback, fallback: "Unknown")
      }
    }

    private static func routeTitle(identifier: String, fallback: String) -> String {
      switch identifier {
      case "shared-vm":
        return "Shared VM"
      case "native-macos":
        return "Native macOS"
      default:
        return sanitizedTitle(fallback, fallback: "Unknown route")
      }
    }

    private static func preferenceIdentifier(_ text: String) -> String {
      let identifier = sanitizedIdentifier(text, fallback: "unknown")
      switch identifier {
      case AgentExecutionEnvironmentPreference.sharedVM.rawValue:
        return identifier
      case "native_macos", "devcontainer_preferred":
        // Legacy stored preferences — Compass no longer offers a
        // host preference; surface them as the canonical Shared VM
        // identifier so recap history stays in the bounded set.
        return AgentExecutionEnvironmentPreference.sharedVM.rawValue
      default:
        return "unknown"
      }
    }

    private static func routeIdentifier(_ text: String) -> String {
      let identifier = sanitizedIdentifier(text, fallback: "unknown")
      switch identifier {
      case "shared-vm", "native-macos":
        return identifier
      default:
        return "unknown"
      }
    }

    private static func supportClassificationIdentifier(_ text: String) -> String {
      let identifier = sanitizedIdentifier(text, fallback: "not-inspected")
      switch identifier {
      case "unavailable",
        "not-provisioned",
        "downloading-ipsw",
        "installing",
        "first-boot-pending",
        "guest-prepping",
        "ready",
        "error",
        "not-inspected":
        return identifier
      default:
        return "not-inspected"
      }
    }

    private static func sanitizedIdentifier(_ text: String, fallback: String) -> String {
      let normalized = boundedText(text, limit: identifierLimit)
        .lowercased()
      let filtered = String(
        normalized.unicodeScalars.map { scalar in
          if isASCIILetter(scalar)
            || isASCIIDigit(scalar)
            || scalar == "-"
            || scalar == "_"
            || scalar == "."
            || scalar == ":"
          {
            return Character(scalar)
          }
          return "-"
        }
      )
      .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-_:."))
      return filtered.isEmpty ? fallback : filtered
    }

    private static func sanitizedTitle(_ text: String, fallback: String) -> String {
      let bounded = boundedText(text, limit: titleLimit)
      guard !bounded.isEmpty else {
        return fallback
      }

      let scalarsAreSafe = bounded.unicodeScalars.allSatisfy { scalar in
        isASCIILetter(scalar)
          || isASCIIDigit(scalar)
          || scalar == " "
          || scalar == "-"
          || scalar == "_"
          || scalar == "."
          || scalar == ":"
          || scalar == "@"
          || scalar == "+"
      }
      return scalarsAreSafe ? bounded : fallback
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
      guard limit > 0 else { return "" }
      let normalized =
        text
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard normalized.count > limit else { return normalized }
      return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
      (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
      (48...57).contains(Int(scalar.value))
    }
  }

  var id: Int { sessionNumber }

  /// Returns a placeholder item suitable for SwiftUI preview and test contexts
  /// where only the item identity matters (popover title, etc.) and no real session
  /// data is accessed.
  static let placeholder = PlanSessionHistoryItem(
    sessionNumber: 0,
    status: .succeeded,
    statusText: "Success",
    startedAt: Date(),
    planExcerpt: nil,
    verifyCommand: nil,
    feedback: nil,
    notes: [],
    commits: [],
    failedVerify: nil,
    runtimeRouteSummary: nil
  )

  var sessionNumber: Int
  var status: SessionStatus
  var statusText: String
  var startedAt: Date
  var planExcerpt: String?
  var verifyCommand: String?
  var feedback: String?
  var notes: [String]
  var commits: [SessionCommit]
  var failedVerify: FailedVerify?
  var runtimeRouteSummary: String?
  var runtimeRouteDescriptor: RuntimeRouteDescriptor

  init(
    sessionNumber: Int,
    status: SessionStatus,
    statusText: String,
    startedAt: Date,
    planExcerpt: String?,
    verifyCommand: String?,
    feedback: String?,
    notes: [String],
    commits: [SessionCommit],
    failedVerify: FailedVerify?,
    runtimeRouteSummary: String?,
    runtimeRouteDescriptor: RuntimeRouteDescriptor = .unavailable
  ) {
    self.sessionNumber = sessionNumber
    self.status = status
    self.statusText = statusText
    self.startedAt = startedAt
    self.planExcerpt = planExcerpt
    self.verifyCommand = verifyCommand
    self.feedback = feedback
    self.notes = notes
    self.commits = commits
    self.failedVerify = failedVerify
    self.runtimeRouteSummary = runtimeRouteSummary
    self.runtimeRouteDescriptor = runtimeRouteDescriptor
  }
}

enum PlanSessionHistoryFilter: String, CaseIterable, Identifiable, Equatable, Hashable {
  case all
  case attention
  case activePaused
  case failedRejected
  case completedFinished
  case sharedVM = "shared_vm"
  case nativeRuntime

  struct Option: Identifiable, Equatable {
    var filter: PlanSessionHistoryFilter
    var count: Int

    var id: PlanSessionHistoryFilter.ID {
      filter.id
    }
  }

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .all:
      return "All"
    case .attention:
      return "Attention"
    case .activePaused:
      return "Active/Paused"
    case .failedRejected:
      return "Failed/Rejected"
    case .completedFinished:
      return "Completed"
    case .sharedVM:
      return "Shared VM"
    case .nativeRuntime:
      return "Native/Fallback"
    }
  }

  var emptyStateName: String {
    switch self {
    case .all:
      return "runs"
    case .attention:
      return "attention runs"
    case .activePaused:
      return "active or paused runs"
    case .failedRejected:
      return "failed or rejected runs"
    case .completedFinished:
      return "completed runs"
    case .sharedVM:
      return "Shared VM runs"
    case .nativeRuntime:
      return "native or fallback runs"
    }
  }

  var systemImage: String {
    switch self {
    case .all:
      return "line.3.horizontal.decrease.circle"
    case .attention:
      return "exclamationmark.triangle"
    case .activePaused:
      return "playpause.circle"
    case .failedRejected:
      return "xmark.octagon"
    case .completedFinished:
      return "checkmark.circle"
    case .sharedVM:
      return "macwindow.on.rectangle"
    case .nativeRuntime:
      return "desktopcomputer"
    }
  }

  static func options(
    for items: [PlanSessionHistoryItem],
    runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
  ) -> [Option] {
    allCases.map { filter in
      Option(
        filter: filter,
        count: items.filter { item in
          filter.matches(item, runCue: runCues[item.sessionNumber])
        }.count
      )
    }
  }

  func matches(
    _ item: PlanSessionHistoryItem,
    runCue: PlanReliabilityFeedback.RunCue? = nil
  ) -> Bool {
    switch self {
    case .all:
      return true
    case .attention:
      return runCue != nil
    case .activePaused:
      return item.status == .planning
        || item.status == .developing
        || item.status == .awaitingApproval
        || runCue?.severity == .paused
    case .failedRejected:
      return item.status == .failed
        || item.status == .rejectedByPlan
        || runCue?.kind == .rejectedPlan
        || runCue?.kind == .developFailed
        || runCue?.kind == .failedVerify
        || runCue?.kind == .dirtyWorktree
        || runCue?.kind == .promotionFailed
    case .completedFinished:
      return item.status == .succeeded
        || item.status == .cancelled
        || item.status == .skipped
    case .sharedVM:
      return item.runtimeRouteDescriptor.isSharedVMRoute
    case .nativeRuntime:
      return item.runtimeRouteDescriptor.isNativeRoute
    }
  }
}

struct PlanSessionHistoryDisplay: Equatable {
  enum Mode: Equatable {
    case recent
    case all
  }

  static let defaultRecentLimit = 8

  var mode: Mode
  var filter: PlanSessionHistoryFilter
  var recentLimit: Int
  var filterOptions: [PlanSessionHistoryFilter.Option]
  var visibleItems: [PlanSessionHistoryItem]
  var unfilteredTotalCount: Int
  var totalCount: Int
  var hiddenCount: Int
  var hiddenStatusSummary: String?
  var shouldOfferModeToggle: Bool
  var countSummary: String

  var visibleCount: Int {
    visibleItems.count
  }

  init(
    items: [PlanSessionHistoryItem],
    mode: Mode = .recent,
    recentLimit: Int = Self.defaultRecentLimit,
    filter: PlanSessionHistoryFilter = .all,
    runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
  ) {
    let boundedRecentLimit = max(0, recentLimit)
    let filterOptions = PlanSessionHistoryFilter.options(for: items, runCues: runCues)
    let filteredItems = items.filter { item in
      filter.matches(item, runCue: runCues[item.sessionNumber])
    }

    let visibleItems: [PlanSessionHistoryItem]
    switch mode {
    case .recent:
      visibleItems = Array(filteredItems.prefix(boundedRecentLimit))
    case .all:
      visibleItems = filteredItems
    }

    let hiddenItems = Array(filteredItems.dropFirst(visibleItems.count))
    let shouldOfferModeToggle = filteredItems.count > boundedRecentLimit

    self.mode = mode
    self.filter = filter
    self.recentLimit = boundedRecentLimit
    self.filterOptions = filterOptions
    self.visibleItems = visibleItems
    unfilteredTotalCount = items.count
    totalCount = filteredItems.count
    hiddenCount = hiddenItems.count
    hiddenStatusSummary = Self.hiddenStatusSummary(for: hiddenItems)
    self.shouldOfferModeToggle = shouldOfferModeToggle
    countSummary = Self.countSummary(
      totalCount: filteredItems.count,
      visibleCount: visibleItems.count,
      hiddenCount: hiddenItems.count,
      mode: mode,
      shouldOfferModeToggle: shouldOfferModeToggle,
      filter: filter
    )
  }

  private static func countSummary(
    totalCount: Int,
    visibleCount: Int,
    hiddenCount: Int,
    mode: Mode,
    shouldOfferModeToggle: Bool,
    filter: PlanSessionHistoryFilter
  ) -> String {
    guard totalCount > 0 else {
      return filter == .all ? "0 runs" : "0 matching runs"
    }

    if hiddenCount > 0 {
      let suffix = filter == .all ? "" : " matching"
      return "Showing latest \(visibleCount) of \(totalCount)\(suffix)"
    }

    if mode == .all, shouldOfferModeToggle {
      let suffix = filter == .all ? "" : " matching"
      return "Showing all \(totalCount)\(suffix)"
    }

    if filter != .all {
      return "\(totalCount) matching \(runWord(for: totalCount))"
    }

    return "\(totalCount) \(runWord(for: totalCount))"
  }

  private static func hiddenStatusSummary(for items: [PlanSessionHistoryItem]) -> String? {
    guard !items.isEmpty else {
      return nil
    }

    var orderedStatuses: [String] = []
    var counts: [String: Int] = [:]
    for item in items {
      let statusText = item.statusText.lowercased()
      if counts[statusText] == nil {
        orderedStatuses.append(statusText)
      }
      counts[statusText, default: 0] += 1
    }

    return orderedStatuses.compactMap { statusText in
      guard let count = counts[statusText] else {
        return nil
      }
      return "\(count) \(statusText)"
    }
    .joined(separator: ", ")
  }

  static func runWord(for count: Int) -> String {
    count == 1 ? "run" : "runs"
  }
}

enum PlanSessionHistory {
  static let defaultPlanExcerptLimit = 280

  static func displayItems(
    for sessions: [SessionRecord],
    planExcerptLimit: Int = defaultPlanExcerptLimit
  ) -> [PlanSessionHistoryItem] {
    return
      sessions
      .sorted { lhs, rhs in
        if lhs.startedAt == rhs.startedAt {
          return lhs.session > rhs.session
        }
        return lhs.startedAt > rhs.startedAt
      }
      .map { session in
        let latestRuntimeSnapshot = session.latestExecutionEnvironmentSnapshot
        return PlanSessionHistoryItem(
          sessionNumber: session.session,
          status: session.status,
          statusText: statusText(for: session.status),
          startedAt: Date(timeIntervalSince1970: session.startedAt / 1000),
          planExcerpt: excerpt(session.plan, limit: planExcerptLimit),
          verifyCommand: nonEmpty(session.verify),
          feedback: nonEmpty(session.feedback),
          notes: session.notes,
          commits: session.commits,
          failedVerify: failedVerify(from: session),
          runtimeRouteSummary: latestRuntimeSnapshot?.routeSummary,
          runtimeRouteDescriptor: PlanSessionHistoryItem.RuntimeRouteDescriptor(
            snapshot: latestRuntimeSnapshot
          )
        )
      }
  }

  private static func statusText(for status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "Planning"
    case .awaitingApproval:
      return "Awaiting approval"
    case .developing:
      return "Developing"
    case .succeeded:
      return "Succeeded"
    case .failed:
      return "Failed"
    case .cancelled:
      return "Cancelled"
    case .rejectedByPlan:
      return "Rejected by plan"
    case .skipped:
      return "Skipped"
    }
  }

  private static func excerpt(_ value: String?, limit: Int) -> String? {
    guard limit > 0,
      let normalized = value?
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " "),
      !normalized.isEmpty
    else {
      return nil
    }
    guard normalized.count > limit else {
      return normalized
    }
    guard limit > 3 else {
      return String(normalized.prefix(limit))
    }
    return String(normalized.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func failedVerify(from session: SessionRecord) -> PlanSessionHistoryItem
    .FailedVerify?
  {
    guard let output = session.verifyOutput,
      let tail = nonEmpty(output.tail)
    else {
      return nil
    }
    return PlanSessionHistoryItem.FailedVerify(
      command: nonEmpty(output.command) ?? nonEmpty(session.verify) ?? "verify",
      exitCodeText: output.exitCode.map { "exit \($0)" } ?? "exit unknown",
      tail: tail
    )
  }
}
