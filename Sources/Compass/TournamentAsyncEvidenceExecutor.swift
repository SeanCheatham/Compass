import Foundation

struct TournamentEvidenceConcurrencyLimits: Equatable, Sendable {
  var totalEvidenceTasks: Int
  var personaModelLLMTasks: Int
  var modelFreeSimulationTasks: Int

  init(
    totalEvidenceTasks: Int = 2,
    personaModelLLMTasks: Int = 1,
    modelFreeSimulationTasks: Int = 2
  ) {
    self.totalEvidenceTasks = max(1, totalEvidenceTasks)
    self.personaModelLLMTasks = max(1, personaModelLLMTasks)
    self.modelFreeSimulationTasks = max(1, modelFreeSimulationTasks)
  }
}

struct TournamentEvidenceWorkReservation: Equatable, Identifiable, Sendable {
  var id: String { taskID }

  var laneID: String
  var stepID: String
  var resourceKind: TournamentResourceKind
  var startedAt: Double
  var idempotencyKey: String
  var taskID: String

  init(
    laneID: String,
    stepID: String,
    resourceKind: TournamentResourceKind,
    startedAt: Double,
    idempotencyKey: String,
    taskID: String
  ) {
    self.laneID = ProductTournamentModelText.identifier(laneID, fallback: "lane")
    self.stepID = ProductTournamentModelText.cleanedText(stepID, fallback: "step", limit: 260)
    self.resourceKind = resourceKind
    self.startedAt = startedAt
    self.idempotencyKey = ProductTournamentModelText.cleanedText(
      idempotencyKey,
      fallback: "evidence-work",
      limit: 320
    )
    self.taskID = ProductTournamentModelText.cleanedText(taskID, fallback: "task", limit: 320)
  }
}

enum TournamentAsyncEvidenceAuditStatus: String, Codable, Equatable, Sendable {
  case started
  case completed
  case failed
  case skipped
}

struct TournamentAsyncEvidenceAudit: Equatable, Sendable {
  var laneID: String
  var stepID: String
  var status: TournamentAsyncEvidenceAuditStatus
  var message: String
  var evidenceRunIDs: [String]
  var timestamp: Double

  init(
    laneID: String,
    stepID: String,
    status: TournamentAsyncEvidenceAuditStatus,
    message: String,
    evidenceRunIDs: [String] = [],
    timestamp: Double
  ) {
    self.laneID = ProductTournamentModelText.identifier(laneID, fallback: "lane")
    self.stepID = ProductTournamentModelText.cleanedText(stepID, fallback: "step", limit: 260)
    self.status = status
    self.message = ProductTournamentModelText.cleanedText(
      message,
      fallback: status.rawValue,
      limit: 700
    )
    self.evidenceRunIDs = ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 160)
    self.timestamp = timestamp
  }
}

struct TournamentAsyncEvidenceBatchOutcome: Equatable, Sendable {
  var reservations: [TournamentEvidenceWorkReservation]
  var audits: [TournamentAsyncEvidenceAudit]
  var completedResults: [TournamentAutomationStepResult]
  var failedWork: [TournamentScheduledWork]
  var skippedWork: [TournamentScheduledWork]

  var shouldRefreshEvidenceIndex: Bool {
    !completedResults.isEmpty
  }

  var evidenceRunIDs: [String] {
    completedResults.flatMap(\.evidenceRunIDs)
  }

  var summary: String {
    [
      "\(completedResults.count) completed",
      "\(failedWork.count) failed",
      "\(skippedWork.count) skipped",
    ].joined(separator: ", ")
  }
}

actor TournamentEvidenceIdempotencyStore {
  enum State: Equatable {
    case inFlight
    case completed
  }

  private var states: [String: State] = [:]

  func reserve(_ key: String) -> Bool {
    switch states[key] {
    case .completed, .inFlight:
      return false
    case nil:
      states[key] = .inFlight
      return true
    }
  }

  func complete(_ key: String) {
    states[key] = .completed
  }

  func fail(_ key: String) {
    if states[key] == .inFlight {
      states.removeValue(forKey: key)
    }
  }
}

struct TournamentAsyncEvidenceExecutor: Sendable {
  var limits: TournamentEvidenceConcurrencyLimits
  var idempotencyStore: TournamentEvidenceIdempotencyStore

  init(
    limits: TournamentEvidenceConcurrencyLimits = TournamentEvidenceConcurrencyLimits(),
    idempotencyStore: TournamentEvidenceIdempotencyStore = TournamentEvidenceIdempotencyStore()
  ) {
    self.limits = limits
    self.idempotencyStore = idempotencyStore
  }

