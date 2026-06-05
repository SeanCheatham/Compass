import Foundation
import Testing

@testable import Compass

@MainActor
struct ProductizationConfigTests {
  @Test func productizationConfigRoundTripsThroughWorkspaceStorage() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let config = makeProductizationConfig()

    try workspace.writeProductizationConfig(config)

    try #require(FileManager.default.fileExists(atPath: workspace.productizationConfigURL.path))
    try #require(FileManager.default.fileExists(atPath: workspace.productizationURL.path))
    try #require(try workspace.readProductizationConfig() == config)
  }

  @Test func missingProductizationConfigReturnsEmptyConfig() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try #require(!FileManager.default.fileExists(atPath: workspace.productizationConfigURL.path))
    try #require(try workspace.readProductizationConfig() == .empty)
  }

  @Test func malformedProductizationConfigThrows() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try "{".write(to: workspace.productizationConfigURL, atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) {
      _ = try workspace.readProductizationConfig()
    }
  }

  @Test func unsupportedProductizationSchemaVersionThrowsClearError() throws {
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
        "solutionHypotheses": [],
        "experiments": [],
        "scenarioCohorts": [],
        "decisions": []
      }
      """

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try payload.write(to: workspace.productizationConfigURL, atomically: true, encoding: .utf8)

    do {
      _ = try workspace.readProductizationConfig()
      #expect(Bool(false), "Expected unsupported schema version.")
    } catch let error as ProductizationConfigError {
      try #require(error == .unsupportedSchemaVersion(99))
      try #require(error.localizedDescription.contains("99"))
    }
  }

  @Test func seedDefaultsCreatePainSolutionsExperimentsAndCohorts() throws {
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.\n",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try #require(config.schemaVersion == 1)
    try #require(config.rawPain.contains("Finance operators"))
    try #require(config.painHypotheses.count == 1)
    try #require(config.userSegments.count == 2)
    try #require(config.currentWorkflows.count == 1)
    try #require(config.alternatives.count == 2)
    try #require(config.solutionHypotheses.count == 2)
    try #require(config.experiments.count == 2)
    try #require(config.scenarioCohorts.count == 2)
    try #require(Set(config.userSegments.map(\.id)).count == config.userSegments.count)
    try #require(Set(config.solutionHypotheses.map(\.id)).count == config.solutionHypotheses.count)
    try #require(Set(config.experiments.map(\.id)).count == config.experiments.count)
    try #require(config.painHypotheses[0].status == .active)
    try #require(config.solutionHypotheses.contains { $0.status == .active })
    try #require(config.solutionHypotheses.allSatisfy { $0.painID == config.painHypotheses[0].id })
    try #require(config.experiments.allSatisfy { !$0.branchName.isEmpty })
    try #require(config.experiments.allSatisfy { !$0.worktreeID.isEmpty })
    try #require(config.experiments[0].createdAt == 1_700_000_000)
  }

  @Test func projectRefreshLoadsSeededProductizationConfigWhenMissing() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try workspace.writeVision("Support teams lose customer promise context across tickets.")

    let project = CompassProject(repoURL: root)
    await project.refresh()

    try #require(!project.productizationConfig.isEmpty)
    try #require(project.productizationConfig.rawPain.contains("Support teams"))
    try #require(project.productizationConfig.solutionHypotheses.count == 2)
  }

  @Test func projectSavesAndReloadsProductizationConfig() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let config = makeProductizationConfig()

    let project = CompassProject(repoURL: root)
    await project.initializeWorkspace()
    await project.saveProductizationConfig(config)

    project.productizationConfig = .empty
    await project.refresh()

    try #require(project.productizationConfig == config)
    try #require(try CompassWorkspace(repoURL: root).readProductizationConfig() == config)
  }

  @Test func oldPMFConfigDoesNotSilentlyBecomeProductizationState() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let oldPMF = PMFConfig.seedDefaults(
      projectTitle: "Legacy PMF",
      vision: "Old product-first state",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try workspace.writePMFConfig(oldPMF)

    try #require(workspace.hasSupersededPMFConfigWithoutProductization)
    try #require(try workspace.readProductizationConfig() == .empty)

    let seeded = try workspace.readOrSeedProductizationConfig(
      projectTitle: "Legacy PMF",
      rawPain: "Operators lose incident decisions in chat."
    )

    try #require(seeded.rawPain.contains("incident decisions"))
    try #require(!seeded.solutionHypotheses.map(\.title).contains(oldPMF.hypotheses[0].title))
  }
}

private func makeProductizationConfig() -> ProductizationConfig {
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
  let solution = SolutionHypothesis(
    id: "solution-handoff-desk",
    painID: pain.id,
    title: "Handoff Desk",
    promise: "Preserve decisions and owners in one executable workflow.",
    workflowBet: "A Rust desktop board can keep handoff context inspectable.",
    targetSegmentIDs: [segment.id],
    differentiator: "Optimized for decision carry-forward rather than generic status.",
    whyThisCouldWin: "The lead gets a clearer next action than chat.",
    whyThisMightFail: "The board may duplicate existing docs.",
    requiredProof: ["Lead can find owner and decision faster than chat"],
    status: .active
  )
  let experiment = ProductExperiment(
    id: "experiment-handoff-desk",
    solutionID: solution.id,
    title: "Handoff Desk prototype",
    branchName: "codex/handoff-desk",
    worktreeID: "handoff-desk-worktree",
    baseSha: "abc",
    currentSha: "def",
    prototypeScope: "Decision board with owner queue.",
    scenarioCohortIDs: ["cohort-handoff"],
    evidenceSummary: "No evidence yet.",
    decision: .keepGoing,
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
  let decision = ProductDecision(
    id: "decision-handoff",
    experimentID: experiment.id,
    decision: .keepGoing,
    summary: "Continue until the owner queue is testable.",
    evidenceRunIDs: ["run-one"],
    decidedAt: 300,
    decidedBy: "Reflect"
  )
  return ProductizationConfig(
    rawPain: pain.rawPain,
    painHypotheses: [pain],
    userSegments: [segment],
    currentWorkflows: [workflow],
    alternatives: [alternative],
    solutionHypotheses: [solution],
    experiments: [experiment],
    scenarioCohorts: [cohort],
    decisions: [decision]
  )
}
