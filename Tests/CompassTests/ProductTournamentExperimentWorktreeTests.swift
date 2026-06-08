import Foundation
import Testing

@testable import Compass

struct ProductTournamentExperimentWorktreeTests {
  @Test func preparesTournamentExperimentBranchesAndSeparateWorktrees() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try commitAll("Initialize Compass storage ignore", at: root)
    let config = makeBranchingProductTournamentConfig()
    try workspace.writeProductTournamentConfig(config)
    let initialMainSha = try await gitOutput(["rev-parse", "HEAD"], in: root)

    let first = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let second = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: "experiment-timeline"
    )

    try #require(first.branchName == "compass/exp/command-board")
    try #require(second.branchName == "compass/exp/timeline")
    try #require(first.worktreeURL != second.worktreeURL)
    try #require(FileManager.default.fileExists(atPath: first.worktreeURL.path))
    try #require(try await gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: root) == "main")
    try #require(try await gitOutput(["rev-parse", "HEAD"], in: root) == initialMainSha)

    try writeFile("experiment-only.txt", contents: "branch one\n", at: first.worktreeURL)
    try await git(["add", "experiment-only.txt"], in: first.worktreeURL)
    try await git(
      ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "Experiment one"],
      in: first.worktreeURL)
    let updatedFirst = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let saved = try workspace.readProductTournamentConfig()
    let savedFirst = try #require(
      saved.tournamentExperiments.first { $0.id == "experiment-command-board" }
    )

    try #require(updatedFirst.currentSha != initialMainSha)
    try #require(savedFirst.baseSha == initialMainSha)
    try #require(savedFirst.currentSha == updatedFirst.currentSha)
    try #require(
      !FileManager.default.fileExists(atPath: root.appending(path: "experiment-only.txt").path))
    try #require(
      !FileManager.default.fileExists(
        atPath: second.worktreeURL.appending(path: "experiment-only.txt").path
      )
    )
  }

  @Test func preparingWorktreeRefreshesCandidateStarterScenarioTargets() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try commitAll("Initialize Compass storage ignore", at: root)
    var config = makeBranchingProductTournamentConfig()
    config.scenarios = [
      ProductScenario(
        id: "scenario-candidate-starter",
        experimentID: "experiment-command-board",
        segmentID: "segment-incident-lead",
        currentWorkflowID: "workflow-chat-triage",
        alternativeID: "alternative-chat",
        title: "Candidate starter",
        task: "Try the candidate implementation.",
        successSignal: "Lead gets a clearer update.",
        targetCommitSha: nil,
        createdAt: 1
      ),
      ProductScenario(
        id: "scenario-explicit-target",
        experimentID: "experiment-command-board",
        segmentID: "segment-incident-lead",
        currentWorkflowID: "workflow-chat-triage",
        alternativeID: "alternative-chat",
        title: "Explicit target",
        task: "Try the explicit target.",
        successSignal: "Explicit target stays pinned.",
        targetCommitSha: "manual-target-sha",
        createdAt: 1
      ),
      ProductScenario(
        id: "scenario-workbench-draft",
        experimentID: "experiment-command-board",
        segmentID: "segment-incident-lead",
        currentWorkflowID: "workflow-chat-triage",
        alternativeID: "alternative-chat",
        title: "Workbench draft",
        task: "Try the manually drafted scenario.",
        successSignal: "Manual draft remains unbound.",
        targetCommitSha: nil,
        createdAt: 1
      ),
    ]
    config.scenarioCohorts = [
      ProductScenarioCohort(
        id: "cohort-candidate-starter",
        title: "Candidate starter cohort",
        experimentID: "experiment-command-board",
        scenarioIDs: ["scenario-candidate-starter", "scenario-explicit-target"],
        tags: ["discover", "candidate-implementation-track"]
      ),
      ProductScenarioCohort(
        id: "cohort-workbench-draft",
        title: "Workbench draft cohort",
        experimentID: "experiment-command-board",
        scenarioIDs: ["scenario-workbench-draft"],
        tags: ["workbench"]
      ),
    ]
    try workspace.writeProductTournamentConfig(config)
    let initialMainSha = try await gitOutput(["rev-parse", "HEAD"], in: root)

    let prepared = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let firstSaved = try workspace.readProductTournamentConfig()
    let firstStarter = try #require(
      firstSaved.scenarios.first { $0.id == "scenario-candidate-starter" }
    )
    let firstExplicit = try #require(
      firstSaved.scenarios.first { $0.id == "scenario-explicit-target" }
    )
    let firstWorkbenchDraft = try #require(
      firstSaved.scenarios.first { $0.id == "scenario-workbench-draft" }
    )

    try #require(prepared.currentSha == initialMainSha)
    try #require(firstStarter.targetCommitSha == initialMainSha)
    try #require(firstExplicit.targetCommitSha == "manual-target-sha")
    try #require(firstWorkbenchDraft.targetCommitSha == nil)

    try writeFile(
      "candidate-implementation.txt",
      contents: "branch implementation\n",
      at: prepared.worktreeURL
    )
    try await git(["add", "candidate-implementation.txt"], in: prepared.worktreeURL)
    try await git(
      [
        "-c", "user.email=t@t",
        "-c", "user.name=t",
        "commit", "-q", "-m", "Candidate implementation",
      ],
      in: prepared.worktreeURL
    )

    let refreshed = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let refreshedSaved = try workspace.readProductTournamentConfig()
    let refreshedStarter = try #require(
      refreshedSaved.scenarios.first { $0.id == "scenario-candidate-starter" }
    )
    let refreshedExplicit = try #require(
      refreshedSaved.scenarios.first { $0.id == "scenario-explicit-target" }
    )
    let refreshedWorkbenchDraft = try #require(
      refreshedSaved.scenarios.first { $0.id == "scenario-workbench-draft" }
    )

    try #require(refreshed.currentSha != initialMainSha)
    try #require(refreshedStarter.targetCommitSha == refreshed.currentSha)
    try #require(refreshedExplicit.targetCommitSha == "manual-target-sha")
    try #require(refreshedWorkbenchDraft.targetCommitSha == nil)
  }

  @Test func prepareWorktreeAutomationExecutorBindsTargetsAndUnblocksEvidenceCohort()
    async throws
  {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try commitAll("Initialize Compass storage ignore", at: root)
    var config = makeBranchingProductTournamentConfig()
    let experimentID = "experiment-command-board"
    let cohortID = "cohort-candidate-starter"
    let scenarioID = "scenario-candidate-starter"
    config.scenarios = [
      ProductScenario(
        id: scenarioID,
        experimentID: experimentID,
        segmentID: "segment-incident-lead",
        currentWorkflowID: "workflow-chat-triage",
        alternativeID: "alternative-chat",
        title: "Candidate starter",
        task: "Try the candidate implementation.",
        successSignal: "Lead gets a clearer update.",
        targetCommitSha: nil,
        createdAt: 1
      )
    ]
    config.scenarioCohorts = [
      ProductScenarioCohort(
        id: cohortID,
        title: "Candidate starter cohort",
        experimentID: experimentID,
        scenarioIDs: [scenarioID],
        tags: ["discover", "candidate-implementation-track"]
      )
    ]
    try workspace.writeProductTournamentConfig(config)

    let prepareStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: config,
        evidenceIndex: .empty
      ))

    try #require(prepareStep.kind == .prepareWorktree)

    let outcome = try await TournamentAutomationPrepareWorktreeStepExecutor.run(
      prepareStep,
      in: workspace
    )
    let saved = try workspace.readProductTournamentConfig()
    let savedExperiment = try #require(
      saved.tournamentExperiments.first { $0.id == experimentID }
    )
    let savedScenario = try #require(saved.scenarios.first { $0.id == scenarioID })
    let nextStep = try #require(
      TournamentAutomationPlanner.nextExecutableStep(
        config: saved,
        evidenceIndex: .empty
      ))
    let nextReadiness = try #require(
      ProductTournamentNextActionAdvisor.cohortRunReadiness(
        for: nextStep.action,
        experiment: savedExperiment,
        config: saved
      ))

    try #require(outcome.prepared.currentSha == savedExperiment.currentSha)
    try #require(outcome.config == saved)
    try #require(outcome.userMessage.contains("Prepared implementation worktree"))
    try #require(savedScenario.targetCommitSha == outcome.prepared.currentSha)
    try #require(nextStep.kind == .runCohort)
    try #require(nextStep.cohortID == cohortID)
    try #require(nextReadiness.enabledScenarioCount == 1)
    try #require(nextReadiness.missingTargetCommitCount == 0)
    try #require(nextReadiness.blockedReason == nil)
  }

  @Test func invalidTournamentExperimentBranchNameIsRejected() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let experiment = ProductTournamentExperiment(
      id: "experiment-bad",
      contenderPlanID: "plan-command-board",
      title: "Bad branch",
      branchName: "bad branch",
      worktreeID: "bad-worktree",
      baseSha: nil,
      currentSha: nil,
      implementationScope: "Invalid branch test",
      evidenceSummary: "No evidence.",
      decision: .notRun,
      createdAt: 1
    )

    await #expect(throws: ProductTournamentExperimentWorktreeError.invalidBranchName("bad branch"))
    {
      _ = try await ProductTournamentExperimentWorktreeManager.ensureWorktree(
        for: experiment,
        in: workspace
      )
    }
  }

  @Test func dirtyBaseWorktreeIsRejectedBeforeTournamentBranchCreation() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try writeFile("dirty.txt", contents: "uncommitted\n", at: root)
    let experiment = makeBranchingProductTournamentConfig().tournamentExperiments[0]

    do {
      _ = try await ProductTournamentExperimentWorktreeManager.ensureWorktree(
        for: experiment, in: workspace)
      #expect(Bool(false), "Expected dirty worktree rejection.")
    } catch let error as ProductTournamentExperimentWorktreeError {
      switch error {
      case .dirtyBaseWorktree(let status):
        try #require(status.contains("dirty.txt"))
      default:
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }
  }

  @Test func sharedVMGuestCatalogSeparatesExperimentEntries() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: root)
    let first = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
      forRepoURL: root,
      experimentID: "experiment-command-board",
      branchName: "compass/exp/command-board"
    )
    let firstAgain = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
      forRepoURL: root,
      experimentID: "experiment-command-board",
      branchName: "compass/exp/command-board"
    )
    let second = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
      forRepoURL: root,
      experimentID: "experiment-command-board",
      branchName: "compass/exp/timeline"
    )

    try #require(first == firstAgain)
    try #require(legacy.id != first.id)
    try #require(first.id != second.id)
    try #require(first.experimentID == "experiment-command-board")
    try #require(first.branchName == "compass/exp/command-board")
    try #require(
      SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: first)
        != SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: second)
    )
  }

  @Test func sessionRecordsRoundTripTournamentMetadata() throws {
    let record = SessionRecord(
      session: 42,
      startedAt: 1,
      endedAt: nil,
      plan: "Plan",
      verify: nil,
      beforeSha: nil,
      afterSha: nil,
      commits: [],
      status: .planning,
      notes: [],
      verifyOutput: nil,
      feedback: nil,
      tournamentExperimentID: "experiment-command-board",
      tournamentContenderPlanID: "plan-command-board",
      tournamentPainID: "pain-command-board",
      tournamentExperimentBranchName: "compass/exp/command-board",
      tournamentExperimentCommitSha: "abc123",
      tournamentExperimentBeforeSha: "before123",
      tournamentExperimentAfterSha: "after123",
      tournamentEvidenceRunIDs: ["run-one", "run-two"],
      tournamentDecision: .narrow
    )

    let data = try JSONEncoder().encode(record)
    let payload = String(decoding: data, as: UTF8.self)
    let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)

    try #require(payload.contains("\"tournamentExperimentID\""))
    try #require(payload.contains("\"tournamentContenderPlanID\""))
    try #require(!payload.contains("\"productExperimentID\""))
    try #require(!payload.contains("\"productTournamentExperimentID\""))
    try #require(!payload.contains("\"contenderPlanID\""))
    try #require(decoded.tournamentExperimentID == "experiment-command-board")
    try #require(decoded.tournamentContenderPlanID == "plan-command-board")
    try #require(decoded.tournamentPainID == "pain-command-board")
    try #require(decoded.tournamentExperimentBranchName == "compass/exp/command-board")
    try #require(decoded.tournamentExperimentCommitSha == "abc123")
    try #require(decoded.tournamentExperimentBeforeSha == "before123")
    try #require(decoded.tournamentExperimentAfterSha == "after123")
    try #require(decoded.tournamentEvidenceRunIDs == ["run-one", "run-two"])
    try #require(decoded.tournamentDecision == .narrow)
  }

  @Test func simulationTargetCapturesReadOnlyCommitIdentity() throws {
    let target = ProductTournamentExperimentSimulationTarget(
      experimentID: "experiment-command-board",
      branchName: "compass/exp/command-board",
      commitSha: "abc123",
      scenarioCohortID: "cohort-incident-lead"
    )

    let decoded = try JSONDecoder().decode(
      ProductTournamentExperimentSimulationTarget.self,
      from: try JSONEncoder().encode(target)
    )

    try #require(decoded == target)
    try #require(
      decoded.readOnlyKey
        == "experiment-command-board|compass/exp/command-board|abc123|cohort-incident-lead"
    )
  }
}

