import Foundation

struct PlanSessionHistoryItem: Identifiable, Equatable {
  struct FailedVerify: Equatable {
    var command: String
    var exitCodeText: String
    var tail: String
  }

  struct AuditArtifact: Identifiable, Equatable, Sendable {
    static let labelLimit = 120
    static let detailLimit = 260
    static let pathLimit = 180

    var id: String { path }

    var path: String
    var kind: String
    var byteCount: UInt64
    var note: String?
    var label: String
    var detail: String
    var systemImageName: String

    init(_ artifact: SessionAuditArtifact) {
      path = Self.bounded(artifact.path, limit: Self.pathLimit)
      kind = Self.bounded(artifact.kind, limit: 80)
      byteCount = artifact.byteCount
      note = artifact.note.map { Self.bounded($0, limit: 140) }

      let kindTitle = Self.kindTitle(kind)
      label = Self.bounded("\(kindTitle) - \(Self.byteCountLabel(byteCount))", limit: Self.labelLimit)
      detail = Self.bounded(
        [note, path.isEmpty ? nil : "Saved at \(path)."]
          .compactMap { $0 }
          .joined(separator: " "),
        limit: Self.detailLimit
      )
      systemImageName = Self.systemImageName(for: kind)
    }

    private static func kindTitle(_ kind: String) -> String {
      switch kind {
      case "verify_output":
        return "Verify output"
      case "develop_output":
        return "Develop output"
      case "plan_output":
        return "Plan output"
      default:
        let title =
          kind
          .replacingOccurrences(of: "_", with: " ")
          .split(whereSeparator: \.isWhitespace)
          .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
          .joined(separator: " ")
        return title.isEmpty ? "Audit artifact" : title
      }
    }

    private static func systemImageName(for kind: String) -> String {
      switch kind {
      case "verify_output":
        return "checkmark.seal"
      case "develop_output":
        return "hammer"
      case "plan_output":
        return "map"
      default:
        return "doc.text.magnifyingglass"
      }
    }

    private static func byteCountLabel(_ bytes: UInt64) -> String {
      if bytes >= 1_048_576 {
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
      }
      if bytes >= 1_024 {
        let kb = Double(bytes) / 1_024
        return String(format: "%.1f KB", kb)
      }
      return "\(bytes) B"
    }

    private static func bounded(_ text: String, limit: Int) -> String {
      let normalized =
        text
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard limit > 0 else { return "" }
      guard normalized.count > limit else { return normalized }
      guard limit > 3 else { return String(normalized.prefix(limit)) }
      return String(normalized.prefix(limit - 3))
        .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
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
      let fallbackDetail = Self.fallbackDetail(for: snapshot)

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
          fallbackStateIdentifier: fallbackStateIdentifier,
          fallbackDetail: fallbackDetail
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
      let routeSummary =
        selectedPreferenceTitle == effectiveRouteTitle
        ? effectiveRouteTitle
        : "\(effectiveRouteTitle) · selected \(selectedPreferenceTitle)"
      var pieces = [
        routeSummary,
        readinessBadgeText(supportClassificationIdentifier),
      ]
      if fallbackStateIdentifier == "fallback" {
        pieces.append("Fallback active")
      }
      if omittedSupportTokenCount > 0 {
        pieces.append("\(omittedSupportTokenCount) detail\(omittedSupportTokenCount == 1 ? "" : "s") hidden")
      }
      return boundedText(pieces.joined(separator: " · "), limit: badgeTextLimit)
    }

    private static func helpText(
      selectedPreferenceTitle: String,
      effectiveRouteTitle: String,
      supportClassificationIdentifier: String,
      omittedSupportTokenCount: Int,
      fallbackStateIdentifier: String,
      fallbackDetail: String?
    ) -> String {
      let routeSummary =
        selectedPreferenceTitle == effectiveRouteTitle
        ? "Runtime: \(effectiveRouteTitle)"
        : "Runtime: \(effectiveRouteTitle); Selected preference: \(selectedPreferenceTitle)"
      var pieces = [
        routeSummary,
        "Private workspace: \(readinessHelpText(supportClassificationIdentifier))",
      ]
      if fallbackStateIdentifier == "fallback" {
        pieces.append(fallbackDetail ?? "Fallback active")
      }
      if omittedSupportTokenCount > 0 {
        pieces.append(
          "\(omittedSupportTokenCount) support detail\(omittedSupportTokenCount == 1 ? "" : "s") hidden"
        )
      }
      return boundedText(pieces.joined(separator: "; "), limit: helpTextLimit)
    }

