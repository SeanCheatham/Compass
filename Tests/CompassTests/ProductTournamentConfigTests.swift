import Foundation
import Testing

@testable import Compass

@MainActor
struct ProductTournamentConfigTests {
  @Test func productTournamentConfigRoundTripsThroughWorkspaceStorage() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let config = makeProductTournamentConfig()

    try workspace.writeProductTournamentConfig(config)

    try #require(FileManager.default.fileExists(atPath: workspace.productTournamentConfigURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.productTournamentURL.path))
    let payload = try String(contentsOf: workspace.productTournamentConfigURL, encoding: .utf8)
    let retiredPlanKey = "\"product" + "Hypotheses\""
    try #require(payload.contains("\"contenderPlans\""))
    try #require(!payload.contains(retiredPlanKey))
    try #require(payload.contains("\"tournamentExperiments\""))
    try #require(!payload.contains("\"experiments\""))
    try #require(try workspace.readProductTournamentConfig() == config)
  }

  @Test func missingProductTournamentConfigReturnsEmptyConfig() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try #require(!FileManager.default.fileExists(atPath: workspace.productTournamentConfigURL.path))
    try #require(try workspace.readProductTournamentConfig() == .empty)
  }

  @Test func malformedProductTournamentConfigThrows() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try "{".write(to: workspace.productTournamentConfigURL, atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) {
      _ = try workspace.readProductTournamentConfig()
    }
  }

  @Test func unsupportedProductTournamentSchemaVersionThrowsClearError() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let payload = """
      {
        "schemaVersion": 99,
        "rawPain": "Pain",
        "painHypotheses": [],
        "userSegments": [],
        "currentWorkflows": [],
        "alternatives": [],
        "contenderPlans": [],
        "tournamentExperiments": [],
        "scenarioCohorts": [],
        "decisions": []
      }
      """

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try payload.write(to: workspace.productTournamentConfigURL, atomically: true, encoding: .utf8)

    do {
      _ = try workspace.readProductTournamentConfig()
      #expect(Bool(false), "Expected unsupported schema version.")
    } catch let error as ProductTournamentConfigError {
      try #require(error == .unsupportedSchemaVersion(99))
      try #require(error.localizedDescription.contains("99"))
    }
  }

  @Test func unsupportedProductTournamentConfigKeyThrowsClearError() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let payload = """
      {
        "schemaVersion": 5,
        "rawPain": "Pain",
        "painHypotheses": [],
        "userSegments": [],
        "currentWorkflows": [],
        "alternatives": [],
        "contenderPlans": [],
        "tournamentExperiments": [],
        "tournaments": [],
        "tournamentContenders": [],
        "tournamentRounds": [],
        "scenarioCohorts": [],
        "decisions": [],
        "retiredPlanIdeas": []
      }
      """

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try payload.write(to: workspace.productTournamentConfigURL, atomically: true, encoding: .utf8)

    do {
      _ = try workspace.readProductTournamentConfig()
      #expect(Bool(false), "Expected unsupported config key.")
    } catch let error as ProductTournamentConfigError {
      try #require(error == .unsupportedKey("retiredPlanIdeas"))
      try #require(error.localizedDescription.contains("retiredPlanIdeas"))
    }
  }

  @Test func productScenarioUsesProductTournamentFallbackTitle() throws {
    let scenario = ProductScenario(
      id: "scenario-blank-title",
      experimentID: "experiment-one",
      segmentID: "segment-one",
      currentWorkflowID: "workflow-one",
      title: "   ",
      task: "Try the workflow.",
      successSignal: "Evidence shows whether the workflow helps.",
      createdAt: 10
    )

    try #require(scenario.title == "Product Tournament scenario")
  }

  @Test func recordingTournamentAutomationCycleAuditKeepsLatestBoundedHistory() throws {
    let base = ProductTournamentConfig.empty
    let first = TournamentAutomationCycleAudit(
      id: "tournament-cycle-first",
      startedAt: 10,
      endedAt: 11,
      executedStepIDs: ["step-one"],
      experimentIDs: ["experiment-one"],
      messages: ["First cycle."],
      maxSteps: 3,
      stopReason: .noExecutableStep,
      stopDetail: "Stopped first.",
      userMessage: "First."
    )
    let second = TournamentAutomationCycleAudit(
      id: "tournament-cycle-second",
      startedAt: 20,
      endedAt: 21,
      executedStepIDs: ["step-two"],
      experimentIDs: ["experiment-two"],
      messages: ["Second cycle."],
      maxSteps: 3,
      stopReason: .reachedStepLimit,
      stopDetail: "Stopped second.",
      userMessage: "Second."
    )
    let third = TournamentAutomationCycleAudit(
      id: "tournament-cycle-third",
      startedAt: 30,
      endedAt: 31,
      executedStepIDs: ["step-three"],
      experimentIDs: ["experiment-three"],
      messages: ["Third cycle."],
      maxSteps: 3,
      stopReason: .executionFailed,
      stopDetail: "Stopped third.",
      userMessage: "Third."
    )

    let next =
      base
      .recordingTournamentAutomationCycleAudit(first, limit: 2)
      .recordingTournamentAutomationCycleAudit(second, limit: 2)
      .recordingTournamentAutomationCycleAudit(third, limit: 2)

    try #require(
      next.tournamentAutomationCycleAudits.map(\.id) == ["tournament-cycle-second", "tournament-cycle-third"])
  }

  @Test func seedDefaultsCreateProductTournamentContendersRoundsAndCohorts() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.\n",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try #require(config.schemaVersion == 5)
    try #require(config.rawPain.contains("Finance operators"))
    try #require(config.painHypotheses.count == 1)
    try #require(config.userSegments.count == 2)
    try #require(config.currentWorkflows.count == 1)
    try #require(config.alternatives.count == 2)
    try #require(config.contenderPlans.count == 2)
    try #require(config.tournamentExperiments.count == 2)
    try #require(config.tournaments.count == 1)
    try #require(config.tournamentContenders.count == 2)
    try #require(config.tournamentRounds.count == 3)
    try #require(config.scenarios.count == 4)
    try #require(config.scenarioCohorts.count == 2)
    try #require(Set(config.userSegments.map(\.id)).count == config.userSegments.count)
    try #require(Set(config.contenderPlans.map(\.id)).count == config.contenderPlans.count)
    try #require(Set(config.tournamentExperiments.map(\.id)).count == config.tournamentExperiments.count)
    try #require(
      Set(config.tournamentContenders.map(\.id)).count == config.tournamentContenders.count)
    try #require(Set(config.tournamentRounds.map(\.id)).count == config.tournamentRounds.count)
    try #require(Set(config.scenarios.map(\.id)).count == config.scenarios.count)
    try #require(config.painHypotheses[0].status == .active)
    try #require(config.contenderPlans.contains { $0.status == .active })
    try #require(config.contenderPlans.allSatisfy { $0.painID == config.painHypotheses[0].id })
    try #require(config.tournamentExperiments.allSatisfy { !$0.branchName.isEmpty })
    try #require(config.tournamentExperiments.allSatisfy { !$0.worktreeID.isEmpty })
    let tournament = try #require(config.tournaments.first)
    try #require(tournament.contenderIDs == config.tournamentContenders.map(\.id))
    try #require(tournament.roundIDs == config.tournamentRounds.map(\.id))
    try #require(tournament.currentRoundID == config.tournamentRounds[0].id)
    try #require(
      config.tournamentRounds.map(\.kind) == [.productPlans, .coreTechnology, .productImplementation])
    try #require(config.tournamentRounds[0].requiresBuiltProduct == false)
    try #require(config.tournamentRounds[1].requiresBuiltProduct)
    try #require(config.tournamentRounds[2].evaluationFocus.contains("Continued-use pull"))
    try #require(config.tournamentContenders.allSatisfy { $0.status == .competing })
    try #require(config.tournamentContenders.allSatisfy { $0.experimentID != nil })
    try #require(config.scenarioCohorts.allSatisfy { $0.scenarioIDs.count == 2 })
    for experiment in config.tournamentExperiments {
      let scenarioSegmentIDs = Set(
        config.scenarios
          .filter { $0.experimentID == experiment.id }
          .map(\.segmentID)
      )
      try #require(scenarioSegmentIDs == Set(config.userSegments.map(\.id)))
    }
    try #require(config.tournamentAutomationCycleAudits.isEmpty)
    try #require(
      Set(config.scenarioCohorts.flatMap(\.scenarioIDs)).isSubset(
        of: Set(config.scenarios.map(\.id)))
    )
    try #require(config.tournamentExperiments[0].createdAt == 1_700_000_000)
  }

  @Test func seededProductTournamentReferencesExistingEntities() throws {
    let config = seededProductTournamentConfig()
    let tournamentIDs = Set(config.tournaments.map(\.id))
    let painIDs = Set(config.painHypotheses.map(\.id))
    let contenderIDs = Set(config.tournamentContenders.map(\.id))
    let planIDs = Set(config.contenderPlans.map(\.id))
    let experimentIDs = Set(config.tournamentExperiments.map(\.id))
    let roundIDs = Set(config.tournamentRounds.map(\.id))
    let scenarioIDs = Set(config.scenarios.map(\.id))
    let segmentIDs = Set(config.userSegments.map(\.id))
    let workflowIDs = Set(config.currentWorkflows.map(\.id))
    let alternativeIDs = Set(config.alternatives.map(\.id))
    let cohortsByID = Dictionary(uniqueKeysWithValues: config.scenarioCohorts.map { ($0.id, $0) })
    let scenariosByID = Dictionary(uniqueKeysWithValues: config.scenarios.map { ($0.id, $0) })

    try #require(config.tournaments.allSatisfy { painIDs.contains($0.painID) })
    try #require(config.tournamentContenders.allSatisfy { tournamentIDs.contains($0.tournamentID) })
    try #require(config.tournamentContenders.allSatisfy { planIDs.contains($0.contenderPlanID) })
    try #require(
      config.tournamentContenders.allSatisfy {
        $0.experimentID.map { experimentIDs.contains($0) } ?? true
      })
    try #require(config.tournamentRounds.allSatisfy { tournamentIDs.contains($0.tournamentID) })
    for round in config.tournamentRounds {
      for contenderID in round.contenderIDs {
        let contender = try #require(config.tournamentContenders.first { $0.id == contenderID })
        try #require(contenderIDs.contains(contenderID))
        try #require(contender.tournamentID == round.tournamentID)
      }
      try #require(round.scenarioCohortIDs.allSatisfy { cohortsByID[$0] != nil })
    }
    for cohort in config.scenarioCohorts {
      try #require(experimentIDs.contains(cohort.experimentID))
      for scenarioID in cohort.scenarioIDs {
        let scenario = try #require(scenariosByID[scenarioID])
        try #require(scenarioIDs.contains(scenarioID))
        try #require(scenario.experimentID == cohort.experimentID)
      }
    }
    for scenario in config.scenarios {
      try #require(experimentIDs.contains(scenario.experimentID))
      try #require(segmentIDs.contains(scenario.segmentID))
      try #require(workflowIDs.contains(scenario.currentWorkflowID))
      try #require(scenario.alternativeID.map { alternativeIDs.contains($0) } ?? true)
    }
    for tournament in config.tournaments {
      try #require(tournament.roundIDs.allSatisfy { roundIDs.contains($0) })
      try #require(tournament.contenderIDs.allSatisfy { contenderIDs.contains($0) })
      try #require(tournament.currentRoundID.map { roundIDs.contains($0) } ?? true)
    }
  }

  @Test func seededProductTournamentActiveStateAssumptionsAreExplicit() throws {
    let config = seededProductTournamentConfig()
    let readModel = ProductTournamentReadModel(config: config)
    let activeTournaments = readModel.activeOrDraftingTournaments()
    let tournament = try #require(activeTournaments.first)
    let rounds = readModel.rounds(in: tournament)

    try #require(activeTournaments.count == 1)
    try #require(rounds.map(\.kind) == [.productPlans, .coreTechnology, .productImplementation])
    try #require(tournament.currentRoundID == rounds[0].id)
    try #require(readModel.activeRound(in: tournament)?.id == rounds[0].id)
    try #require(rounds[0].status == .active)
    try #require(rounds[1].status != .active)
    try #require(rounds[2].status != .active)
  }

  @Test func seededProductTournamentCurrentlyHasDuplicateStatusSources() throws {
    let config = seededProductTournamentConfig()
    let tournament = try #require(config.tournaments.first)
    let roundStatuses = Dictionary(uniqueKeysWithValues: config.tournamentRounds.map {
      ($0.kind, $0.status)
    })

    try #require(config.painHypotheses.map(\.status) == [.active])
    try #require(Set(config.contenderPlans.map(\.status)) == [.active, .candidate])
    try #require(Set(config.tournamentContenders.map(\.status)) == [.competing])
    try #require(Set(config.tournamentExperiments.map(\.decision)) == [.notRun])
    try #require(tournament.status == .active)
    try #require(tournament.currentRoundID != nil)
    try #require(roundStatuses[.productPlans] == .active)
    try #require(roundStatuses[.coreTechnology] == .planned)
    try #require(roundStatuses[.productImplementation] == .planned)
  }

  @Test func productTournamentReadModelCentralizesSeededLookups() throws {
    let config = seededProductTournamentConfig()
    let readModel = ProductTournamentReadModel(config: config)
    let tournament = try #require(readModel.activeTournament())
    let round = try #require(readModel.activeRound(in: tournament))
    let node = try #require(readModel.contenderNodes(in: tournament).first)
    let experiment = try #require(node.experiment)

    try #require(round.kind == .productPlans)
    try #require(readModel.pain(for: tournament)?.id == tournament.painID)
    try #require(readModel.contenders(in: tournament).map(\.id) == tournament.contenderIDs)
    try #require(readModel.plan(for: node.contender)?.id == node.plan.id)
    try #require(readModel.experiment(for: node.contender)?.id == experiment.id)
    try #require(readModel.scenarios(for: experiment).count == 2)
    try #require(readModel.cohorts(for: experiment).count == 1)
  }

  @Test func productTournamentReadModelReturnsNilOrEmptyForMissingReferences() throws {
    var config = seededProductTournamentConfig()
    config.tournamentContenders[0].contenderPlanID = "missing-plan"
    config.tournamentContenders[0].experimentID = "missing-experiment"
    config.tournamentExperiments[0].scenarioCohortIDs = ["missing-cohort"]
    let readModel = ProductTournamentReadModel(config: config)
    let tournament = try #require(readModel.activeTournament())
    let contender = try #require(readModel.contenders(in: tournament).first)
    let experiment = config.tournamentExperiments[0]

    try #require(readModel.plan(for: contender) == nil)
    try #require(readModel.experiment(for: contender) == nil)
    try #require(readModel.contenderNodes(in: tournament).count == 1)
    try #require(readModel.cohorts(for: experiment).isEmpty)
    try #require(readModel.tournament(id: "missing") == nil)
    try #require(readModel.round(id: "missing") == nil)
  }

  @Test func projectRefreshLoadsSeededProductTournamentConfigWhenMissing() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try workspace.writeVision("Support teams lose customer promise context across tickets.")

    let project = CompassProject(repoURL: root)
    await project.refresh()

    try #require(!project.productTournamentConfig.isEmpty)
    try #require(project.productTournamentConfig.rawPain.contains("Support teams"))
    try #require(project.productTournamentConfig.contenderPlans.count == 2)
    try #require(project.productTournamentConfig.tournaments.count == 1)
    try #require(project.productTournamentConfig.tournamentRounds.map(\.kind).contains(.productPlans))
  }

  @Test func projectSavesAndReloadsProductTournamentConfig() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let config = makeProductTournamentConfig()

    let project = CompassProject(repoURL: root)
    await project.initializeWorkspace()
    await project.saveProductTournamentConfig(config)

    project.productTournamentConfig = .empty
    await project.refresh()

    try #require(project.productTournamentConfig == config)
    try #require(try CompassWorkspace(repoURL: root).readProductTournamentConfig() == config)
  }

}