private func makeBranchingProductTournamentConfig() -> ProductTournamentConfig {
  let pain = PainHypothesis(
    id: "pain-incidents",
    title: "Incident decision drift",
    rawPain: "Incident decisions disappear across chat and tickets.",
    targetSituation: "A support lead prepares a customer update.",
    painFrequency: "Weekly",
    painSeverity: "High",
    costOfInaction: "Repeated decisions",
    status: .active,
    createdAt: 1
  )
  let contenderPlan = ProductTournamentContenderPlan(
    id: "plan-command-board",
    painID: pain.id,
    title: "Command Board",
    promise: "Keep incident decisions visible.",
    contenderPlan: "A board can beat chat.",
    targetSegmentIDs: [],
    differentiator: "Decision trail",
    whyThisCouldWin: "Faster customer updates",
    whyThisMightFail: "Chat may be enough",
    requiredProof: ["Lead drafts clearer update"],
    status: .active
  )
  let first = ProductTournamentExperiment(
    id: "experiment-command-board",
    contenderPlanID: contenderPlan.id,
    title: "Command board implementation",
    branchName: "compass/exp/command-board",
    worktreeID: "command-board-worktree",
    baseSha: nil,
    currentSha: nil,
    implementationScope: "Owner queue and update composer.",
    evidenceSummary: "No evidence.",
    decision: .notRun,
    createdAt: 1
  )
  let second = ProductTournamentExperiment(
    id: "experiment-timeline",
    contenderPlanID: contenderPlan.id,
    title: "Timeline implementation",
    branchName: "compass/exp/timeline",
    worktreeID: "timeline-worktree",
    baseSha: nil,
    currentSha: nil,
    implementationScope: "Decision timeline.",
    evidenceSummary: "No evidence.",
    decision: .notRun,
    createdAt: 1
  )
  return ProductTournamentConfig(
    rawPain: pain.rawPain,
    painHypotheses: [pain],
    userSegments: [],
    currentWorkflows: [],
    alternatives: [],
    contenderPlans: [contenderPlan],
    tournamentExperiments: [first, second],
    scenarioCohorts: [],
    decisions: []
  )
}

private func setupCommittedRepo(at root: URL) throws {
  try initGitRepo(at: root)
  try writeFile("README.md", contents: "# Experiment repo\n", at: root)
  try commitAll("Initial", at: root)
}

private func commitAll(_ message: String, at root: URL) throws {
  try runGit("git add -A", at: root)
  try runGit("git -c user.email=t@t -c user.name=t commit -q -m '\(message)'", at: root)
}

private func git(_ arguments: [String], in directory: URL) async throws {
  let result = try await ProcessRunner.runEnv(
    "git",
    arguments,
    workingDirectory: directory,
    timeout: 60
  )
  guard result.exitCode == 0 else {
    throw TestHelperError.gitCommandFailed(status: result.exitCode)
  }
}

private func gitOutput(_ arguments: [String], in directory: URL) async throws -> String {
  let result = try await ProcessRunner.runEnv(
    "git",
    arguments,
    workingDirectory: directory,
    timeout: 60
  )
  guard result.exitCode == 0 else {
    throw TestHelperError.gitCommandFailed(status: result.exitCode)
  }
  return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}
