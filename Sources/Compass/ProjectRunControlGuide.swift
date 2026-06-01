import Foundation

struct ProjectRunControlGuide: Equatable {
  var primaryHelp: String
  var primaryKind: Kind
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
    isPaused: Bool
  ) {
    let canStart = hasRepository && !isRunning && !isAutoPlaying
    let hasImmediate = state.immediate != nil
    primaryKind = Self.primaryKind(
      reliabilityStatus: reliabilityStatus,
      hasImmediate: hasImmediate,
      isPaused: isPaused
    )
    let resumeCopy = isPaused ? "Resume the factory from its paused gate." : nil
    let recoveryCopy =
      reliabilityStatus.isEmpty
      ? nil
      : "\(reliabilityStatus.primaryCue): \(reliabilityStatus.actionLabel)."

    options = [
      Option(
        kind: .loop,
        title: isPaused ? "Resume Loop" : "Run Loop",
        detail: resumeCopy
          ?? recoveryCopy
          ?? (hasImmediate
            ? "Let Compass plan, develop, verify, review, and keep going."
            : "Let Plan choose the next slice, then Develop it if one is found."),
        systemImage: "play.circle.fill",
        isEnabled: canStart
      ),
      Option(
        kind: .planOnly,
        title: Self.planOnlyTitle(for: reliabilityStatus),
        detail: Self.planOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          hasImmediate: hasImmediate
        ),
        systemImage: "map",
        isEnabled: canStart
      ),
      Option(
        kind: .developOnly,
        title: Self.developOnlyTitle(for: reliabilityStatus),
        detail: Self.developOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          hasImmediate: hasImmediate
        ),
        systemImage: "hammer.fill",
        isEnabled: canStart && hasImmediate
      ),
    ]

    primaryHelp = Self.primaryHelp(
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      hasImmediate: hasImmediate,
      reliabilityStatus: reliabilityStatus
    )
  }

  enum Kind: Hashable {
    case loop
    case planOnly
    case developOnly
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
    isPaused: Bool
  ) -> Kind {
    if isPaused {
      return .loop
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
    hasImmediate: Bool
  ) -> String {
    if reliabilityStatus.primaryKind == .rejectedPlan {
      return "Ask Plan to repair the rejected handoff before Develop starts."
    }

    return hasImmediate
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
    hasImmediate: Bool
  ) -> String {
    guard hasImmediate else {
      return "Disabled until Plan selects Immediate Work."
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

  private static func primaryHelp(
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    hasImmediate: Bool,
    reliabilityStatus: ProjectReliabilityStatus
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
    if hasImmediate {
      return "Choose whether to run the full loop, re-plan, or develop the current slice."
    }
    return "Run Plan first, or let the full loop choose and build the next slice."
  }
}
