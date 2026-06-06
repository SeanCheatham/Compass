import Foundation
import Testing

@testable import Compass

struct ProductTournamentPlanEvaluationTests {
  @Test func modelFreeRoundOneEvaluatesContenderPlansWithoutGeneratedAppContract() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductTournamentConfig.seedDefaults(
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
    try #require(outcome.completedEvaluationCount == 4)
    try #require(outcome.skippedContenderIDs.isEmpty)
    try #require(outcome.targetedBuyerOrSponsorContenderIDs.count == 2)
    try #require(outcome.buyerOrSponsorEvaluationCount == 2)
    try #require(outcome.userMessage.contains("buyer/sponsor"))
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
    try #require(index.planEvaluationSummaries.count == 4)
    try #require(index.aggregate.planReadinessByContender.count == 2)
    try #require(
      index.aggregate.planReadinessByContender.allSatisfy {
        $0.buyerOrSponsorPersonaCount == 1 && $0.planProofDebt.buyerOrSponsorDeficit == 0
      })
    try #require(
      index.aggregate.planReadinessByContender.contains {
        $0.recommendation == .advanceToFeasibility || $0.recommendation == .gatherEvidence
      })
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: try workspace.readProductTournamentConfig(),
      evidenceIndex: index
    )
    try #require(digest.contains("plan_readiness"))
    try #require(digest.contains("willingness_to_pay"))
    try #require(digest.contains("commercial_proof"))
    try #require(digest.contains("buyer_sponsor_signals"))
    try #require(digest.contains("plan_proof_debt"))
    try #require(digest.contains("next_plan_proof"))
    try #require(digest.contains("focused_plan_proof_action"))
  }

  @Test func modelFreeRoundOneCanFocusOneContenderProofTarget() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try workspace.writeProductTournamentConfig(config)

    let tournament = try #require(config.tournaments.first)
    let round = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let focusedContender = try #require(config.tournamentContenders.first)

    let outcome = try ProductTournamentPlanEvaluator.runPlanRound(
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: focusedContender.id,
      in: workspace,
      now: Date(timeIntervalSince1970: 2_500)
    )

    try #require(outcome.focusedContenderID == focusedContender.id)
    try #require(outcome.focusedProofTargetSummary == "operator and economic-buyer plan evaluations")
    try #require(outcome.completedEvaluationCount == 2)
    try #require(outcome.records.allSatisfy { $0.contenderID == focusedContender.id })
    try #require(outcome.targetedBuyerOrSponsorContenderIDs == [focusedContender.id])
    try #require(outcome.userMessage.contains("Focused contender: \(focusedContender.id)"))
    try #require(outcome.userMessage.contains("Focused target: operator and economic-buyer"))

    let index = workspace.readProductTournamentEvidenceIndex()
    try #require(index.planEvaluationSummaries.count == 2)
    try #require(index.aggregate.planReadinessByContender.map(\.contenderID) == [focusedContender.id])
  }

  @Test func modelFreeRoundOneTargetsBuyerSponsorDebtAfterOperatorOnlyEvidence() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRoundIndex = try #require(
      config.tournamentRounds.firstIndex { $0.kind == .productPlans })
    let contender = try #require(
      config.tournamentContenders.first { $0.targetSegmentIDs.count == 1 })
    config.tournamentRounds[planRoundIndex].contenderIDs = [contender.id]
    let round = config.tournamentRounds[planRoundIndex]
    try workspace.writeProductTournamentConfig(config)

    let operatorSegmentID = try #require(contender.targetSegmentIDs.first)
    let operatorSegment = try #require(
      config.userSegments.first { $0.id == operatorSegmentID })
    _ = try workspace.writeProductTournamentPlanEvaluationRecord(
      makePlanEvaluationRecord(
        id: "operator-only-plan-eval",
        tournament: tournament,
        round: round,
        contender: contender,
        config: config,
        segment: operatorSegment,
        startedAt: 1,
        endedAt: 2
      )
    )

    let before = try #require(
      workspace.readProductTournamentEvidenceIndex().aggregate.planReadinessByContender.first)
    try #require(before.buyerOrSponsorPersonaCount == 0)
    try #require(before.planProofDebt.buyerOrSponsorDeficit == 1)
    try #require(before.planProofDebt.hasActionableFocusedProof)
    try #require(before.planProofDebt.focusedActionTitle == "Run Buyer Proof")
    try #require(before.commercialProofSummary.contains("buyer/sponsor price and ROI"))
    try #require(before.nextProofTargetSummary.contains("economic-buyer"))
    let beforeDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: try workspace.readProductTournamentConfig(),
      evidenceIndex: workspace.readProductTournamentEvidenceIndex()
    )
    try #require(beforeDigest.contains("commercial_proof"))
    try #require(beforeDigest.contains("next_plan_proof"))
    try #require(beforeDigest.contains("economic-buyer"))
    try #require(beforeDigest.contains("focused_plan_proof_action Run Buyer Proof"))

    let outcome = try ProductTournamentPlanEvaluator.runPlanRound(
      tournamentID: tournament.id,
      roundID: round.id,
      in: workspace,
      now: Date(timeIntervalSince1970: 3_000)
    )

    try #require(outcome.completedEvaluationCount == 1)
    try #require(outcome.targetedBuyerOrSponsorContenderIDs == [contender.id])
    try #require(outcome.buyerOrSponsorEvaluationCount == 1)
    try #require(outcome.userMessage.contains("Targeted buyer/sponsor proof"))
    let buyerRecord = try #require(outcome.records.first)
    try #require(buyerRecord.contenderID == contender.id)
    try #require(
      ProductTournamentPlanPersonaSignals.isBuyerOrSponsor(
        personaID: buyerRecord.personaID,
        personaName: buyerRecord.personaName
      ))

    let after = try #require(
      workspace.readProductTournamentEvidenceIndex().aggregate.planReadinessByContender.first)
    try #require(after.completedEvaluationCount == 2)
    try #require(after.distinctPersonaCount == 2)
    try #require(after.buyerOrSponsorPersonaCount == 1)
    try #require(after.planProofDebt.buyerOrSponsorDeficit == 0)
    try #require(after.planProofDebt.isClear)
    try #require(!after.planProofDebt.hasActionableFocusedProof)
    try #require(after.planProofDebt.focusedActionTitle == "Proof Complete")
    try #require(after.commercialProofSummary.contains("buyer/sponsor willingness to pay"))
    try #require(after.nextProofTargetSummary == "Round 2 feasibility transition")
    let afterDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: try workspace.readProductTournamentConfig(),
      evidenceIndex: workspace.readProductTournamentEvidenceIndex()
    )
    try #require(afterDigest.contains("focused_plan_proof_action Proof Complete"))
  }

  @Test func modelFreeRoundOneRewardsExplicitPricingAndROILanguage() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.painHypotheses[0].painSeverity = "Moderate recurring pain."
    config.painHypotheses[0].costOfInaction = "Manual follow-up continues."
    let tournament = try #require(config.tournaments.first)
    let round = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let buyerSegment = try #require(
      config.userSegments.first { ProductTournamentPlanPersonaSignals.isBuyerOrSponsor($0) })
    let commercialContenderIndex = 0
    let genericContenderIndex = 1
    config.tournamentContenders[commercialContenderIndex].targetSegmentIDs = [buyerSegment.id]
    config.tournamentContenders[commercialContenderIndex].productPlan =
      "Sell a $199/month subscription with an ROI calculator, budget-owner sponsorship, and a one-month payback from saving 8 reporting hours per month."
    config.tournamentContenders[commercialContenderIndex].valueProposition =
      "Show finance a priced reporting product with ROI proof and sponsor-ready savings."
    config.tournamentContenders[genericContenderIndex].targetSegmentIDs = [buyerSegment.id]
    config.tournamentContenders[genericContenderIndex].productPlan =
      "Offer a clearer reporting workspace that organizes updates and reminders."
    config.tournamentContenders[genericContenderIndex].valueProposition =
      "Make weekly reporting easier to review."
    let genericSolutionID = config.tournamentContenders[genericContenderIndex].solutionID
    let genericSolutionIndex = try #require(
      config.productHypotheses.firstIndex { $0.id == genericSolutionID })
    config.productHypotheses[genericSolutionIndex].differentiator =
      "Organizes reporting context in one workflow."
    config.productHypotheses[genericSolutionIndex].whyThisCouldWin =
      "The user may prefer a clearer reporting workspace."
    config.productHypotheses[genericSolutionIndex].requiredProof = [
      "Show reporting steps are easier to review."
    ]
    try workspace.writeProductTournamentConfig(config)

    let outcome = try ProductTournamentPlanEvaluator.runPlanRound(
      tournamentID: tournament.id,
      roundID: round.id,
      in: workspace,
      now: Date(timeIntervalSince1970: 4_000)
    )

    let commercialContender = config.tournamentContenders[commercialContenderIndex]
    let genericContender = config.tournamentContenders[genericContenderIndex]
    let commercialRecord = try #require(
      outcome.records.first { $0.contenderID == commercialContender.id })
    let genericRecord = try #require(
      outcome.records.first { $0.contenderID == genericContender.id })

    try #require(
      (commercialRecord.willingnessToPayScore ?? 0)
        > (genericRecord.willingnessToPayScore ?? 0))
    try #require(commercialRecord.estimatedMonthlyPriceCents == 19_900)
    try #require(commercialRecord.commercialProofSummary?.contains("$199/month") == true)
    try #require(
      commercialRecord.rationale.contains {
        $0.contains("Commercial plan signal") && $0.contains("$199/month")
      })
    try #require(commercialRecord.planStrengths.contains { $0.contains("Commercial proof") })
    try #require(genericRecord.commercialProofSummary?.contains("no explicit price") == true)
    try #require(genericRecord.objections.contains { $0.contains("explicit price, ROI") })
  }

  @Test func planEvaluationRejectsBuiltProductRounds() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = ProductTournamentConfig.seedDefaults(
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

private func makePlanEvaluationRecord(
  id: String,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  contender: ProductTournamentContender,
  config: ProductTournamentConfig,
  segment: UserSegment,
  startedAt: Double,
  endedAt: Double
) throws -> ProductTournamentPlanEvaluationRecord {
  let solution = try #require(config.productHypotheses.first { $0.id == contender.solutionID })
  return ProductTournamentPlanEvaluationRecord(
    id: id,
    tournamentID: tournament.id,
    roundID: round.id,
    contenderID: contender.id,
    solutionID: contender.solutionID,
    experimentID: contender.experimentID,
    painID: solution.painID,
    personaID: segment.id,
    personaName: segment.name,
    currentWorkflowID: segment.currentWorkflowIDs.first,
    alternativeID: segment.alternativeIDs.first,
    startedAt: startedAt,
    endedAt: endedAt,
    scores: ProductTournamentEvidenceScores(
      painRecognition: 5,
      workflowImprovement: 5,
      alternativeAdvantage: 5,
      switchingReadiness: 5,
      continuedUsePull: 5,
      willingnessToPay: 5
    ),
    willingnessToPayScore: 5,
    estimatedMonthlyPriceCents: 9900,
    currentAlternativeComparison: "The plan beats the current workaround.",
    verdict: .strongPull,
    summary: "\(segment.name) strongly liked the plan."
  )
}
