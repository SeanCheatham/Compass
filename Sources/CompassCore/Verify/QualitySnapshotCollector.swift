import Foundation

/// Shared post-verify coverage + mutation collection used by headless and UI loops.
public enum QualitySnapshotCollector {
  public struct Context {
    public var workspace: CompassWorkspace
    public var sessionNumber: Int?
    public var changedFiles: [String]
    public var repoURL: URL

    public init(
      workspace: CompassWorkspace,
      sessionNumber: Int?,
      changedFiles: [String],
      repoURL: URL
    ) {
      self.workspace = workspace
      self.sessionNumber = sessionNumber
      self.changedFiles = changedFiles
      self.repoURL = repoURL
    }
  }

  public enum EventKind: String, Sendable, Equatable {
    case coverageSnapshot = "coverage_snapshot"
    case mutationSnapshot = "mutation_snapshot"
    case vmResetWorkspace = "vm_reset_workspace"
  }

  public struct Event: Sendable, Equatable {
    public var kind: EventKind
    public var level: String
    public var status: String
    public var message: String
    public var detail: String?
    public var metadata: [String: String]

    public init(
      kind: EventKind,
      level: String = "info",
      status: String,
      message: String,
      detail: String? = nil,
      metadata: [String: String] = [:]
    ) {
      self.kind = kind
      self.level = level
      self.status = status
      self.message = message
      self.detail = detail
      self.metadata = metadata
    }
  }

  public struct Outcome: Sendable {
    public var coverage: CoverageSnapshot?
    public var mutation: MutationSnapshot?
    public var events: [Event]
    public var coverageLog: String?
    public var mutationLog: String?
    public var mutationCommand: String?

    public init(
      coverage: CoverageSnapshot? = nil,
      mutation: MutationSnapshot? = nil,
      events: [Event] = [],
      coverageLog: String? = nil,
      mutationLog: String? = nil,
      mutationCommand: String? = nil
    ) {
      self.coverage = coverage
      self.mutation = mutation
      self.events = events
      self.coverageLog = coverageLog
      self.mutationLog = mutationLog
      self.mutationCommand = mutationCommand
    }
  }

  public static func collect(
    context: Context,
    bash: any AgentBashRunner,
    resetGuestDirt: Bool = true
  ) async -> Outcome {
    var outcome = Outcome()
    let timeout = QualityCollectionTimeout.seconds()

    do {
      let result = try await bash.run(
        command: GeneratedProjectQuality.coverageCollectCommand,
        workingDirectory: context.repoURL,
        timeout: timeout
      )
      outcome.coverageLog =
        "$ \(GeneratedProjectQuality.coverageCollectCommand)\n\n" + result.stdout + "\n"
        + result.stderr
      var snapshot = GeneratedProjectQuality.parseCoverageReport(
        output: result.stdout + "\n" + result.stderr
      )
      if snapshot.overallLineCoveragePercent == nil && snapshot.files.isEmpty {
        outcome.events.append(
          Event(
            kind: .coverageSnapshot,
            level: "warning",
            status: "failed",
            message:
              "Coverage collection produced no data (exit \(result.exitCode)); no snapshot saved.",
            detail: Self.tail(result.stdout + result.stderr, max: 2000)
          )
        )
      } else {
        snapshot.sessionNumber = context.sessionNumber
        try CoverageSnapshotStore.writeCoverageSnapshot(snapshot, workspace: context.workspace)
        outcome.coverage = snapshot
        outcome.events.append(
          Event(
            kind: .coverageSnapshot,
            status: "completed",
            message: "Coverage snapshot saved.",
            metadata: [
              "overallLineCoveragePercent": snapshot.overallLineCoveragePercent.map { String($0) }
                ?? "unknown"
            ]
          )
        )
      }
    } catch {
      outcome.events.append(
        Event(
          kind: .coverageSnapshot,
          level: "warning",
          status: "failed",
          message: "Coverage collection failed (verify still passed): \(error.localizedDescription)"
        )
      )
    }

    do {
      let command = GeneratedProjectQuality.mutationTestCommand(
        forChangedFiles: context.changedFiles
      )
      outcome.mutationCommand = command
      let result = try await bash.run(
        command: command,
        workingDirectory: context.repoURL,
        timeout: timeout
      )
      outcome.mutationLog = "$ \(command)\n\n" + result.stdout + "\n" + result.stderr
      var snapshot = MutationReportParser.parse(
        output: result.stdout + "\n" + result.stderr,
        exitCode: Int(result.exitCode),
        command: command
      )
      if snapshot.tested > 0 || result.exitCode == 0 {
        snapshot.sessionNumber = context.sessionNumber
        try MutationSnapshotStore.writeMutationSnapshot(snapshot, workspace: context.workspace)
        outcome.mutation = snapshot
        outcome.events.append(
          Event(
            kind: .mutationSnapshot,
            level: snapshot.missed > 0 ? "warning" : "info",
            status: "completed",
            message:
              "Mutation snapshot saved (\(snapshot.caught) caught, \(snapshot.missed) missed).",
            metadata: [
              "command": command,
              "exitCode": "\(snapshot.exitCode)",
              "mutationScorePercent": snapshot.mutationScorePercent.map { String($0) } ?? "unknown",
            ]
          )
        )
      } else {
        outcome.events.append(
          Event(
            kind: .mutationSnapshot,
            level: "warning",
            status: "failed",
            message:
              "Mutation collection did not run (exit \(result.exitCode)); no snapshot saved.",
            detail: Self.tail(result.stdout + result.stderr, max: 2000)
          )
        )
      }
    } catch {
      outcome.events.append(
        Event(
          kind: .mutationSnapshot,
          level: "warning",
          status: "failed",
          message: "Mutation collection failed (verify still passed): \(error.localizedDescription)"
        )
      )
    }

    guard resetGuestDirt else { return outcome }

    do {
      let resetOutcome = try await SharedCompassVMGuestWorkspaceReset.reset(
        repoURL: context.repoURL,
        mode: .dirt
      )
      outcome.events.append(
        Event(
          kind: .vmResetWorkspace,
          status: "completed",
          message: "Guest workspace dirt cleaned after mutation.",
          detail: resetOutcome.detail,
          metadata: ["mode": resetOutcome.mode.rawValue]
        )
      )
    } catch {
      outcome.events.append(
        Event(
          kind: .vmResetWorkspace,
          level: "warning",
          status: "failed",
          message: "Guest workspace dirt cleanup failed: \(error.localizedDescription)"
        )
      )
    }

    return outcome
  }

  private static func tail(_ text: String, max: Int) -> String {
    guard text.count > max else { return text }
    return String(text.suffix(max))
  }
}