    private static func fallbackStateIdentifier(
      for snapshot: SessionExecutionEnvironmentSnapshot
    ) -> String {
      let fallbackReason =
        snapshot.fallbackReason?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return fallbackReason.isEmpty ? "direct" : "fallback"
    }

    private static func fallbackDetail(
      for snapshot: SessionExecutionEnvironmentSnapshot
    ) -> String? {
      guard
        let fallbackReason = snapshot.fallbackReason?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !fallbackReason.isEmpty
      else {
        return nil
      }
      return "Fallback: \(AgentExecutionLaunchPlan.userFacingFallbackReason(fallbackReason))"
    }

    private static func readinessBadgeText(_ identifier: String) -> String {
      switch identifier {
      case "ready":
        return "Ready"
      case "not-provisioned":
        return "Workspace not prepared"
      case "downloading-ipsw":
        return "Downloading macOS"
      case "installing":
        return "Installing macOS"
      case "first-boot-pending", "guest-prepping":
        return "Finishing setup"
      case "provisioning-dev-tools":
        return "Installing developer tools"
      case "unavailable":
        return "Workspace unavailable"
      case "error":
        return "Needs attention"
      default:
        return "Readiness not checked"
      }
    }

    private static func readinessHelpText(_ identifier: String) -> String {
      switch identifier {
      case "ready":
        return "ready"
      case "not-provisioned":
        return "not prepared yet"
      case "downloading-ipsw":
        return "downloading macOS"
      case "installing":
        return "installing macOS"
      case "first-boot-pending", "guest-prepping":
        return "finishing setup"
      case "provisioning-dev-tools":
        return "installing developer tools"
      case "unavailable":
        return "unavailable"
      case "error":
        return "needs attention"
      default:
        return "not checked yet"
      }
    }

    private static func preferenceTitle(identifier: String, fallback: String) -> String {
      switch identifier {
      case AgentExecutionEnvironmentPreference.sharedVM.rawValue:
        return "Private workspace"
      default:
        return sanitizedTitle(fallback, fallback: "Unknown")
      }
    }

