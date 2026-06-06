import Foundation
import Testing

@testable import Compass

struct ProductTournamentGitRolloutTests {
  @Test func fastForwardPromotionUpdatesAcceptedBranchAndDecisionTrail() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await setupRolloutRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try await commitCompassIgnoreIfNeeded(at: root)
    let baseSha = try await gitOutput(["rev-parse", "HEAD"], in: root)
    let branchName = "compass/exp/fast-forward"
    let experimentSha = try await createExperimentBranch(
      branchName,
      fileName: "implementation.txt",
      contents: "experiment\n",
      at: root
    )
    let config = makeGitRolloutConfig(
      experimentID: "experiment-fast-forward",
      branchName: branchName,
      baseSha: baseSha,
      currentSha: experimentSha,
      decision: .promote
    )
    try workspace.writeProductTournamentConfig(config)
    try workspace.writeProductTournamentEvidenceRecord(makeGitRolloutEvidence(config: config))

    let result = try await workspace.promoteProductTournamentExperiment(
      experimentID: "experiment-fast-forward",
      acceptedBranchName: "main",
      now: Date(timeIntervalSince1970: 100)
    )
    let promoted = try workspace.readProductTournamentConfig()
    let experiment = try #require(
      promoted.tournamentExperiments.first { $0.id == "experiment-fast-forward" }
    )
    let contenderPlan = try #require(promoted.contenderPlans.first)
    let decision = try #require(promoted.decisions.last)

    try #require(result.preview.kind == .fastForwardPromotion)
    try #require(try await gitOutput(["rev-parse", "main"], in: root) == experimentSha)
    try #require(try await gitOutput(["rev-parse", branchName], in: root) == experimentSha)
    try #require(experiment.decision == .promoted)
    try #require(contenderPlan.status == .promoted)
    try #require(decision.decision == .promoted)
    try #require(decision.beforeSha == baseSha)
    try #require(decision.afterSha == experimentSha)
    try #require(decision.evidenceRunIDs == ["rollout-run"])
    try #require(decision.decidedBy == "Product Tournament Workbench")
  }

  @Test func mergePromotionRecordsMergeCommitWhenAcceptedBranchDiverged() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await setupRolloutRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try await commitCompassIgnoreIfNeeded(at: root)
    let baseSha = try await gitOutput(["rev-parse", "HEAD"], in: root)
    let branchName = "compass/exp/merge"
    let experimentSha = try await createExperimentBranch(
      branchName,
      fileName: "experiment.txt",
      contents: "experiment\n",
      at: root
    )
    try await git(["checkout", "main"], in: root)
    try writeFile("main.txt", contents: "accepted branch work\n", at: root)
    try await git(["add", "main.txt"], in: root)
    try await git(["commit", "-q", "-m", "Main work"], in: root)
    let acceptedBeforeSha = try await gitOutput(["rev-parse", "main"], in: root)
    let config = makeGitRolloutConfig(
      experimentID: "experiment-merge",
      branchName: branchName,
      baseSha: baseSha,
      currentSha: experimentSha,
      decision: .promote
    )
    try workspace.writeProductTournamentConfig(config)
    try workspace.writeProductTournamentEvidenceRecord(makeGitRolloutEvidence(config: config))

    let result = try await workspace.promoteProductTournamentExperiment(
      experimentID: "experiment-merge",
      acceptedBranchName: "main",
      now: Date(timeIntervalSince1970: 110)
    )
    let mergeSha = try await gitOutput(["rev-parse", "main"], in: root)
    let parents = try await gitOutput(["rev-list", "--parents", "-n", "1", "main"], in: root)
      .split(separator: " ")
    let decision = try #require(try workspace.readProductTournamentConfig().decisions.last)

    try #require(result.preview.kind == .mergePromotion)
    try #require(mergeSha != acceptedBeforeSha)
    try #require(mergeSha != experimentSha)
    try #require(parents.count == 3)
    try #require(decision.beforeSha == acceptedBeforeSha)
    try #require(decision.afterSha == mergeSha)
    try #require(decision.decidedBy == "Product Tournament Workbench")
  }

  @Test func promotionRejectsStaleExperimentShaAndLeavesAcceptedBranchUntouched() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await setupRolloutRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try await commitCompassIgnoreIfNeeded(at: root)
    let baseSha = try await gitOutput(["rev-parse", "HEAD"], in: root)
    let branchName = "compass/exp/stale"
    let recordedExperimentSha = try await createExperimentBranch(
      branchName,
      fileName: "implementation.txt",
      contents: "recorded\n",
      at: root
    )
    try await git(["checkout", branchName], in: root)
    try writeFile("newer.txt", contents: "newer\n", at: root)
    try await git(["add", "newer.txt"], in: root)
    try await git(["commit", "-q", "-m", "Newer experiment work"], in: root)
    let actualExperimentSha = try await gitOutput(["rev-parse", branchName], in: root)
    try await git(["checkout", "main"], in: root)
    let config = makeGitRolloutConfig(
      experimentID: "experiment-stale",
      branchName: branchName,
      baseSha: baseSha,
      currentSha: recordedExperimentSha,
      decision: .promote
    )
    try workspace.writeProductTournamentConfig(config)

    do {
      _ = try await workspace.promoteProductTournamentExperiment(
        experimentID: "experiment-stale",
        acceptedBranchName: "main"
      )
      Issue.record("Expected stale experiment sha rejection.")
    } catch let error as ProductTournamentExperimentGitRolloutError {
      try #require(
        error == .staleExperimentSha(
          branchName: branchName,
          expected: recordedExperimentSha,
          actual: actualExperimentSha
        )
      )
    }

    try #require(try await gitOutput(["rev-parse", "main"], in: root) == baseSha)
    try #require(try workspace.readProductTournamentConfig().tournamentExperiments[0].decision == .promote)
  }

  @Test func archiveCreatesArchiveRefAndPreservesExperimentLineage() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await setupRolloutRepo(at: root)
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try await commitCompassIgnoreIfNeeded(at: root)
    let baseSha = try await gitOutput(["rev-parse", "HEAD"], in: root)
    let branchName = "compass/exp/archive"
    let experimentSha = try await createExperimentBranch(
      branchName,
      fileName: "archive.txt",
      contents: "archive me\n",
      at: root
    )
    let config = makeGitRolloutConfig(
      experimentID: "experiment-archive",
      branchName: branchName,
      baseSha: baseSha,
      currentSha: experimentSha,
      decision: .kill
    )
    try workspace.writeProductTournamentConfig(config)
    try workspace.writeProductTournamentEvidenceRecord(makeGitRolloutEvidence(config: config))
    let worktreeURL = workspace.productTournamentExperimentWorktreeURL(experimentID: "experiment-archive")
    try FileManager.default.createDirectory(
      at: worktreeURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try await git(["worktree", "add", worktreeURL.path, branchName], in: root)

    let result = try await workspace.archiveProductTournamentExperiment(
      experimentID: "experiment-archive",
      acceptedBranchName: "main",
      now: Date(timeIntervalSince1970: 120)
    )
    let saved = try workspace.readProductTournamentConfig()
    let experiment = try #require(saved.tournamentExperiments.first { $0.id == "experiment-archive" })
    let contenderPlan = try #require(saved.contenderPlans.first)
    let decision = try #require(saved.decisions.last)
    let archiveBranch = try #require(result.archiveBranchName)

    try #require(archiveBranch == "compass/archive/rollout-plan")
    try #require(try await gitOutput(["rev-parse", archiveBranch], in: root) == experimentSha)
    try #require(try await gitOutput(["rev-parse", branchName], in: root) == experimentSha)
    try #require(FileManager.default.fileExists(atPath: worktreeURL.path))
    try #require(try await gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: worktreeURL) == branchName)
    try #require(experiment.decision == .archived)
    try #require(experiment.worktreeID == "experiment-archive-worktree")
    try #require(contenderPlan.status == .parked)
    try #require(decision.decision == .archived)
    try #require(decision.branchName == branchName)
    try #require(decision.beforeSha == experimentSha)
    try #require(decision.afterSha == experimentSha)
    try #require(decision.evidenceRunIDs == ["rollout-run"])
    try #require(decision.decidedBy == "Product Tournament Workbench")
  }
}

