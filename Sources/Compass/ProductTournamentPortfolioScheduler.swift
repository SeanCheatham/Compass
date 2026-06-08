import Foundation

enum TournamentResourceKind: String, Codable, CaseIterable, Equatable, Sendable {
  case stateWriter
  case llm
  case build
  case verify
  case scenarioSimulation
  case critic

  var label: String {
    switch self {
    case .stateWriter: return "State writer"
    case .llm: return "LLM"
    case .build: return "Build"
    case .verify: return "Verify"
    case .scenarioSimulation: return "Scenario simulation"
    case .critic: return "Critic"
    }
  }
}

struct TournamentScheduledWork: Equatable, Identifiable, Sendable {
  var id: String { stepID }

  var laneID: String
  var stepID: String
  var step: TournamentAutomationStep
  var resourceKind: TournamentResourceKind
  var additionalResourceKinds: [TournamentResourceKind]
  var priority: Int
  var canRun: Bool
  var blockedReason: String?
  var conflictKeys: [String]
  var selectionReason: String

  init(
    laneID: String,
    step: TournamentAutomationStep,
    resourceKind: TournamentResourceKind,
    additionalResourceKinds: [TournamentResourceKind] = [],
    priority: Int,
    canRun: Bool,
    blockedReason: String?,
    conflictKeys: [String],
    selectionReason: String
  ) {
    self.laneID = ProductTournamentModelText.identifier(laneID, fallback: "lane")
    self.stepID = ProductTournamentModelText.cleanedText(step.id, fallback: "step", limit: 260)
    self.step = step
    self.resourceKind = resourceKind
    self.additionalResourceKinds = additionalResourceKinds
    self.priority = max(0, priority)
    self.canRun = canRun
    self.blockedReason = ProductTournamentModelText.optionalCleanedText(
      blockedReason,
      limit: 700
    )
    self.conflictKeys = ProductTournamentModelText.cleanedList(conflictKeys, limit: 180)
    self.selectionReason = ProductTournamentModelText.cleanedText(
      selectionReason,
      fallback: "Scheduled by portfolio policy.",
      limit: 500
    )
  }

  var resourceSummary: String {
    ([resourceKind] + additionalResourceKinds).map(\.rawValue).joined(separator: "+")
  }
}

struct TournamentPortfolioSchedule: Equatable, Sendable {
  var selectedWork: [TournamentScheduledWork]
  var deferredWork: [TournamentScheduledWork]
  var maxSteps: Int
  var lanes: [ProductTournamentLaneState]

  var canRun: Bool { !selectedWork.isEmpty }

  var executableWorkCount: Int {
    selectedWork.count + deferredWork.filter(\.canRun).count
  }

  var parallelizableEvidenceWork: [TournamentScheduledWork] {
    selectedWork.filter { work in
      work.step.kind == .runPlanProof || work.step.kind == .runCohort
    }
  }

  var summary: String {
    if selectedWork.isEmpty {
      if let blocked = deferredWork.first(where: { !$0.canRun }) {
        return
          "No portfolio work selected; next blocked lane \(blocked.laneID) needs \(blocked.resourceKind.rawValue)."
      }
      return "No portfolio work selected."
    }
    let deferredExecutable = deferredWork.filter(\.canRun).count
    let deferredText =
      deferredExecutable > 0 ? "; \(deferredExecutable) executable work item(s) deferred" : ""
    return
      "\(selectedWork.count) portfolio work item(s) selected across \(Set(selectedWork.map(\.laneID)).count) lane(s)\(deferredText)."
  }

  var selectedSummary: String {
    guard !selectedWork.isEmpty else { return "No selected portfolio work." }
    return selectedWork
      .map {
        "\($0.laneID): \($0.step.queueTitle) [\($0.resourceSummary), priority \($0.priority)]"
      }
      .joined(separator: " -> ")
  }

  var deferredSummary: String {
    guard !deferredWork.isEmpty else { return "No deferred portfolio work." }
    return deferredWork.prefix(4)
      .map { work in
        let reason = work.blockedReason ?? "deferred by max step or conflict policy"
        return "\(work.laneID): \(work.step.queueTitle) [\(work.resourceSummary)] - \(reason)"
      }
      .joined(separator: " | ")
  }

  init(
    selectedWork: [TournamentScheduledWork],
    deferredWork: [TournamentScheduledWork],
    maxSteps: Int,
    lanes: [ProductTournamentLaneState]
  ) {
    self.selectedWork = selectedWork
    self.deferredWork = deferredWork
    self.maxSteps = max(1, maxSteps)
    self.lanes = lanes
  }
}