  func run(
    schedule: TournamentPortfolioSchedule,
    now: Date = Date(),
    execute: @escaping @Sendable (TournamentScheduledWork) async throws -> TournamentAutomationStepResult
  ) async -> TournamentAsyncEvidenceBatchOutcome {
    let selected = await selectedEvidenceWork(from: schedule)
    let startedAt = now.timeIntervalSince1970
    var skippedWork = selected.skipped
    var reservations: [TournamentEvidenceWorkReservation] = []
    var startedAudits: [TournamentAsyncEvidenceAudit] = []

    for (index, work) in selected.runnable.enumerated() {
      let key = idempotencyKey(for: work)
      let reserved = await idempotencyStore.reserve(key)
      guard reserved else {
        skippedWork.append(work)
        continue
      }
      let reservation = TournamentEvidenceWorkReservation(
        laneID: work.laneID,
        stepID: work.stepID,
        resourceKind: work.resourceKind,
        startedAt: startedAt,
        idempotencyKey: key,
        taskID: "evidence-task-\(index)-\(work.stepID)"
      )
      reservations.append(reservation)
      startedAudits.append(
        TournamentAsyncEvidenceAudit(
          laneID: work.laneID,
          stepID: work.stepID,
          status: .started,
          message: "Started \(work.resourceSummary) evidence work.",
          timestamp: startedAt
        ))
    }

    let workByKey = Dictionary(uniqueKeysWithValues: selected.runnable.map {
      (idempotencyKey(for: $0), $0)
    })
    var terminalAudits: [TournamentAsyncEvidenceAudit] = []
    var completedResults: [TournamentAutomationStepResult] = []
    var failedWork: [TournamentScheduledWork] = []

    await withTaskGroup(of: EvidenceTaskCompletion.self) { group in
      for reservation in reservations {
        guard let work = workByKey[reservation.idempotencyKey] else { continue }
        group.addTask {
          do {
            let result = try await execute(work)
            return .completed(work, reservation, result)
          } catch {
            return .failed(work, reservation, String(describing: error))
          }
        }
      }

      for await completion in group {
        switch completion {
        case .completed(let work, let reservation, let result):
          await idempotencyStore.complete(reservation.idempotencyKey)
          completedResults.append(result)
          terminalAudits.append(
            TournamentAsyncEvidenceAudit(
              laneID: work.laneID,
              stepID: work.stepID,
              status: .completed,
              message: result.message,
              evidenceRunIDs: result.evidenceRunIDs,
              timestamp: Date().timeIntervalSince1970
            ))
        case .failed(let work, let reservation, let message):
          await idempotencyStore.fail(reservation.idempotencyKey)
          failedWork.append(work)
          terminalAudits.append(
            TournamentAsyncEvidenceAudit(
              laneID: work.laneID,
              stepID: work.stepID,
              status: .failed,
              message: message,
              timestamp: Date().timeIntervalSince1970
            ))
        }
      }
    }

    let skippedAudits = skippedWork.map { work in
      TournamentAsyncEvidenceAudit(
        laneID: work.laneID,
        stepID: work.stepID,
        status: .skipped,
        message: work.blockedReason ?? "Skipped by evidence concurrency or idempotency guard.",
        timestamp: Date().timeIntervalSince1970
      )
    }

    return TournamentAsyncEvidenceBatchOutcome(
      reservations: reservations,
      audits: startedAudits + terminalAudits + skippedAudits,
      completedResults: completedResults.sorted { lhs, rhs in
        (lhs.executedStepID ?? "") < (rhs.executedStepID ?? "")
      },
      failedWork: failedWork.sorted { $0.stepID < $1.stepID },
      skippedWork: skippedWork.sorted { $0.stepID < $1.stepID }
    )
  }

  private func selectedEvidenceWork(
    from schedule: TournamentPortfolioSchedule
  ) async -> (runnable: [TournamentScheduledWork], skipped: [TournamentScheduledWork]) {
    var runnable: [TournamentScheduledWork] = []
    var skipped: [TournamentScheduledWork] = []
    var laneIDs = Set<String>()
    var personaCount = 0
    var modelFreeCount = 0

    for work in schedule.selectedWork {
      guard isSafeEvidenceWork(work) else { continue }
      guard work.canRun else {
        skipped.append(work)
        continue
      }
      guard !laneIDs.contains(work.laneID) else {
        var skippedWork = work
        skippedWork.blockedReason = "Skipped because another evidence task is already selected for this lane."
        skipped.append(skippedWork)
        continue
      }
      guard runnable.count < limits.totalEvidenceTasks else {
        var skippedWork = work
        skippedWork.blockedReason =
          "Skipped because total evidence concurrency is capped at \(limits.totalEvidenceTasks)."
        skipped.append(skippedWork)
        continue
      }

      if work.step.action.requiredSimulationMode == .personaModel {
        guard personaCount < limits.personaModelLLMTasks else {
          var skippedWork = work
          skippedWork.blockedReason =
            "Skipped because persona-model LLM concurrency is capped at \(limits.personaModelLLMTasks)."
          skipped.append(skippedWork)
          continue
        }
        personaCount += 1
      } else {
        guard modelFreeCount < limits.modelFreeSimulationTasks else {
          var skippedWork = work
          skippedWork.blockedReason =
            "Skipped because model-free simulation concurrency is capped at \(limits.modelFreeSimulationTasks)."
          skipped.append(skippedWork)
          continue
        }
        modelFreeCount += 1
      }

      laneIDs.insert(work.laneID)
      runnable.append(work)
    }
    return (runnable, skipped)
  }

  private func isSafeEvidenceWork(_ work: TournamentScheduledWork) -> Bool {
    work.step.kind == .runPlanProof || work.step.kind == .runCohort
  }

  private func idempotencyKey(for work: TournamentScheduledWork) -> String {
    [
      work.laneID,
      work.stepID,
      work.step.targetScenarioID ?? "all-scenarios",
      work.step.action.requiredSimulationMode?.rawValue ?? "default-mode",
    ].joined(separator: "::")
  }

  private enum EvidenceTaskCompletion {
    case completed(
      TournamentScheduledWork,
      TournamentEvidenceWorkReservation,
      TournamentAutomationStepResult
    )
    case failed(TournamentScheduledWork, TournamentEvidenceWorkReservation, String)
  }
}