    private static func routeTitle(identifier: String, fallback: String) -> String {
      switch identifier {
      case "shared-vm":
        return "Private workspace"
      case "native-macos":
        return "This Mac"
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
    handoffDigest: PlanHandoffDigest(plan: nil),
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
  var handoffDigest: PlanHandoffDigest
  var verifyCommand: String?
  var feedback: String?
  var notes: [String]
  var commits: [SessionCommit]
  var failedVerify: FailedVerify?
  var runtimeRouteSummary: String?
  var runtimeRouteDescriptor: RuntimeRouteDescriptor
  var auditArtifacts: [AuditArtifact]

  init(
    sessionNumber: Int,
    status: SessionStatus,
    statusText: String,
    startedAt: Date,
    planExcerpt: String?,
    handoffDigest: PlanHandoffDigest = PlanHandoffDigest(plan: nil),
    verifyCommand: String?,
    feedback: String?,
    notes: [String],
    commits: [SessionCommit],
    failedVerify: FailedVerify?,
    runtimeRouteSummary: String?,
    runtimeRouteDescriptor: RuntimeRouteDescriptor = .unavailable,
    auditArtifacts: [AuditArtifact] = []
  ) {
    self.sessionNumber = sessionNumber
    self.status = status
    self.statusText = statusText
    self.startedAt = startedAt
    self.planExcerpt = planExcerpt
    self.handoffDigest = handoffDigest
    self.verifyCommand = verifyCommand
    self.feedback = feedback
    self.notes = notes
    self.commits = commits
    self.failedVerify = failedVerify
    self.runtimeRouteSummary = runtimeRouteSummary
    self.runtimeRouteDescriptor = runtimeRouteDescriptor
    self.auditArtifacts = auditArtifacts
  }
}

struct PlanSessionHistoryClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_500

  var text: String

  init(
    item: PlanSessionHistoryItem,
    reliabilityCue: PlanReliabilityFeedback.RunCue? = nil
  ) {
    var sections: [String] = [
      "Compass Run History Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded audit context. Do not invent files, commands, "
        + "credentials, outcomes, commits, or extra scope.",
      "- Use the recorded handoff, verify proof, notes, and commits to decide what can "
        + "be trusted before continuing.",
      "- If the run needs attention, repair from the recorded cue or failure detail before "
        + "starting new work.",
      "",
      "Run: #\(item.sessionNumber)",
      "Status: \(item.statusText)",
      "Started: \(item.startedAt.formatted(date: .abbreviated, time: .shortened))",
    ]

    if let reliabilityCue {
      sections.append("")
      sections.append("Attention cue:")
      sections.append("\(reliabilityCue.label): \(reliabilityCue.detail)")
    }

    sections.append("")
    sections.append("Handoff:")
    sections.append("Status: \(item.handoffDigest.title)")
    sections.append(item.handoffDigest.detail)

    if let outcome = item.handoffDigest.outcome {
      sections.append("Outcome: \(outcome)")
    } else if let planExcerpt = item.planExcerpt {
      sections.append("Plan excerpt: \(planExcerpt)")
    }

    if let whyItMatters = item.handoffDigest.whyItMatters {
      sections.append("Why it matters: \(whyItMatters)")
    }

    if !item.handoffDigest.acceptanceChecks.isEmpty {
      sections.append("Acceptance checks:")
      sections.append(contentsOf: item.handoffDigest.acceptanceChecks.map { "- \($0)" })
    }

    if !item.handoffDigest.missingPieces.isEmpty {
      sections.append("Missing handoff detail:")
      sections.append(contentsOf: item.handoffDigest.missingPieces.map { "- \($0.label)" })
    }

    sections.append("")
    sections.append("Verify:")
    sections.append(item.verifyCommand ?? "No verify command recorded.")

    if item.runtimeRouteDescriptor.isSnapshotAvailable {
      sections.append("")
      sections.append("Runtime route:")
      sections.append(item.runtimeRouteDescriptor.badgeText)
      sections.append(item.runtimeRouteDescriptor.helpText)
    } else if let runtimeRouteSummary = item.runtimeRouteSummary {
      sections.append("")
      sections.append("Runtime route:")
      sections.append(runtimeRouteSummary)
    }

    if !item.auditArtifacts.isEmpty {
      sections.append("")
      sections.append("Audit artifacts:")
      sections.append(
        contentsOf: item.auditArtifacts.prefix(6).map { artifact in
          "- \(artifact.label): \(artifact.detail)"
        }
      )
      if item.auditArtifacts.count > 6 {
        sections.append("- ...\(item.auditArtifacts.count - 6) more audit artifacts not shown")
      }
    }

    if let failedVerify = item.failedVerify {
      sections.append("")
      sections.append("Failed verify:")
      sections.append("\(failedVerify.command) (\(failedVerify.exitCodeText))")
      sections.append(failedVerify.tail)
    }

    if let feedback = item.feedback {
      sections.append("")
      sections.append("Feedback:")
      sections.append(feedback)
    }

    if !item.notes.isEmpty {
      sections.append("")
      sections.append("Notes:")
      sections.append(contentsOf: item.notes.prefix(5).map { "- \($0)" })
      if item.notes.count > 5 {
        sections.append("- ...\(item.notes.count - 5) more notes not shown")
      }
    }

    if !item.commits.isEmpty {
      sections.append("")
      sections.append("Commits:")
      sections.append(contentsOf: item.commits.prefix(8).map { "- \($0.short) \($0.subject)" })
      if item.commits.count > 8 {
        sections.append("- ...\(item.commits.count - 8) more commits not shown")
      }
    }

    text = PlanSessionHistoryClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum PlanSessionHistoryClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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
      return "Private workspace"
    case .nativeRuntime:
      return "This Mac/Fallback"
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
      return "private workspace runs"
    case .nativeRuntime:
      return "runs using this Mac or fallback"
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
    planExcerptLimit: Int = defaultPlanExcerptLimit,
    auditManifests: [Int: SessionAuditManifest] = [:]
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
        let auditArtifacts = (auditManifests[session.session]?.artifacts ?? [])
          .map(PlanSessionHistoryItem.AuditArtifact.init)
        return PlanSessionHistoryItem(
          sessionNumber: session.session,
          status: session.status,
          statusText: statusText(for: session.status),
          startedAt: Date(timeIntervalSince1970: session.startedAt / 1000),
          planExcerpt: excerpt(session.plan, limit: planExcerptLimit),
          handoffDigest: PlanHandoffDigest(plan: session.plan),
          verifyCommand: nonEmpty(session.verify),
          feedback: nonEmpty(session.feedback),
          notes: session.notes,
          commits: session.commits,
          failedVerify: failedVerify(from: session),
          runtimeRouteSummary: latestRuntimeSnapshot?.routeSummary,
          runtimeRouteDescriptor: PlanSessionHistoryItem.RuntimeRouteDescriptor(
            snapshot: latestRuntimeSnapshot
          ),
          auditArtifacts: auditArtifacts
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
