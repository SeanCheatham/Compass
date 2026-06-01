import Foundation

struct LiveTimelineGuide: Equatable, Sendable {
  static let detailLimit = 240
  static let identifierLimit = 1_200

  enum Tone: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case complete
    case attention
  }

  struct Checkpoint: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImageName: String
  }

  struct EventSummary: Identifiable, Equatable, Sendable {
    var id: String
    var level: String
    var kind: String
    var status: String
    var text: String
    var detail: String?
  }

  static let latestEventLimit = 5
  static let eventTextLimit = 140
  static let eventDetailLimit = 220

  var shouldShow: Bool
  var title: String
  var detail: String
  var statusLabel: String
  var tone: Tone
  var systemImageName: String
  var checkpoints: [Checkpoint]
  var phaseLabel: String
  var eventCount: Int
  var runningEventCount: Int
  var failedEventCount: Int
  var latestEvents: [EventSummary]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    shouldShow && tone != .running
  }

  init(
    phase: LoopPhase,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    liveLog: [LiveLine],
    reliabilityStatus: ProjectReliabilityStatus
  ) {
    let eventCount = liveLog.count
    let runningEventCount = liveLog.filter { $0.status == .running }.count
    let failedEventCount = liveLog.filter {
      $0.status == .failed || $0.level == .error
    }.count
    let modeLabel = isAutoPlaying ? "Loop" : "Single run"

    shouldShow = reliabilityStatus.isEmpty
    phaseLabel = phase.rawValue
    self.eventCount = eventCount
    self.runningEventCount = runningEventCount
    self.failedEventCount = failedEventCount
    latestEvents = Self.latestEvents(from: liveLog)

    if isPaused {
      title = "Factory Paused"
      detail =
        "Compass is holding the loop at a safe gate. Resume when the plan still looks right, or stop to keep the current state unchanged."
      statusLabel = "Paused"
      tone = .paused
      systemImageName = "pause.circle.fill"
      checkpoints = Self.pausedCheckpoints()
    } else if isRunning || isAutoPlaying {
      let presentation = Self.runningPresentation(
        phase: phase,
        modeLabel: modeLabel,
        runningEventCount: runningEventCount
      )
      title = presentation.title
      detail = presentation.detail
      statusLabel = presentation.statusLabel
      tone = .running
      systemImageName = presentation.systemImageName
      checkpoints = Self.runningCheckpoints()
    } else if eventCount == 0 {
      title = "Ready for a Run"
      detail =
        "This timeline will fill with agent notes, commands, file changes, and checks once Compass starts working."
      statusLabel = "No events yet"
      tone = .idle
      systemImageName = "play.circle"
      checkpoints = Self.idleCheckpoints()
    } else if failedEventCount > 0 || phase == .failed {
      title = "Latest Run Needs Review"
      detail =
        "The timeline is preserving the failed or warning events so the next run can start from the concrete symptom instead of guessing."
      statusLabel = Self.eventLabel(eventCount)
      tone = .attention
      systemImageName = "exclamationmark.triangle.fill"
      checkpoints = Self.reviewCheckpoints()
    } else if phase == .succeeded {
      title = "Latest Run Succeeded"
      detail =
        "The timeline keeps the completed work visible, including commands and proof, so you can audit what Compass changed before starting again."
      statusLabel = Self.eventLabel(eventCount)
      tone = .complete
      systemImageName = "checkmark.circle.fill"
      checkpoints = Self.completedCheckpoints()
    } else {
      title = "Timeline Ready"
      detail =
        "The latest events remain available for audit. Start Plan for a fresh proposal, or run the loop when you want Compass to continue."
      statusLabel = Self.eventLabel(eventCount)
      tone = .idle
      systemImageName = "clock.arrow.circlepath"
      checkpoints = Self.idleCheckpoints()
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      statusLabel: statusLabel,
      tone: tone,
      phase: phase,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      eventCount: eventCount,
      runningEventCount: runningEventCount,
      failedEventCount: failedEventCount,
      checkpoints: checkpoints,
      liveLog: liveLog
    )
  }

  private static func runningPresentation(
    phase: LoopPhase,
    modeLabel: String,
    runningEventCount: Int
  ) -> (title: String, detail: String, statusLabel: String, systemImageName: String) {
    let statusLabel =
      runningEventCount > 0
      ? "Live: \(runningEventCount) running"
      : modeLabel

    switch phase {
    case .planning:
      return (
        "Planning Next Slice",
        "Compass is choosing one executable step, the proof it should run, and the handoff Develop will receive.",
        statusLabel,
        "map.fill"
      )
    case .developing:
      return (
        "Developing Current Slice",
        "Compass is editing toward the saved Immediate Work. Commands, file changes, and agent notes appear here as they happen.",
        statusLabel,
        "hammer.fill"
      )
    case .verifying:
      return (
        "Verifying Work",
        "Compass is running the planned proof command and will keep the result visible for review.",
        statusLabel,
        "checkmark.seal.fill"
      )
    case .reviewing:
      return (
        "Reviewing Result",
        "Compass is checking whether the finished slice is small, grounded, and ready to keep.",
        statusLabel,
        "text.magnifyingglass"
      )
    default:
      return (
        "Run In Progress",
        "Compass is working through the factory loop. New events will appear here as it plans, edits, checks, and reviews.",
        statusLabel,
        "play.circle.fill"
      )
    }
  }

  private static func idleCheckpoints() -> [Checkpoint] {
    [
      Checkpoint(
        id: "plan",
        label: "Plan",
        detail: "Choose the next slice before code changes.",
        systemImageName: "map"
      ),
      Checkpoint(
        id: "develop",
        label: "Develop",
        detail: "Make the scoped edit.",
        systemImageName: "hammer"
      ),
      Checkpoint(
        id: "verify",
        label: "Verify",
        detail: "Run the promised proof.",
        systemImageName: "checkmark.seal"
      ),
    ]
  }

  private static func runningCheckpoints() -> [Checkpoint] {
    [
      Checkpoint(
        id: "notes",
        label: "Notes",
        detail: "Agent decisions and handoffs.",
        systemImageName: "sparkles"
      ),
      Checkpoint(
        id: "commands",
        label: "Commands",
        detail: "Checks Compass is running.",
        systemImageName: "terminal"
      ),
      Checkpoint(
        id: "files",
        label: "Files",
        detail: "Edits made during the run.",
        systemImageName: "doc.badge.gearshape"
      ),
    ]
  }

  private static func pausedCheckpoints() -> [Checkpoint] {
    [
      Checkpoint(
        id: "context",
        label: "Context saved",
        detail: "The current gate remains visible.",
        systemImageName: "tray.full"
      ),
      Checkpoint(
        id: "resume",
        label: "Resume",
        detail: "Continue when the goal still fits.",
        systemImageName: "play.circle"
      ),
      Checkpoint(
        id: "stop",
        label: "Stop",
        detail: "End without starting another phase.",
        systemImageName: "stop.circle"
      ),
    ]
  }

  private static func reviewCheckpoints() -> [Checkpoint] {
    [
      Checkpoint(
        id: "symptom",
        label: "Symptom",
        detail: "Start with the visible failure.",
        systemImageName: "exclamationmark.triangle"
      ),
      Checkpoint(
        id: "narrow",
        label: "Narrow",
        detail: "Ask for the smallest fix.",
        systemImageName: "scope"
      ),
      Checkpoint(
        id: "proof",
        label: "Proof",
        detail: "Rerun the captured check.",
        systemImageName: "checkmark.seal"
      ),
    ]
  }

  private static func completedCheckpoints() -> [Checkpoint] {
    [
      Checkpoint(
        id: "audit",
        label: "Audit",
        detail: "Review commands and changes.",
        systemImageName: "text.magnifyingglass"
      ),
      Checkpoint(
        id: "proof",
        label: "Proof",
        detail: "Keep the verification visible.",
        systemImageName: "checkmark.seal"
      ),
      Checkpoint(
        id: "next",
        label: "Next",
        detail: "Start another focused slice.",
        systemImageName: "arrow.right.circle"
      ),
    ]
  }

  private static func eventLabel(_ count: Int) -> String {
    count == 1 ? "1 event" : "\(count) events"
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    statusLabel: String,
    tone: Tone,
    phase: LoopPhase,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    eventCount: Int,
    runningEventCount: Int,
    failedEventCount: Int,
    checkpoints: [Checkpoint],
    liveLog: [LiveLine]
  ) -> String {
    let latestEvents = liveLog.suffix(4).map { line in
      [
        line.text,
        line.detail ?? "",
      ]
      .filter { !$0.isEmpty }
      .joined(separator: ":")
    }
    .joined(separator: ",")

    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "status:\(statusLabel)",
      "tone:\(tone.rawValue)",
      "phase:\(phase.rawValue)",
      "running:\(isRunning)",
      "auto:\(isAutoPlaying)",
      "paused:\(isPaused)",
      "events:\(eventCount)",
      "runningEvents:\(runningEventCount)",
      "failedEvents:\(failedEventCount)",
      "checkpoints:\(checkpoints.map(\.id).joined(separator: ","))",
      "latest:\(latestEvents)",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }

  private static func latestEvents(from liveLog: [LiveLine]) -> [EventSummary] {
    let latest = liveLog.suffix(Self.latestEventLimit)
    let firstIndex = liveLog.count - latest.count

    return latest.enumerated().map { offset, line in
      let text = normalizedLine(line.text, fallback: "Untitled event", limit: eventTextLimit)
      let detail = line.detail.map {
        normalizedLine($0, fallback: "", limit: eventDetailLimit)
      }
      .flatMap { $0.isEmpty ? nil : $0 }

      return EventSummary(
        id: "\(firstIndex + offset)-\(kindLabel(line.kind))-\(statusLabel(line.status))",
        level: levelLabel(line.level),
        kind: kindLabel(line.kind),
        status: statusLabel(line.status),
        text: text,
        detail: detail
      )
    }
  }

  private static func normalizedLine(
    _ text: String,
    fallback: String,
    limit: Int
  ) -> String {
    let collapsed =
      text
      .split { character in
        character.isWhitespace
      }
      .joined(separator: " ")
    let candidate = collapsed.isEmpty ? fallback : collapsed
    return StringUtils.boundedText(candidate, limit: limit)
  }

  private static func levelLabel(_ level: LiveLine.Level) -> String {
    switch level {
    case .info:
      return "info"
    case .success:
      return "success"
    case .warning:
      return "warning"
    case .error:
      return "error"
    case .raw:
      return "raw"
    }
  }

  private static func kindLabel(_ kind: LiveLine.Kind) -> String {
    switch kind {
    case .message:
      return "message"
    case .lifecycle:
      return "lifecycle"
    case .command:
      return "command"
    case .agentMessage:
      return "agent-message"
    case .fileChange:
      return "file-change"
    }
  }

  private static func statusLabel(_ status: LiveLine.Status) -> String {
    switch status {
    case .none:
      return "none"
    case .running:
      return "running"
    case .completed:
      return "completed"
    case .failed:
      return "failed"
    }
  }
}

