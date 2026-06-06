import Foundation
import Testing

@testable import Compass

struct ProductTournamentPlanEvaluationTests {
  @Test func modelFreeRoundOneEvaluatesContenderPlansWithoutGeneratedAppContract() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try workspace.writeProductTournamentConfig(config)

    let tournament = try #require(config.tournaments.first)
    let round = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let outcome = try ProductTournamentPlanEvaluator.runPlanRound(
      tournamentID: tournament.id,
      roundID: round.id,
      in: workspace,
      projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
      now: Date(timeIntervalSince1970: 2_000)
    )

    try #require(outcome.tournamentID == tournament.id)
    try #require(outcome.roundID == round.id)
    try #require(outcome.completedEvaluationCount == 3)
    try #require(outcome.skippedContenderIDs.isEmpty)
    try #require(outcome.records.allSatisfy { $0.roundID == round.id })
    try #require(outcome.records.allSatisfy { $0.status == .completed })
    try #require(
      outcome.records.allSatisfy {
        $0.promptVersions == [ProductTournamentPlanEvaluator.promptVersionID]
      })
    try #require(outcome.records.contains { $0.willingnessToPayScore ?? 0 >= 3 })
    try #require(
      outcome.records.allSatisfy { $0.scores.willingnessToPay == $0.willingnessToPayScore })

    let index = workspace.readProductTournamentEvidenceIndex()
    try #require(index.summaries.isEmpty)
    try #require(index.planEvaluationSummaries.count == 3)
    try #require(index.aggregate.planReadinessByContender.count == 2)
    try #require(
      index.aggregate.planReadinessByContender.contains {
        $0.recommendation == .advanceToFeasibility || $0.recommendation == .gatherEvidence
      })
    let digest = ProductizationPlanningDigestFormatter.promptText(
      config: try workspace.readProductTournamentConfig(),
      evidenceIndex: index
    )
    try #require(digest.contains("plan_readiness"))
    try #require(digest.contains("willingness_to_pay"))
  }

  @Test func planEvaluationRejectsBuiltProductRounds() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try workspace.writeProductTournamentConfig(config)
    let tournament = try #require(config.tournaments.first)
    let feasibilityRound = try #require(
      config.tournamentRounds.first { $0.kind == .coreTechnology })

    #expect(
      throws: ProductTournamentPlanEvaluationError.roundRequiresBuiltProduct(feasibilityRound.id)
    ) {
      _ = try ProductTournamentPlanEvaluator.runPlanRound(
        tournamentID: tournament.id,
        roundID: feasibilityRound.id,
        in: workspace
      )
    }
  }
}
