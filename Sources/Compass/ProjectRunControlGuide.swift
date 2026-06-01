import Foundation

struct ProjectRunControlGuide: Equatable {
  var primaryHelp: String
  var options: [Option]

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
        title: "Run Plan Only",
        detail: hasImmediate
          ? "Ask Plan to refine or replace the next slice, then stop before Develop."
          : "Ask Plan to choose one executable next slice, then stop for review.",
        systemImage: "map",
        isEnabled: canStart
      ),
      Option(
        kind: .developOnly,
        title: "Run Develop Only",
        detail: hasImmediate
          ? "Build the current Immediate Work now, using the saved verify command."
          : "Disabled until Plan selects Immediate Work.",
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
