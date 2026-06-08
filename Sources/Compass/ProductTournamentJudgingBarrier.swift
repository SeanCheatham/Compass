import Foundation

enum ProductTournamentJudgingBarrierType: String, Codable, CaseIterable, Equatable, Sendable {
  case evidenceBatchComplete
  case roundReadyForJudging
  case decisionReady
  case winnerSelectionReady
}

struct ProductTournamentJudgingBarrier: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var type: ProductTournamentJudgingBarrierType
  var comparedLaneIDs: [String]
  var evidenceCutoffTimestamp: Double
  var includedEvidenceRunIDs: [String]
  var deferredLaneIDs: [String]
  var blockedLaneIDs: [String]
  var fairnessReason: String

  init(
    id: String,
    type: ProductTournamentJudgingBarrierType,
    comparedLaneIDs: [String],
    evidenceCutoffTimestamp: Double,
    includedEvidenceRunIDs: [String],
    deferredLaneIDs: [String] = [],
    blockedLaneIDs: [String] = [],
    fairnessReason: String
  ) {
    self.id = ProductTournamentModelText.cleanedText(id, fallback: "barrier", limit: 260)
    self.type = type
    self.comparedLaneIDs = ProductTournamentModelText.cleanedList(comparedLaneIDs, limit: 160)
    self.evidenceCutoffTimestamp = evidenceCutoffTimestamp
    self.includedEvidenceRunIDs = ProductTournamentModelText.cleanedList(
      includedEvidenceRunIDs,
      limit: 180
    )
    self.deferredLaneIDs = ProductTournamentModelText.cleanedList(deferredLaneIDs, limit: 160)
    self.blockedLaneIDs = ProductTournamentModelText.cleanedList(blockedLaneIDs, limit: 160)
    self.fairnessReason = ProductTournamentModelText.cleanedText(
      fairnessReason,
      fallback: "Judging waits for comparable lane evidence.",
      limit: 700
    )
  }

  var summary: String {
    let deferred = deferredLaneIDs.isEmpty ? "none" : deferredLaneIDs.joined(separator: ",")
    let blocked = blockedLaneIDs.isEmpty ? "none" : blockedLaneIDs.joined(separator: ",")
    return
      "\(type.rawValue): compare \(comparedLaneIDs.joined(separator: ",")); deferred \(deferred); blocked \(blocked); cutoff \(evidenceCutoffTimestamp). \(fairnessReason)"
  }
}

struct ProductTournamentDecisionBarrierAudit: Codable, Equatable, Sendable {
  var barrierID: String
  var comparedLaneIDs: [String]
  var evidenceCutoffTimestamp: Double
  var includedEvidenceRunIDs: [String]
  var deferredLaneIDs: [String]
  var blockedLaneIDs: [String]
  var fairnessReason: String

  init(barrier: ProductTournamentJudgingBarrier) {
    self.barrierID = barrier.id
    self.comparedLaneIDs = barrier.comparedLaneIDs
    self.evidenceCutoffTimestamp = barrier.evidenceCutoffTimestamp
    self.includedEvidenceRunIDs = barrier.includedEvidenceRunIDs
    self.deferredLaneIDs = barrier.deferredLaneIDs
    self.blockedLaneIDs = barrier.blockedLaneIDs
    self.fairnessReason = barrier.fairnessReason
  }
}

enum ProductTournamentJudgingBarrierBuilder {
  static func barriers(
    lanes: [ProductTournamentLaneState],
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentJudgingBarrier] {
    let active = lanes.filter { $0.status != .finished }
    let ready = active.filter { $0.status == .readyForDecision }
    guard !ready.isEmpty else {
      return evidenceIndex.updatedAt <= 0
        ? []
        : [
          ProductTournamentJudgingBarrier(
            id: "evidence-batch-complete:\(Int(evidenceIndex.updatedAt))",
            type: .evidenceBatchComplete,
            comparedLaneIDs: [],
            evidenceCutoffTimestamp: evidenceIndex.updatedAt,
            includedEvidenceRunIDs: evidenceRunIDs(from: lanes),
            fairnessReason: "Evidence batch completed; no lane is ready for a state-changing decision yet."
          )
        ]
    }

    let blocked = active.filter { $0.status == .blocked }
    let awaiting = active.filter { lane in
      lane.status != .readyForDecision && lane.status != .blocked
    }
    let type: ProductTournamentJudgingBarrierType =
      awaiting.isEmpty ? .decisionReady : .roundReadyForJudging
    let reason =
      awaiting.isEmpty
      ? "All non-blocked active lanes have reached the same decision barrier."
      : "Ready lanes wait for peers to gather comparable proof before judging."
    let readyKey = ready.map(\.id).joined(separator: "+")
    return [
      ProductTournamentJudgingBarrier(
        id: "\(type.rawValue):\(readyKey):\(Int(evidenceIndex.updatedAt))",
        type: type,
        comparedLaneIDs: ready.map(\.id),
        evidenceCutoffTimestamp: evidenceIndex.updatedAt,
        includedEvidenceRunIDs: evidenceRunIDs(from: ready),
        deferredLaneIDs: awaiting.map(\.id),
        blockedLaneIDs: blocked.map(\.id),
        fairnessReason: reason
      )
    ]
  }

