import Foundation
import Testing

@testable import Compass

struct ProductExperimentWorktreeTests {
  @Test func preparesExperimentBranchesAndSeparateWorktrees() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try commitAll("Initialize Compass storage ignore", at: root)
    let config = makeBranchingProductizationConfig()
    try workspace.writeProductizationConfig(config)
    let initialMainSha = try await gitOutput(["rev-parse", "HEAD"], in: root)

    let first = try await workspace.prepareProductExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let second = try await workspace.prepareProductExperimentWorktree(
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
    try await git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "Experiment one"], in: first.worktreeURL)
    let updatedFirst = try await workspace.prepareProductExperimentWorktree(
      experimentID: "experiment-command-board"
    )
    let saved = try workspace.readProductizationConfig()
    let savedFirst = try #require(
      saved.experiments.first { $0.id == "experiment-command-board" }
    )

    try #require(updatedFirst.currentSha != initialMainSha)
    try #require(savedFirst.baseSha == initialMainSha)
    try #require(savedFirst.currentSha == updatedFirst.currentSha)
    try #require(!FileManager.default.fileExists(atPath: root.appending(path: "experiment-only.txt").path))
    try #require(
      !FileManager.default.fileExists(
        atPath: second.worktreeURL.appending(path: "experiment-only.txt").path
      )
    )
  }

  @Test func invalidExperimentBranchNameIsRejected() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let experiment = ProductExperiment(
      id: "experiment-bad",
      solutionID: "solution-command-board",
      title: "Bad branch",
      branchName: "bad branch",
      worktreeID: "bad-worktree",
      baseSha: nil,
      currentSha: nil,
      prototypeScope: "Invalid branch test",
      evidenceSummary: "No evidence.",
      decision: .notRun,
      createdAt: 1
    )

    await #expect(throws: ProductExperimentWorktreeError.invalidBranchName("bad branch")) {
      _ = try await ProductExperimentWorktreeManager.ensureWorktree(
        for: experiment,
        in: workspace
      )
    }
  }

  @Test func dirtyBaseWorktreeIsRejectedBeforeBranchCreation() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try setupCommittedRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try writeFile("dirty.txt", contents: "uncommitted\n", at: root)
    let experiment = makeBranchingProductizationConfig().experiments[0]

    do {
      _ = try await ProductExperimentWorktreeManager.ensureWorktree(for: experiment, in: workspace)
      #expect(Bool(false), "Expected dirty worktree rejection.")
    } catch let error as ProductExperimentWorktreeError {
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

  @Test func sessionRecordsRoundTripProductExperimentMetadata() throws {
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
      productExperimentID: "experiment-command-board",
      productSolutionID: "solution-command-board",
      productPainID: "pain-command-board",
      productExperimentBranchName: "compass/exp/command-board",
      productExperimentCommitSha: "abc123",
      productExperimentBeforeSha: "before123",
      productExperimentAfterSha: "after123",
      productEvidenceRunIDs: ["run-one", "run-two"],
      productDecision: .narrow
    )

    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)

    try #require(decoded.productExperimentID == "experiment-command-board")
    try #require(decoded.productSolutionID == "solution-command-board")
    try #require(decoded.productPainID == "pain-command-board")
    try #require(decoded.productExperimentBranchName == "compass/exp/command-board")
    try #require(decoded.productExperimentCommitSha == "abc123")
    try #require(decoded.productExperimentBeforeSha == "before123")
    try #require(decoded.productExperimentAfterSha == "after123")
    try #require(decoded.productEvidenceRunIDs == ["run-one", "run-two"])
    try #require(decoded.productDecision == .narrow)
  }

  @Test func simulationTargetCapturesReadOnlyCommitIdentity() throws {
    let target = ProductExperimentSimulationTarget(
      experimentID: "experiment-command-board",
      branchName: "compass/exp/command-board",
      commitSha: "abc123",
      scenarioCohortID: "cohort-incident-lead"
    )

    let decoded = try JSONDecoder().decode(
      ProductExperimentSimulationTarget.self,
      from: try JSONEncoder().encode(target)
    )

    try #require(decoded == target)
    try #require(
      decoded.readOnlyKey == "experiment-command-board|compass/exp/command-board|abc123|cohort-incident-lead"
    )
  }
}

private func makeBranchingProductizationConfig() -> ProductizationConfig {
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
  let solution = SolutionHypothesis(
    id: "solution-command-board",
    painID: pain.id,
    title: "Command Board",
    promise: "Keep incident decisions visible.",
    workflowBet: "A board can beat chat.",
    targetSegmentIDs: [],
    differentiator: "Decision trail",
    whyThisCouldWin: "Faster customer updates",
    whyThisMightFail: "Chat may be enough",
    requiredProof: ["Lead drafts clearer update"],
    status: .active
  )
  let first = ProductExperiment(
    id: "experiment-command-board",
    solutionID: solution.id,
    title: "Command board prototype",
    branchName: "compass/exp/command-board",
    worktreeID: "command-board-worktree",
    baseSha: nil,
    currentSha: nil,
    prototypeScope: "Owner queue and update composer.",
    evidenceSummary: "No evidence.",
    decision: .notRun,
    createdAt: 1
  )
  let second = ProductExperiment(
    id: "experiment-timeline",
    solutionID: solution.id,
    title: "Timeline prototype",
    branchName: "compass/exp/timeline",
    worktreeID: "timeline-worktree",
    baseSha: nil,
    currentSha: nil,
    prototypeScope: "Decision timeline.",
    evidenceSummary: "No evidence.",
    decision: .notRun,
    createdAt: 1
  )
  return ProductizationConfig(
    rawPain: pain.rawPain,
    painHypotheses: [pain],
    userSegments: [],
    currentWorkflows: [],
    alternatives: [],
    solutionHypotheses: [solution],
    experiments: [first, second],
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
