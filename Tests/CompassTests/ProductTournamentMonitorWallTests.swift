import Foundation
import Testing

@testable import Compass

struct ProductTournamentMonitorWallTests {
  @Test func evidenceRunTileUsesRunScreenshotAndTournamentContext() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance teams reconcile reports by hand.",
      now: Date(timeIntervalSince1970: 10)
    )
    config.tournamentExperiments[0].currentSha = "abc123def456"
    let experiment = config.tournamentExperiments[0]
    let contender = try #require(
      config.tournamentContenders.first { $0.experimentID == experiment.id }
    )
    let scenario = try #require(config.scenarios.first { $0.experimentID == experiment.id })
    let record = monitorEvidenceRecord(
      id: "run-one",
      config: config,
      experiment: experiment,
      contender: contender,
      scenario: scenario
    )
    _ = try workspace.writeProductTournamentEvidenceRecord(record)
    let runURL = workspace.productTournamentEvidenceStore.runsURL
      .appending(
        path: ProductTournamentEvidenceStore.safeRunID(record.id), directoryHint: .isDirectory)
    let screenshotURL = runURL.appending(path: "viewport.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)

    let wall = ProductTournamentMonitorWall.build(
      config: config,
      evidenceIndex: workspace.readProductTournamentEvidenceIndex(),
      workspace: workspace,
      sessions: []
    )
    let tile = try #require(wall.tiles.first { $0.runID == "run-one" })

    try #require(tile.source == .evidenceRun)
    try #require(tile.title == contender.title)
    try #require(tile.scenarioID == scenario.id)
    try #require(tile.imageURL?.standardizedFileURL.path == screenshotURL.standardizedFileURL.path)
    try #require(tile.isScreenshotBacked)
    try #require(tile.roundLabel == "Round 1: Plan proof")
    try #require(tile.commitLabel == "abc123de")
    try #require(wall.screenshotCount == 1)
  }

  @Test func sessionVisualProofTileLinksToTournamentSessionMetadata() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance teams reconcile reports by hand.",
      now: Date(timeIntervalSince1970: 10)
    )
    let experiment = config.tournamentExperiments[0]
    let contender = try #require(
      config.tournamentContenders.first { $0.experimentID == experiment.id }
    )
    let screenshotURL = try workspace.writeSessionAuditArtifactData(
      session: 7,
      name: "rust-desktop-visual-attempt-1.png",
      kind: "visual_screenshot",
      data: Data([0x89, 0x50, 0x4E, 0x47]),
      note: "Rust desktop screenshot captured during visual verification."
    )
    let session = SessionRecord(
      session: 7,
      startedAt: 20_000,
      endedAt: 30_000,
      plan: "Build the first inspectable screen.",
      verify: nil,
      beforeSha: nil,
      afterSha: nil,
      commits: [],
      status: .succeeded,
      notes: [],
      verifyOutput: nil,
      feedback: nil,
      tournamentExperimentID: experiment.id,
      tournamentExperimentBranchName: experiment.branchName,
      tournamentExperimentAfterSha: "fedcba987654",
      tournamentEvidenceRunIDs: ["run-one"]
    )

    let wall = ProductTournamentMonitorWall.build(
      config: config,
      evidenceIndex: .empty,
      workspace: workspace,
      sessions: [session]
    )
    let tile = try #require(wall.tiles.first { $0.source == .sessionVisualProof })

    try #require(tile.title == contender.title)
    try #require(tile.imageURL?.standardizedFileURL.path == screenshotURL.standardizedFileURL.path)
    try #require(tile.experimentID == experiment.id)
    try #require(tile.runID == "run-one")
    try #require(tile.statusLabel == "Succeeded")
    try #require(tile.commitLabel == "fedcba98")
    try #require(wall.sessionScreenshotCount == 1)
  }
}

private func monitorEvidenceRecord(
  id: String,
  config: ProductTournamentConfig,
  experiment: ProductTournamentExperiment,
  contender: ProductTournamentContender,
  scenario: ProductScenario
) -> ProductTournamentEvidenceRecord {
  ProductTournamentEvidenceRecord(
    id: id,
    experimentID: experiment.id,
    contenderPlanID: experiment.contenderPlanID,
    painID: config.painHypotheses[0].id,
    tournamentID: config.tournaments[0].id,
    roundID: config.tournamentRounds[0].id,
    contenderID: contender.id,
    branchName: experiment.branchName,
    commitSha: "abc123def456",
    scenarioID: scenario.id,
    personaID: scenario.segmentID,
    mode: .modelFree,
    status: .completed,
    startedAt: 20,
    endedAt: 30,
    traceHash: "trace-\(id)",
    completedUseProof: true,
    model: "model-free",
    scores: ProductTournamentEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 4,
      alternativeAdvantage: 3,
      switchingReadiness: 3,
      continuedUsePull: 4
    ),
    currentAlternativeComparison: "The contender beats the spreadsheet for review confidence.",
    willingnessToPayScore: 4,
    sponsorshipIntent: "The simulated user would sponsor a pilot.",
    verdict: .promising,
    summary: "The simulated user completed the workflow and wanted a pilot."
  )
}
