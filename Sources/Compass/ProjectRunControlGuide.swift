import Foundation

struct ProjectRunControlGuide: Equatable {
  var primaryHelp: String
  var primaryKind: Kind
  var readiness: Readiness
  var options: [Option]

  var primaryOption: Option {
    options.first { $0.kind == primaryKind } ?? options[0]
  }

  var alternativeOptions: [Option] {
    options.filter { $0.kind != primaryOption.kind }
  }

  init(
    state: PlanState,
    reliabilityStatus: ProjectReliabilityStatus,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    languageProfile: RepositoryLanguageProfile = .empty,
    drafts: String = ""
  ) {
    let canStart = hasRepository && !isRunning && !isAutoPlaying
    let draftIntakeGuide = DraftIntakeGuide(drafts: drafts)
    let handoffReadiness = HandoffReadiness(
      state: state,
      languageProfile: languageProfile
    )
    let hasImmediate = handoffReadiness.hasImmediate
    let canDevelop = hasImmediate && handoffReadiness.canDevelop
    readiness = Self.readiness(
      handoffReadiness: handoffReadiness,
      reliabilityStatus: reliabilityStatus,
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      draftIntakeGuide: draftIntakeGuide
    )
    primaryKind = Self.primaryKind(
      reliabilityStatus: reliabilityStatus,
      hasImmediate: hasImmediate,
      canDevelop: canDevelop,
      isPaused: isPaused
    )
    let resumeCopy = isPaused ? "Resume the factory from its paused gate." : nil
    let recoveryCopy =
      reliabilityStatus.isEmpty
      ? nil
      : "\(reliabilityStatus.primaryCue): \(reliabilityStatus.actionLabel)."
    let loopDetail: String
    if let resumeCopy {
      loopDetail = resumeCopy
    } else if let recoveryCopy {
      loopDetail = recoveryCopy
    } else if hasImmediate && !handoffReadiness.canDevelop {
      loopDetail =
        "Ask Plan to repair Immediate Work, then continue only if the handoff becomes executable."
    } else if hasImmediate {
      loopDetail = "Let Compass plan, develop, verify, review, and keep going."
    } else if !draftIntakeGuide.isEmpty {
      loopDetail = Self.loopDetail(draftIntakeGuide: draftIntakeGuide)
    } else {
      loopDetail = "Let Plan choose the next slice, then Develop it if one is found."
    }

    options = [
      Option(
        kind: .loop,
        title: isPaused ? "Resume Loop" : "Run Loop",
        detail: loopDetail,
        systemImage: "play.circle.fill",
        isEnabled: canStart
      ),
      Option(
        kind: .planOnly,
        title: Self.planOnlyTitle(for: reliabilityStatus),
        detail: Self.planOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          handoffReadiness: handoffReadiness,
          draftIntakeGuide: draftIntakeGuide
        ),
        systemImage: "map",
        isEnabled: canStart
      ),
      Option(
        kind: .developOnly,
        title: Self.developOnlyTitle(for: reliabilityStatus),
        detail: Self.developOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          handoffReadiness: handoffReadiness
        ),
        systemImage: "hammer.fill",
        isEnabled: canStart && canDevelop
      ),
    ]

    primaryHelp = Self.primaryHelp(
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      hasImmediate: hasImmediate,
      handoffReadiness: handoffReadiness,
      reliabilityStatus: reliabilityStatus,
      draftIntakeGuide: draftIntakeGuide
    )
  }

  enum Kind: Hashable {
    case loop
    case planOnly
    case developOnly
  }

  struct Readiness: Equatable {
    var title: String
    var detail: String
    var systemImage: String
  }

  struct Option: Identifiable, Equatable {
    var kind: Kind
    var title: String
    var detail: String
    var systemImage: String
    var isEnabled: Bool

    var id: Kind { kind }
  }

  private static func primaryKind(
    reliabilityStatus: ProjectReliabilityStatus,
    hasImmediate: Bool,
    canDevelop: Bool,
    isPaused: Bool
  ) -> Kind {
    if isPaused {
      return .loop
    }

    if hasImmediate && !canDevelop {
      switch reliabilityStatus.primaryKind {
      case .dirtyWorktree, .promotionFailed:
        return .loop
      case .rejectedPlan, .resumeDevelop, .developBlocked, .developFailed, .failedVerify, nil:
        return .planOnly
      }
    }

    switch reliabilityStatus.primaryKind {
    case .rejectedPlan:
      return .planOnly
    case .resumeDevelop:
      return hasImmediate ? .developOnly : .planOnly
    case .developBlocked, .developFailed, .failedVerify:
      return hasImmediate ? .developOnly : .planOnly
    case .dirtyWorktree, .promotionFailed, nil:
      return .loop
    }
  }

  private static func planOnlyTitle(for reliabilityStatus: ProjectReliabilityStatus) -> String {
    reliabilityStatus.primaryKind == .rejectedPlan ? "Retry Plan" : "Run Plan Only"
  }

  private static func planOnlyDetail(
    reliabilityStatus: ProjectReliabilityStatus,
    handoffReadiness: HandoffReadiness,
    draftIntakeGuide: DraftIntakeGuide
  ) -> String {
    if reliabilityStatus.primaryKind == .rejectedPlan {
      return "Ask Plan to repair the rejected handoff before Develop starts."
    }

    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return "Ask Plan to add \(handoffReadiness.missingLabel) before Develop starts."
    }

    if !handoffReadiness.hasImmediate, !draftIntakeGuide.isEmpty {
      return Self.planOnlyDetail(draftIntakeGuide: draftIntakeGuide)
    }

    return handoffReadiness.hasImmediate
      ? "Ask Plan to refine or replace the next slice, then stop before Develop."
      : "Ask Plan to choose one executable next slice, then stop for review."
  }

  private static func developOnlyTitle(for reliabilityStatus: ProjectReliabilityStatus) -> String {
    switch reliabilityStatus.primaryKind {
    case .resumeDevelop:
      return "Resume Develop"
    case .developBlocked, .developFailed, .failedVerify:
      return "Retry Develop"
    case .rejectedPlan, .dirtyWorktree, .promotionFailed, nil:
      return "Run Develop Only"
    }
  }

  private static func developOnlyDetail(
    reliabilityStatus: ProjectReliabilityStatus,
    handoffReadiness: HandoffReadiness
  ) -> String {
    guard handoffReadiness.hasImmediate else {
      return "Disabled until Plan selects Immediate Work."
    }

    guard handoffReadiness.canDevelop else {
      return "Disabled until Immediate Work has \(handoffReadiness.missingLabel)."
    }

    switch reliabilityStatus.primaryKind {
    case .resumeDevelop:
      return "Start Develop from the saved Immediate Work."
    case .developBlocked, .developFailed, .failedVerify:
      return "Retry the current Immediate Work with the captured issue still visible."
    case .rejectedPlan, .dirtyWorktree, .promotionFailed, nil:
      return "Build the current Immediate Work now, using the saved verify command."
    }
  }

  private static func readiness(
    handoffReadiness: HandoffReadiness,
    reliabilityStatus: ProjectReliabilityStatus,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    draftIntakeGuide: DraftIntakeGuide
  ) -> Readiness {
    if !hasRepository {
      return Readiness(
        title: "Repository needed",
        detail: "Add a Git repository before running the factory.",
        systemImage: "folder.badge.plus"
      )
    }

    if isRunning || isAutoPlaying {
      return Readiness(
        title: "Run in progress",
        detail: "Compass is already running this project.",
        systemImage: "play.circle"
      )
    }

    if isPaused {
      return Readiness(
        title: "Paused at gate",
        detail: "Resume the loop or choose a different pause point.",
        systemImage: "pause.circle"
      )
    }

    if !reliabilityStatus.isEmpty {
      return Readiness(
        title: reliabilityStatus.primaryCue,
        detail: "\(reliabilityStatus.actionLabel). \(reliabilityStatus.detail)",
        systemImage: reliabilityStatus.systemImage
      )
    }

    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return Readiness(
        title: "Plan repair needed",
        detail: "Immediate Work needs \(handoffReadiness.missingLabel) before Develop.",
        systemImage: "list.bullet.clipboard"
      )
    }

    if handoffReadiness.canDevelop {
      return Readiness(
        title: "Ready for Develop",
        detail: "Immediate Work has an outcome, acceptance checks, and a runnable verify command.",
        systemImage: "checkmark.seal"
      )
    }

    if !draftIntakeGuide.isEmpty {
      return Readiness(
        title: draftIntakeGuide.status == .ready ? "Drafts ready for Plan" : "Drafts need detail",
        detail: draftIntakeGuide.detail,
        systemImage: draftIntakeGuide.status == .ready ? "checkmark.seal" : "list.bullet.clipboard"
      )
    }

    return Readiness(
      title: "Plan needed",
      detail: "Plan should choose one executable next slice before Develop.",
      systemImage: "map"
    )
  }

  private static func primaryHelp(
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    hasImmediate: Bool,
    handoffReadiness: HandoffReadiness,
    reliabilityStatus: ProjectReliabilityStatus,
    draftIntakeGuide: DraftIntakeGuide
  ) -> String {
    if !hasRepository {
      return "Add a Git repository before running the factory."
    }
    if isRunning || isAutoPlaying {
      return "Compass is already running."
    }
    if isPaused {
      return "Choose how to resume the paused factory."
    }
    if !reliabilityStatus.isEmpty {
      return "\(reliabilityStatus.primaryCue): \(reliabilityStatus.actionLabel)"
    }
    if hasImmediate && !handoffReadiness.canDevelop {
      return "Repair Immediate Work before Develop: add \(handoffReadiness.missingLabel)."
    }
    if hasImmediate {
      return "Choose whether to run the full loop, re-plan, or develop the current slice."
    }
    if !draftIntakeGuide.isEmpty {
      return
        "\(draftIntakeGuide.scoreLabel) in Drafts; Plan will turn the queue into one executable slice."
    }
    return "Run Plan first, or let the full loop choose and build the next slice."
  }

  private static func loopDetail(draftIntakeGuide: DraftIntakeGuide) -> String {
    switch draftIntakeGuide.status {
    case .empty:
      return "Let Plan choose the next slice, then Develop it if one is found."
    case .ready:
      return
        "Plan will use \(draftIntakeGuide.entryCountLabel) to choose one executable slice, then Develop it."
    case .needsDetail:
      return
        "Plan can use \(draftIntakeGuide.entryCountLabel), but Drafts shows missing signals before Develop starts."
    }
  }

  private static func planOnlyDetail(draftIntakeGuide: DraftIntakeGuide) -> String {
    switch draftIntakeGuide.status {
    case .empty:
      return "Ask Plan to choose one executable next slice, then stop for review."
    case .ready:
      return "Ask Plan to turn \(draftIntakeGuide.entryCountLabel) into one executable handoff."
    case .needsDetail:
      return "Ask Plan to use the queue, with Drafts showing which signals still need detail."
    }
  }

  private struct HandoffReadiness: Equatable {
    var hasImmediate: Bool
    var canDevelop: Bool
    var missingLabel: String

    init(
      state: PlanState,
      languageProfile: RepositoryLanguageProfile
    ) {
      hasImmediate = state.immediate != nil
      let repairGuide = PlanHandoffRepairGuide(
        plan: state.immediate?.plan,
        verify: state.immediate?.verify,
        languageProfile: languageProfile
      )
      canDevelop = repairGuide.status == .ready
      let missing = repairGuide.steps
        .filter { $0.isRequired && !$0.isSatisfied }
        .map(\.title)
      missingLabel =
        missing.isEmpty
        ? "an executable handoff"
        : missing.joined(separator: " and ")
    }
  }
}