private func makeProductTournamentConfig() -> ProductTournamentConfig {
  let pain = PainHypothesis(
    id: "pain-handoff-drift",
    title: "Handoff drift",
    rawPain: "Delivery teams lose decisions between planning and implementation.",
    targetSituation: "A team moves from planning into execution.",
    painFrequency: "Weekly",
    painSeverity: "High enough to cause rework",
    costOfInaction: "Teams repeat decisions and ship with stale assumptions.",
    successSignals: ["Fewer repeated decisions"],
    unknowns: ["Which handoff matters most?"],
    status: .active,
    createdAt: 100,
    updatedAt: 200
  )
  let workflow = CurrentWorkflow(
    id: "workflow-status-doc",
    painID: pain.id,
    title: "Status doc workflow",
    steps: ["Write update", "Ask for missing owner", "Chase decision"],
    tools: ["Docs", "Chat"],
    handoffs: ["PM to engineering lead"],
    failureModes: ["Decision context disappears"],
    workarounds: ["Manual checklist"],
    estimatedCost: "Two hours per week"
  )
  let alternative = Alternative(
    id: "alternative-chat",
    painID: pain.id,
    title: "Chat thread",
    kind: .manual,
    strengths: ["Already adopted"],
    weaknesses: ["Hard to search"],
    switchingCost: "Low short-term cost"
  )
  let segment = UserSegment(
    id: "segment-lead",
    painID: pain.id,
    name: "Delivery lead",
    role: "Keeps implementation moving",
    context: "Tracks decisions under deadline pressure.",
    goals: ["Find owner quickly"],
    constraints: ["Low setup tolerance"],
    currentWorkflowIDs: [workflow.id],
    alternativeIDs: [alternative.id],
    decisionCriteria: ["Less follow-up"],
    skepticism: "Will keep chat if Compass feels heavier."
  )
  let contenderPlan = ProductTournamentContenderPlan(
    id: "plan-handoff-desk",
    painID: pain.id,
    title: "Handoff Desk",
    promise: "Preserve decisions and owners in one executable workflow.",
    contenderPlan: "A Rust desktop board can keep handoff context inspectable.",
    targetSegmentIDs: [segment.id],
    differentiator: "Optimized for decision carry-forward rather than generic status.",
    whyThisCouldWin: "The lead gets a clearer next action than chat.",
    whyThisMightFail: "The board may duplicate existing docs.",
    requiredProof: ["Lead can find owner and decision faster than chat"],
    status: .active
  )
  let experiment = ProductTournamentExperiment(
    id: "experiment-handoff-desk",
    contenderPlanID: contenderPlan.id,
    title: "Handoff Desk implementation",
    branchName: "codex/handoff-desk",
    worktreeID: "handoff-desk-worktree",
    baseSha: "abc",
    currentSha: "def",
    implementationScope: "Decision board with owner queue.",
    scenarioCohortIDs: ["cohort-handoff"],
    evidenceSummary: "No evidence yet.",
    decision: .keepGoing,
    createdAt: 100,
    updatedAt: 200
  )
  let scenario = ProductScenario(
    id: "scenario-lead",
    experimentID: experiment.id,
    segmentID: segment.id,
    currentWorkflowID: workflow.id,
    alternativeID: alternative.id,
    title: "Delivery lead handoff scenario",
    task: "Complete the owner handoff and decide whether the board reduces repeated follow-up.",
    successSignal: "The lead can find the owner and decision faster than chat.",
    targetCommitSha: experiment.currentSha,
    maxTurns: 6,
    appCommandTimeoutSeconds: 90,
    enabled: true,
    createdAt: 100,
    updatedAt: 200
  )
  let cohort = ProductScenarioCohort(
    id: "cohort-handoff",
    title: "Handoff cohort",
    experimentID: experiment.id,
    scenarioIDs: ["scenario-lead"],
    tags: ["focused"]
  )
  let decision = ProductTournamentDecision(
    id: "decision-handoff",
    experimentID: experiment.id,
    decision: .keepGoing,
    summary: "Continue until the owner queue is testable.",
    evidenceRunIDs: ["run-one"],
    decidedAt: 300,
    decidedBy: "Reflect"
  )
  let audit = TournamentAutomationCycleAudit(
    id: "tournament-cycle-handoff",
    startedAt: 400,
    endedAt: 405,
    executedStepIDs: ["experiment-handoff-desk:run_cohort:cohort-handoff"],
    experimentIDs: [experiment.id],
    messages: ["Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped."],
    maxSteps: 3,
    evidenceTensionSummaries: [
      "experiment-handoff-desk: resolve split tournament evidence; target Delivery lead"
    ],
    stopReason: .noExecutableStep,
    stopDetail: "Stopped because no executable tournament automation step remains.",
    userMessage:
      "Tournament automation cycle ran 1 step(s). Model-free cohort ran 1 scenario(s): 1 completed, 0 needing review, 0 skipped. Stopped because no executable tournament automation step remains."
  )
  return ProductTournamentConfig(
    rawPain: pain.rawPain,
    painHypotheses: [pain],
    userSegments: [segment],
    currentWorkflows: [workflow],
    alternatives: [alternative],
    contenderPlans: [contenderPlan],
    tournamentExperiments: [experiment],
    scenarios: [scenario],
    scenarioCohorts: [cohort],
    decisions: [decision],
    tournamentAutomationCycleAudits: [audit]
  )
}

private func seededProductTournamentConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
}