private func setupRolloutRepo(at root: URL) async throws -> String {
  try initGitRepo(at: root)
  try await git(["config", "user.email", "t@t"], in: root)
  try await git(["config", "user.name", "t"], in: root)
  try writeFile("README.md", contents: "# Rollout repo\n", at: root)
  try await git(["add", "README.md"], in: root)
  try await git(["commit", "-q", "-m", "Initial"], in: root)
  return try await gitOutput(["rev-parse", "HEAD"], in: root)
}

private func commitCompassIgnoreIfNeeded(at root: URL) async throws {
  let status = try await gitOutput(["status", "--porcelain"], in: root)
  guard !status.isEmpty else { return }
  try await git(["add", ".gitignore"], in: root)
  try await git(["commit", "-q", "-m", "Ignore Compass storage"], in: root)
}

private func createExperimentBranch(
  _ branchName: String,
  fileName: String,
  contents: String,
  at root: URL
) async throws -> String {
  try await git(["checkout", "-b", branchName], in: root)
  try writeFile(fileName, contents: contents, at: root)
  try await git(["add", fileName], in: root)
  try await git(["commit", "-q", "-m", "Experiment work"], in: root)
  let sha = try await gitOutput(["rev-parse", "HEAD"], in: root)
  try await git(["checkout", "main"], in: root)
  return sha
}