struct LiveTimelineClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_200

  var text: String

  init(guide: LiveTimelineGuide) {
    guard guide.shouldShow else {
      text = ""
      return
    }

    var sections: [String] = [
      "Compass Live Timeline Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded run-state context. Do not invent commands, files, failures, commits, verification results, or completed work.",
      "- If the run is active or paused, preserve the current gate unless the user explicitly asks to resume or stop.",
      "- If the status needs attention, start from the concrete latest events and ask for the smallest repair plus a proof rerun.",
      "- If the run succeeded, audit commands and verification before proposing another focused slice.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Phase: \(guide.phaseLabel)",
      "Timeline: \(guide.statusLabel)",
      "Events: \(Self.countSummary(guide))",
      "Detail: \(guide.detail)",
      "",
      "Checkpoints:",
    ]

    for checkpoint in guide.checkpoints {
      sections.append("- \(checkpoint.label): \(checkpoint.detail)")
    }

    sections.append("")
    sections.append("Latest events:")

    if guide.latestEvents.isEmpty {
      sections.append("- No live events captured yet.")
    } else {
      for event in guide.latestEvents {
        sections.append(Self.eventLine(event))
      }
    }

    text = LiveTimelineClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func countSummary(_ guide: LiveTimelineGuide) -> String {
    "\(guide.eventCount) total, \(guide.runningEventCount) running, \(guide.failedEventCount) failed"
  }

  private static func eventLine(_ event: LiveTimelineGuide.EventSummary) -> String {
    let prefix = "- [\(event.status) \(event.kind) \(event.level)] \(event.text)"
    guard let detail = event.detail else { return prefix }
    return "\(prefix): \(detail)"
  }
}

private enum LiveTimelineClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
