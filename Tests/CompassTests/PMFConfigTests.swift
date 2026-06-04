import Foundation
import Testing

@testable import Compass

@MainActor
struct PMFConfigTests {
  @Test func testPMFConfigRoundTripsThroughWorkspaceStorage() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let config = makeConfig()

    try workspace.writePMFConfig(config)

    try #require(FileManager.default.fileExists(atPath: workspace.pmfConfigURL.path))
    try #require(try workspace.readPMFConfig() == config)
  }

  @Test func testMissingPMFConfigReturnsEmptyConfig() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try #require(!FileManager.default.fileExists(atPath: workspace.pmfConfigURL.path))
    try #require(try workspace.readPMFConfig() == .empty)
  }

  @Test func testMalformedPMFConfigThrows() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try "{".write(to: workspace.pmfConfigURL, atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) {
      _ = try workspace.readPMFConfig()
    }
  }

  @Test func testUnsupportedPMFConfigSchemaVersionThrowsClearError() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let payload = """
      {
        "schemaVersion": 99,
        "hypotheses": [],
        "personas": [],
        "tasks": [],
        "scenarios": []
      }
      """

    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    try payload.write(to: workspace.pmfConfigURL, atomically: true, encoding: .utf8)

    do {
      _ = try workspace.readPMFConfig()
      #expect(Bool(false), "Expected unsupported schema version.")
    } catch let error as PMFConfigError {
      try #require(error == .unsupportedSchemaVersion(99))
      try #require(error.localizedDescription.contains("99"))
    }
  }

  @Test func testSeedDefaultsCreateSpecificHypothesisPersonasTasksAndCohort() throws {
    let config = PMFConfig.seedDefaults(
      projectTitle: "LedgerLift",
      vision: "Reduce weekly finance reporting busywork for operations teams.\n",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try #require(config.schemaVersion == 1)
    try #require(config.hypotheses.count == 1)
    try #require(config.personas.count == 3)
    try #require(config.tasks.count == 2)
    try #require(config.scenarios.count == 6)
    try #require(config.cohorts.count == 1)
    try #require(config.hypotheses[0].jobToBeDone.contains("weekly finance reporting"))
    try #require(config.hypotheses[0].createdAt == 1_700_000_000)
    try #require(config.personas.allSatisfy { !$0.skepticism.isEmpty })
    try #require(config.tasks.allSatisfy { $0.maxTurns > 0 })
    try #require(config.cohorts[0].scenarioIDs == config.scenarios.map(\.id))
  }

  @Test func testProjectRefreshLoadsSeededPMFConfigWhenMissing() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)

    let project = CompassProject(repoURL: root)
    await project.initializeWorkspace()

    try #require(!project.pmfConfig.isEmpty)
    try #require(project.pmfConfig.hypotheses.count == 1)
    try #require(project.pmfConfig.personas.count == 3)
  }

  @Test func testProjectSavesAndReloadsPMFConfig() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try initGitRepo(at: root)
    let config = makeConfig()

    let project = CompassProject(repoURL: root)
    await project.initializeWorkspace()
    await project.savePMFConfig(config)

    project.pmfConfig = .empty
    await project.refresh()

    try #require(project.pmfConfig == config)
    try #require(try CompassWorkspace(repoURL: root).readPMFConfig() == config)
  }

  private func makeConfig() -> PMFConfig {
    let hypothesis = ProductHypothesis(
      id: "hypothesis-alpha",
      title: "Alpha product hypothesis",
      targetUser: "Team lead",
      jobToBeDone: "Reduce handoff drift",
      pain: "Status disappears between tools",
      promise: "Compass keeps the next step clear",
      currentAlternatives: ["Docs", "chat"],
      successCriteria: ["Clear next action"],
      pricingAssumptions: ["Pays when weekly status time drops"],
      switchingAssumptions: ["Needs low migration cost"],
      knownRisks: ["May feel like another planning surface"],
      createdAt: 100,
      updatedAt: 200
    )
    let persona = PMFPersona(
      id: "persona-lead",
      name: "Delivery lead",
      role: "Team lead",
      context: "Evaluates planning tools between delivery deadlines",
      goals: ["Keep work moving"],
      constraints: ["Limited setup time"],
      currentWorkflow: "Status doc plus chat reminders",
      skepticism: "Wants proof the tool reduces coordination work",
      decisionCriteria: ["Less follow-up", "Clear ownership"],
      technicalComfort: "moderate"
    )
    let task = PMFTask(
      id: "task-clarity",
      title: "Find the next action",
      situation: "The team is between planning and implementation",
      desiredOutcome: "Identify what to do next",
      startingContext: "Start from the app's initial state",
      successSignals: ["Finds a next action"],
      failureSignals: ["Cannot tell where to begin"],
      maxTurns: 5
    )
    let scenario = PMFScenario(
      id: "scenario-lead-clarity",
      title: "Delivery lead finds next action",
      hypothesisID: hypothesis.id,
      personaID: persona.id,
      taskID: task.id,
      seed: "alpha-seed",
      tags: ["roundtrip"]
    )
    return PMFConfig(
      hypotheses: [hypothesis],
      personas: [persona],
      tasks: [task],
      scenarios: [scenario],
      cohorts: [
        PMFScenarioCohort(
          id: "cohort-alpha",
          title: "Alpha cohort",
          scenarioIDs: [scenario.id],
          tags: ["roundtrip"]
        )
      ]
    )
  }
}