enum TournamentPortfolioScheduler {
  static func schedule(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    maxSteps: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentPortfolioSchedule {
    schedule(
      steps: TournamentAutomationPlanner.steps(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ),
      config: config,
      evidenceIndex: evidenceIndex,
      maxSteps: maxSteps
    )
  }

  static func schedule(
    steps: [TournamentAutomationStep],
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    maxSteps: Int = 3
  ) -> TournamentPortfolioSchedule {
    let limit = max(1, maxSteps)
    let lanes = ProductTournamentLaneStateBuilder.lanes(
      config: config,
      evidenceIndex: evidenceIndex,
      steps: firstStepPerExperiment(steps)
    )
    let laneByExperimentID = Dictionary(uniqueKeysWithValues: lanes.map { ($0.experimentID, $0) })
    let candidates = steps.enumerated().map { index, step in
      scheduledWork(
        for: step,
        lane: laneByExperimentID[step.experimentID],
        originalIndex: index
      )
    }
    .sorted(by: workSort)

    var selected: [TournamentScheduledWork] = []
    var deferred: [TournamentScheduledWork] = []
    var selectedMutableExperiments = Set<String>()

    for candidate in candidates {
      guard candidate.canRun else {
        deferred.append(candidate)
        continue
      }

      let isMutable = candidate.conflictKeys.contains("mutable-experiment:\(candidate.laneID)")
      if isMutable && selectedMutableExperiments.contains(candidate.laneID) {
        var conflicted = candidate
        conflicted.canRun = false
        conflicted.blockedReason =
          "Deferred because another mutable step is already selected for this lane."
        deferred.append(conflicted)
        continue
      }

      guard selected.count < limit else {
        var capped = candidate
        capped.blockedReason = "Deferred because the portfolio cycle is capped at \(limit) step(s)."
        deferred.append(capped)
        continue
      }

      selected.append(candidate)
      if isMutable {
        selectedMutableExperiments.insert(candidate.laneID)
      }
    }

    return TournamentPortfolioSchedule(
      selectedWork: selected,
      deferredWork: deferred,
      maxSteps: limit,
      lanes: lanes
    )
  }

  private static func firstStepPerExperiment(
    _ steps: [TournamentAutomationStep]
  ) -> [TournamentAutomationStep] {
    var seen = Set<String>()
    var unique: [TournamentAutomationStep] = []
    for step in steps where !seen.contains(step.experimentID) {
      unique.append(step)
      seen.insert(step.experimentID)
    }
    return unique
  }

  private static func scheduledWork(
    for step: TournamentAutomationStep,
    lane: ProductTournamentLaneState?,
    originalIndex: Int
  ) -> TournamentScheduledWork {
    let resources = resourceKinds(for: step)
    let conflictKeys = conflictKeys(for: step, lane: lane)
    let boostedPriority = step.action.priority + priorityBoost(for: step, lane: lane)
    let blockedReason = step.canExecute ? nil : step.blockedReason ?? step.detail
    return TournamentScheduledWork(
      laneID: lane?.id ?? step.experimentID,
      step: step,
      resourceKind: resources.first ?? .stateWriter,
      additionalResourceKinds: Array(resources.dropFirst()),
      priority: boostedPriority,
      canRun: step.canExecute,
      blockedReason: blockedReason,
      conflictKeys: conflictKeys + ["planner-order:\(originalIndex)"],
      selectionReason: selectionReason(for: step, lane: lane, resources: resources)
    )
  }

  private static func resourceKinds(for step: TournamentAutomationStep) -> [TournamentResourceKind] {
    switch step.kind {
    case .prepareWorktree:
      return [.stateWriter, .build]
    case .runPlanProof:
      return step.action.requiredSimulationMode == .personaModel ? [.llm] : [.scenarioSimulation]
    case .runCohort:
      if step.action.requiredSimulationMode == .personaModel {
        return [.llm, .scenarioSimulation]
      }
      return [.scenarioSimulation]
    case .applyDecision, .applyRoundTransition, .applyRevision:
      return [.stateWriter]
    case .blocked:
      return [.stateWriter]
    }
  }

  private static func conflictKeys(
    for step: TournamentAutomationStep,
    lane: ProductTournamentLaneState?
  ) -> [String] {
    var keys = ["lane:\(step.experimentID)"]
    switch step.kind {
    case .prepareWorktree, .applyDecision, .applyRoundTransition, .applyRevision:
      keys.append("mutable-experiment:\(step.experimentID)")
    case .runPlanProof, .runCohort, .blocked:
      break
    }
    if step.kind == .prepareWorktree {
      keys.append("worktree:\(lane?.worktreeID ?? step.experimentID)")
    }
    if let cohortID = step.cohortID {
      keys.append("cohort:\(cohortID)")
    }
    if let scenarioID = step.targetScenarioID {
      keys.append("scenario:\(scenarioID)")
    }
    return keys
  }

  private static func priorityBoost(
    for step: TournamentAutomationStep,
    lane: ProductTournamentLaneState?
  ) -> Int {
    var boost = 0
    if step.kind == .runCohort || step.kind == .runPlanProof {
      boost += 5
    }
    if lane?.status == .blocked {
      boost -= 20
    }
    if lane?.latestEvidenceIDs.isEmpty == true {
      boost += 2
    }
    return boost
  }

  private static func selectionReason(
    for step: TournamentAutomationStep,
    lane: ProductTournamentLaneState?,
    resources: [TournamentResourceKind]
  ) -> String {
    let resourceText = resources.map(\.rawValue).joined(separator: "+")
    let laneStatus = lane?.status.rawValue ?? "unknown"
    if step.canExecute {
      return
        "Selected candidate uses \(resourceText), lane status \(laneStatus), priority \(step.action.priority)."
    }
    let reason = step.blockedReason ?? step.detail
    return "Deferred candidate uses \(resourceText), lane status \(laneStatus): \(reason)"
  }

  private static func workSort(lhs: TournamentScheduledWork, rhs: TournamentScheduledWork) -> Bool {
    if lhs.canRun != rhs.canRun { return lhs.canRun && !rhs.canRun }
    if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
    let lhsOrder = plannerOrder(lhs)
    let rhsOrder = plannerOrder(rhs)
    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
    return lhs.stepID < rhs.stepID
  }

  private static func plannerOrder(_ work: TournamentScheduledWork) -> Int {
    work.conflictKeys.compactMap { key in
      guard key.hasPrefix("planner-order:") else { return nil }
      return Int(key.dropFirst("planner-order:".count))
    }.first ?? Int.max
  }
}