private func makeGitRolloutConfig(
  experimentID: String,
  branchName: String,
  baseSha: String,
  currentSha: String,
  decision: ProductTournamentExperimentDecision
) -> ProductTournamentConfig {
  let pain = PainHypothesis(
    id: "pain-rollout",
    title: "Rollout pain",
    rawPain: "Users need reliable tournament experiment rollout.",
    targetSituation: "A product contender is ready for a decision.",
    painFrequency: "Weekly",
    painSeverity: "High",
    costOfInaction: "Experiment lineage gets lost.",
    status: .active,
    createdAt: 1
  )
  let contenderPlan = ProductTournamentContenderPlan(
    id: "plan-rollout",
    painID: pain.id,
    title: "Rollout Plan",
    promise: "Promote and archive tournament experiments deliberately.",
    contenderPlan: "Git-backed rollout preserves evidence and lineage.",
    targetSegmentIDs: [],
    differentiator: "Evidence-linked branch decisions.",
    whyThisCouldWin: "Users can trust the accepted branch history.",
    whyThisMightFail: "Branch state may go stale.",
    requiredProof: ["Promotion records before and after commits"],
    status: .active
  )
  let experiment = ProductTournamentExperiment(
    id: experimentID,
    contenderPlanID: contenderPlan.id,
    title: "Rollout experiment",
    branchName: branchName,
    worktreeID: "\(experimentID)-worktree",
    baseSha: baseSha,
    currentSha: currentSha,
    implementationScope: "Rollout branch mechanics.",
    evidenceSummary: "Ready for git rollout.",
    decision: decision,
    createdAt: 1
  )
  return ProductTournamentConfig(
    rawPain: pain.rawPain,
    painHypotheses: [pain],
    userSegments: [],
    currentWorkflows: [],
    alternatives: [],
    contenderPlans: [contenderPlan],
    tournamentExperiments: [experiment],
    scenarioCohorts: [],
    decisions: []
  )
}

private func makeGitRolloutEvidence(config: ProductTournamentConfig) -> ProductTournamentEvidenceRecord {
  ProductTournamentEvidenceRecord(
    id: "rollout-run",
    experimentID: config.tournamentExperiments[0].id,
    contenderPlanID: config.contenderPlans[0].id,
    painID: config.painHypotheses[0].id,
    branchName: config.tournamentExperiments[0].branchName,
    commitSha: config.tournamentExperiments[0].currentSha ?? "unknown",
    scenarioID: "scenario-rollout",
    personaID: "segment-rollout",
    mode: .modelFree,
    status: .completed,
    startedAt: 1,
    endedAt: 2,
    traceHash: "trace-rollout",
    model: "model-free",
    scores: ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 4,
      alternativeAdvantage: 4,
      switchingReadiness: 4,
      continuedUsePull: 4
    ),
    currentAlternativeComparison: "Better than manual branch tracking.",
    verdict: .strongPull,
    summary: "Evidence supports git rollout."
  )
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
