import Foundation
import Testing

@testable import Compass

struct ProductTournamentFeasibilityHandoffTests {
  @Test func roundTwoHandoffTargetsNarrowedContenderImplementationTrack() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let feasibilityRound = try #require(
      config.tournamentRounds.first { $0.kind == .coreTechnology })
    let contender = try #require(config.tournamentContenders.first)
    let experimentID = try #require(contender.experimentID)
    let experiment = try #require(config.tournamentExperiments.first { $0.id == experimentID })
    let records = try strongPlanRecords(
      for: contender,
      tournament: tournament,
      round: planRound,
      config: config
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)
    let transition = try ProductTournamentPlanTransitioner.applyBestProposal(
      tournamentID: tournament.id,
      roundID: planRound.id,
      to: config,
      evidenceIndex: index,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let handoffs = ProductTournamentFeasibilityAdvisor.handoffs(
      config: transition.config,
      evidenceIndex: index
    )
    let handoff = try #require(handoffs.first)
    let implementationTarget = try #require(
      ProductTournamentRoundImplementationTargetResolver.defaultActiveRoundTwoTarget(
        in: transition.config
      )
    )
    let siblingExperimentID = try #require(
      transition.config.tournamentContenders.first {
        $0.tournamentID == tournament.id && $0.experimentID != experiment.id
      }?.experimentID
    )
    let siblingResolvedTarget = try #require(
      ProductTournamentRoundImplementationTargetResolver.roundTwoTarget(
        forExperimentInTargetTournament: siblingExperimentID,
        in: transition.config
      )
    )
    let pausedSiblingExperimentIDs =
      ProductTournamentRoundImplementationTargetResolver.blockedSiblingExperimentIDs(
        for: implementationTarget,
        in: transition.config
      )
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: transition.config,
      evidenceIndex: index
    )
    let planPrompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productTournamentConfig: transition.config,
      productTournamentEvidenceIndex: index
    )
    let reflectPrompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1,
      productTournamentConfig: transition.config,
      productTournamentEvidenceIndex: index
    )

    try #require(handoffs.count == 1)
    try #require(handoff.roundID == feasibilityRound.id)
    try #require(handoff.contenderID == contender.id)
    try #require(handoff.experimentID == experiment.id)
    try #require(handoff.branchName == experiment.branchName)
    try #require(handoff.worktreeID == experiment.worktreeID)
    try #require(implementationTarget.tournamentID == tournament.id)
    try #require(implementationTarget.roundID == feasibilityRound.id)
    try #require(implementationTarget.contenderID == contender.id)
    try #require(implementationTarget.experimentID == experiment.id)
    try #require(siblingResolvedTarget == implementationTarget)
    try #require(pausedSiblingExperimentIDs == [siblingExperimentID])
    try #require(handoff.planRecommendation == .advanceToFeasibility)
    try #require((handoff.planReadinessScore ?? 0) >= 66)
    try #require(handoff.coreTechnologyProof.contains(experiment.title))
    try #require(handoff.implementationTargetLine.contains("selected_experiment \(experiment.id)"))
    try #require(handoff.implementationTargetLine.contains("only_contender \(contender.id)"))
    try #require(
      handoff.implementationTargetLine.contains("do_not_build_competing_contenders true"))
    try #require(handoff.acceptanceSignals.contains("Technical feasibility"))
    try #require(digest.contains("Round 2 implementation target"))
    try #require(digest.contains("round_2_implementation_target"))
    try #require(digest.contains("selected_experiment \(experiment.id)"))
    try #require(digest.contains("only_contender \(contender.id)"))
    try #require(digest.contains("core_technology_proof"))
    try #require(digest.contains("Round 2 implementation target"))
    try #require(digest.contains("round_2_evidence_lock"))
    try #require(digest.contains("paused_sibling_experiments \(siblingExperimentID)"))
    try #require(digest.contains("sibling tournament automation evidence is paused"))
    try #require(digest.contains("Round 2 feasibility handoff"))
    try #require(digest.contains("round_2_feasibility contender \(contender.id)"))
    try #require(digest.contains("experiment \(experiment.id)"))
    try #require(digest.contains("branch \(experiment.branchName)"))
    try #require(digest.contains("plan_readiness"))
    try #require(planPrompt.contains("## Product Tournament Context"))
    try #require(planPrompt.contains("Round 2 implementation target"))
    try #require(planPrompt.contains("must name `selected_experiment`"))
    try #require(planPrompt.contains("selected_experiment \(experiment.id)"))
    try #require(planPrompt.contains("only_contender \(contender.id)"))
    try #require(planPrompt.contains("worktree \(experiment.worktreeID)"))
    try #require(planPrompt.contains("round_2_evidence_lock"))
    try #require(planPrompt.contains("paused_sibling_experiments \(siblingExperimentID)"))
    try #require(planPrompt.contains("Do not plan scenario, cohort, Tournament Automation"))
    try #require(reflectPrompt.contains("## Product Tournament Context"))
    try #require(reflectPrompt.contains("round_2_evidence_lock"))
    try #require(reflectPrompt.contains("paused_sibling_experiments \(siblingExperimentID)"))
    try #require(reflectPrompt.contains("Do not recommend planning"))
  }

  @Test func handoffIsAbsentBeforeRoundOneTransition() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let records = try strongPlanRecords(
      for: contender,
      tournament: tournament,
      round: planRound,
      config: config
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], planEvaluationRecords: records)

    try #require(
      ProductTournamentFeasibilityAdvisor.handoffs(
        config: config,
        evidenceIndex: index
      ).isEmpty
    )
    try #require(
      ProductTournamentRoundImplementationTargetResolver.defaultActiveRoundTwoTarget(
        in: config
      ) == nil
    )
    try #require(
      ProductTournamentRoundImplementationTargetResolver.activeRoundTwoTargets(
        in: config
      ).isEmpty
    )
    try #require(
      ProductTournamentRoundImplementationTargetResolver.blockedSiblingExperimentIDs(
        for: ProductTournamentRoundImplementationTarget(
          tournamentID: tournament.id,
          roundID: planRound.id,
          contenderID: contender.id,
          experimentID: try #require(contender.experimentID)
        ),
        in: config
      ) == []
    )
  }
}

private func strongPlanRecords(
  for contender: ProductTournamentContender,
  tournament: ProductTournament,
  round: ProductTournamentRound,
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  let hypothesis = try #require(config.productHypotheses.first { $0.id == contender.productHypothesisID })
  return config.userSegments.prefix(2).enumerated().map { index, segment in
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-feasibility-\(index)",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      productHypothesisID: contender.productHypothesisID,
      experimentID: contender.experimentID,
      painID: hypothesis.painID,
      personaID: segment.id,
      personaName: segment.name,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      scores: ProductTournamentEvidenceScores(
        painRecognition: 5,
        workflowImprovement: 5,
        alternativeAdvantage: 5,
        switchingReadiness: 5,
        continuedUsePull: 5
      ),
      willingnessToPayScore: 4,
      estimatedMonthlyPriceCents: 9900,
      currentAlternativeComparison: "The plan can beat the current workaround.",
      verdict: .strongPull,
      summary: "The plan is ready for feasibility proof.",
      rationale: ["Strong Round 1 signal."]
    )
  }
}