  private static func evidenceRunIDs(from lanes: [ProductTournamentLaneState]) -> [String] {
    var seen = Set<String>()
    var ids: [String] = []
    for id in lanes.flatMap(\.latestEvidenceIDs) where !seen.contains(id) {
      ids.append(id)
      seen.insert(id)
    }
    return ids
  }
}

enum ProductTournamentLaneBarrierAnnotator {
  static func lanes(
    _ lanes: [ProductTournamentLaneState],
    barriers: [ProductTournamentJudgingBarrier]
  ) -> [ProductTournamentLaneState] {
    let awaitingReadyLaneIDs = Set(
      barriers
        .filter { !$0.deferredLaneIDs.isEmpty }
        .flatMap(\.comparedLaneIDs)
    )
    guard !awaitingReadyLaneIDs.isEmpty else { return lanes }
    return lanes.map { lane in
      guard awaitingReadyLaneIDs.contains(lane.id), lane.status == .readyForDecision else {
        return lane
      }
      var copy = lane
      copy.status = .awaitingPeers
      copy.blockedReason = "Awaiting peer lanes before a fair judging pass."
      return copy
    }
  }
}

enum TournamentStateWriterOperationKind: String, Codable, CaseIterable, Equatable, Sendable {
  case applyDecision
  case applyRoundTransition
  case applyRevision
  case landBranchChanges
  case writeTournamentConfig
}

struct TournamentStateWriterOperation: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var kind: TournamentStateWriterOperationKind
  var laneID: String?
  var reason: String
  var enqueuedAt: Double

  init(
    id: String,
    kind: TournamentStateWriterOperationKind,
    laneID: String? = nil,
    reason: String,
    enqueuedAt: Double = Date().timeIntervalSince1970
  ) {
    self.id = ProductTournamentModelText.cleanedText(id, fallback: "state-writer-op", limit: 260)
    self.kind = kind
    self.laneID = ProductTournamentModelText.optionalIdentifier(laneID, fallback: "lane")
    self.reason = ProductTournamentModelText.cleanedText(
      reason,
      fallback: "Serialize tournament state mutation.",
      limit: 500
    )
    self.enqueuedAt = enqueuedAt
  }
}

struct TournamentStateWriterOperationRecord: Equatable, Sendable {
  var operation: TournamentStateWriterOperation
  var startedAt: Double
  var endedAt: Double
  var message: String
}

actor TournamentStateWriterQueue {
  private var pending: [TournamentStateWriterOperation] = []

  func enqueue(_ operation: TournamentStateWriterOperation) {
    pending.append(operation)
    pending.sort { lhs, rhs in
      if lhs.enqueuedAt == rhs.enqueuedAt { return lhs.id < rhs.id }
      return lhs.enqueuedAt < rhs.enqueuedAt
    }
  }

  func drain(
    now: @Sendable () -> Date = { Date() },
    execute: @Sendable (TournamentStateWriterOperation) async throws -> String
  ) async rethrows -> [TournamentStateWriterOperationRecord] {
    var records: [TournamentStateWriterOperationRecord] = []
    while !pending.isEmpty {
      let operation = pending.removeFirst()
      let started = now().timeIntervalSince1970
      let message = try await execute(operation)
      let ended = now().timeIntervalSince1970
      records.append(
        TournamentStateWriterOperationRecord(
          operation: operation,
          startedAt: started,
          endedAt: ended,
          message: ProductTournamentModelText.cleanedText(
            message,
            fallback: "State writer operation completed.",
            limit: 700
          )
        ))
    }
    return records
  }
}
