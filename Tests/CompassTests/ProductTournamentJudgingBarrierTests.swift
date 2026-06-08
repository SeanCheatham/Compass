import Foundation
import Testing

@testable import Compass

struct ProductTournamentJudgingBarrierTests {
  @Test func readyLaneWaitsAtRoundBarrierForComparablePeers() throws {
    let ready = makeBarrierLane(
      id: "lane-ready",
      status: .readyForDecision,
      evidenceIDs: ["run-ready"]
    )
    let peer = makeBarrierLane(
      id: "lane-peer",
      status: .runningEvidence,
      evidenceIDs: ["run-peer"]
    )
    let index = ProductTournamentEvidenceIndex(updatedAt: 123)

    let barrier = try #require(
      ProductTournamentJudgingBarrierBuilder.barriers(
        lanes: [ready, peer],
        evidenceIndex: index
      ).first)
    let annotated = ProductTournamentLaneBarrierAnnotator.lanes(
      [ready, peer],
      barriers: [barrier]
    )

    try #require(barrier.type == .roundReadyForJudging)
    try #require(barrier.comparedLaneIDs == ["lane-ready"])
    try #require(barrier.deferredLaneIDs == ["lane-peer"])
    try #require(barrier.includedEvidenceRunIDs == ["run-ready"])
    try #require(barrier.fairnessReason.contains("wait"))
    try #require(annotated[0].status == .awaitingPeers)
    try #require(annotated[0].blockedReason?.contains("Awaiting peer") == true)
  }

  @Test func allReadyLanesProduceDecisionBarrierAndAuditFields() throws {
    let first = makeBarrierLane(id: "lane-a", status: .readyForDecision, evidenceIDs: ["run-a"])
    let second = makeBarrierLane(id: "lane-b", status: .readyForDecision, evidenceIDs: ["run-b"])
    let blocked = makeBarrierLane(id: "lane-c", status: .blocked, evidenceIDs: ["run-c"])
    let index = ProductTournamentEvidenceIndex(updatedAt: 456)

    let barrier = try #require(
      ProductTournamentJudgingBarrierBuilder.barriers(
        lanes: [first, second, blocked],
        evidenceIndex: index
      ).first)
    let audit = ProductTournamentDecisionBarrierAudit(barrier: barrier)

    try #require(barrier.type == .decisionReady)
    try #require(barrier.comparedLaneIDs == ["lane-a", "lane-b"])
    try #require(barrier.deferredLaneIDs.isEmpty)
    try #require(barrier.blockedLaneIDs == ["lane-c"])
    try #require(audit.evidenceCutoffTimestamp == 456)
    try #require(audit.includedEvidenceRunIDs == ["run-a", "run-b"])
    try #require(audit.fairnessReason.contains("same decision barrier"))
  }

  @Test func evidenceBatchBarrierRecordsCutoffWhenNoLaneIsDecisionReady() throws {
    let lane = makeBarrierLane(id: "lane-a", status: .runningEvidence, evidenceIDs: ["run-a"])
    let index = ProductTournamentEvidenceIndex(updatedAt: 789)

    let barrier = try #require(
      ProductTournamentJudgingBarrierBuilder.barriers(
        lanes: [lane],
        evidenceIndex: index
      ).first)

    try #require(barrier.type == .evidenceBatchComplete)
    try #require(barrier.evidenceCutoffTimestamp == 789)
    try #require(barrier.fairnessReason.contains("no lane is ready"))
  }

  @Test func stateWriterQueueDrainsOperationsSeriallyInEnqueueOrder() async throws {
    let queue = TournamentStateWriterQueue()
    await queue.enqueue(
      TournamentStateWriterOperation(
        id: "op-b",
        kind: .applyRevision,
        laneID: "lane-b",
        reason: "Second",
        enqueuedAt: 2
      ))
    await queue.enqueue(
      TournamentStateWriterOperation(
        id: "op-a",
        kind: .applyDecision,
        laneID: "lane-a",
        reason: "First",
        enqueuedAt: 1
      ))
    let monitor = StateWriterSerialMonitor()

    let records = try await queue.drain {
      Date(timeIntervalSince1970: 10)
    } execute: { operation in
      await monitor.started()
      try await Task.sleep(nanoseconds: 5_000_000)
      await monitor.ended()
      return "Completed \(operation.id)"
    }

    try #require(records.map { $0.operation.id } == ["op-a", "op-b"])
    try #require(await monitor.maxActiveCount() == 1)
    try #require(records.map(\.message) == ["Completed op-a", "Completed op-b"])
  }

  @Test func planningDigestIncludesJudgingBarrierSummary() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
      now: Date(timeIntervalSince1970: 10)
    )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: ProductTournamentEvidenceIndex(updatedAt: 321)
    )

    try #require(digest.contains("Tournament judging barriers:"))
    try #require(digest.contains("evidenceBatchComplete") || digest.contains("evidence_batch"))
    try #require(digest.contains("cutoff"))
  }
}

private actor StateWriterSerialMonitor {
  private var active = 0
  private var maxActive = 0

  func started() {
    active += 1
    maxActive = max(maxActive, active)
  }

  func ended() {
    active -= 1
  }

  func maxActiveCount() -> Int {
    maxActive
  }
}

private func makeBarrierLane(
  id: String,
  status: ProductTournamentLaneStatus,
  evidenceIDs: [String]
) -> ProductTournamentLaneState {
  ProductTournamentLaneState(
    experimentID: id,
    experimentTitle: id,
    contenderID: "\(id)-contender",
    contenderTitle: "\(id) contender",
    branchName: "codex/\(id)",
    worktreeID: "\(id)-worktree",
    currentCommit: "head-\(id)",
    baseCommit: "base-\(id)",
    status: status,
    activeStepID: "\(id)-step",
    blockedReason: status == .blocked ? "Blocked for test." : nil,
    latestEvidenceIDs: evidenceIDs,
    proofDebtSummary: "proof complete",
    updatedAt: 1
  )
}
