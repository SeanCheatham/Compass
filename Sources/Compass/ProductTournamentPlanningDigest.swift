import Foundation

enum ProductTournamentPlanningDigestFormatter {
  static func promptText(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    maxPainHypotheses: Int = 3,
    maxContenderPlans: Int = 5,
    maxExperiments: Int = 6,
    maxDecisions: Int = 4,
    maxEvidenceSignals: Int = 5
  ) -> String {
    var lines: [String] = [
      "Product tournament context starts from durable user pain; competing product contenders are evaluated through rounds."
    ]

    if config.isEmpty {
      lines.append("No product tournament state is configured yet.")
      return boundedLines(lines, maxLines: 36, maxCharacters: 3_800)
    }

    lines += painLines(config: config, maxPainHypotheses: maxPainHypotheses)
    lines += tournamentLines(config: config, evidenceIndex: evidenceIndex)
    lines += roundTwoImplementationTargetLines(config: config, evidenceIndex: evidenceIndex)
    lines += feasibilityHandoffLines(config: config, evidenceIndex: evidenceIndex)
    lines += ProductTournamentRoundTwoProofOverview.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += ProductTournamentRoundTwoProofGapValidationAdvisor.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += roundEvidenceTransitionLines(config: config, evidenceIndex: evidenceIndex)
    lines += revisionBriefLines(config: config, evidenceIndex: evidenceIndex)
    lines += ProductTournamentRoundThreeProductImplementationOverview.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += productImplementationEvidenceTransitionLines(config: config, evidenceIndex: evidenceIndex)
    lines += tournamentAutomationCycleAuditLines(config: config, evidenceIndex: evidenceIndex)
    lines += tournamentAutomationWorktreePrepLines(config: config, evidenceIndex: evidenceIndex)
    lines += tournamentAutomationPlanProofAuditLines(config: config)
    lines += TournamentPlanProofDeltaOverview.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += nextActionLines(config: config, evidenceIndex: evidenceIndex)
    lines += contenderPlanLines(config: config, maxContenderPlans: maxContenderPlans)
    lines += experimentLines(config: config, maxExperiments: maxExperiments)
    lines += evidenceSignalLines(
      config: config,
      index: evidenceIndex,
      maxEvidenceSignals: maxEvidenceSignals
    )
    lines += decisionLines(config: config, maxDecisions: maxDecisions)
    lines += unknownLines(config: config)
    lines += decisionProposalLines(config: config, evidenceIndex: evidenceIndex)
    lines += evidenceTensionLines(config: config, evidenceIndex: evidenceIndex)
    lines += rationaleSignalLines(config: config, evidenceIndex: evidenceIndex)
    lines += targetedProofOutcomeLines(config: config, evidenceIndex: evidenceIndex)
    lines += portfolioPressureLines(config: config, evidenceIndex: evidenceIndex)
    lines += TournamentAutomationProofTargetScoreboard.contextLines(
      config: config,
      evidenceIndex: evidenceIndex
    )
    lines += proofTargetLines(config: config, evidenceIndex: evidenceIndex)
    lines += tournamentAutomationLines(config: config, evidenceIndex: evidenceIndex)

    return boundedLines(lines, maxLines: 80, maxCharacters: 12_000)
  }

  private static func painLines(
    config: ProductTournamentConfig,
    maxPainHypotheses: Int
  ) -> [String] {
    let active = config.painHypotheses
      .filter { $0.status == .active || $0.status == .draft }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return lhs.status == .active
      }
    guard !active.isEmpty else {
      let rawPain = bounded(config.rawPain, 240)
      return [
        "Pain model:",
        rawPain.isEmpty ? "- No active pain hypothesis is configured." : "- Raw pain: \(rawPain).",
      ]
    }

    var lines = ["Active pain hypotheses:"]
    for pain in active.prefix(maxPainHypotheses) {
      lines.append(
        "- \(bounded(pain.title, 180)): \(bounded(pain.rawPain, 220)); situation: \(bounded(pain.targetSituation, 180)); severity: \(bounded(pain.painSeverity, 120))."
      )
      if !pain.costOfInaction.isEmpty {
        lines.append("- Cost of inaction: \(bounded(pain.costOfInaction, 220)).")
      }
    }
    if active.count > maxPainHypotheses {
      lines.append("- \(active.count - maxPainHypotheses) more pain hypothesis/hypotheses omitted.")
    }
    return lines
  }

  private static func tournamentLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let tournaments = config.tournaments
      .filter { $0.status == .active || $0.status == .drafting }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return lhs.status == .active
      }

    guard !tournaments.isEmpty else {
      return [
        "Product tournaments:",
        "- No active tournament is configured. Seed competing contenders and rounds before committing to one product.",
      ]
    }

    var lines = ["Product tournaments:"]
    for tournament in tournaments.prefix(3) {
      let currentRound =
        tournament.currentRoundID.flatMap { roundID in
          config.tournamentRounds.first { $0.id == roundID }
        }
      let currentRoundLabel =
        currentRound.map {
          "round \($0.ordinal) \($0.kind.rawValue)"
        } ?? "no current round"
      lines.append(
        "- \(bounded(tournament.title, 120)) [\(tournament.status.rawValue), pain \(tournament.painID), \(currentRoundLabel)]: \(bounded(tournament.premise, 160))."
      )

      let contenders = tournament.contenderIDs.compactMap { contenderID in
        config.tournamentContenders.first { $0.id == contenderID }
      }
      for contender in contenders.prefix(4) {
        let experiment = contender.experimentID ?? "no implementation track"
        let segments =
          contender.targetSegmentIDs.isEmpty
          ? "no target segment"
          : contender.targetSegmentIDs.joined(separator: ", ")
        let planReadiness = evidenceIndex.aggregate.planReadinessByContender.first {
          $0.contenderID == contender.id
        }
        let planEvidenceBase =
          planReadiness.map {
            "plan_readiness \($0.scoreLabel)/100, recommendation \($0.recommendation.rawValue), willingness_to_pay \(bounded(formatScore($0.averageWillingnessToPayScore), 20))/5, commercial_proof \($0.commercialProofSummary), buyer_sponsor_signals \($0.buyerOrSponsorPersonaCount), plan_modes persona_model \($0.personaModelEvaluationCount) model_free \($0.modelFreeEvaluationCount), plan_proof_debt \($0.planProofDebt.summary), next_plan_proof \($0.nextProofTargetSummary), focused_plan_proof_action \($0.planProofDebt.focusedActionTitle)"
          }
          ?? "no plan evidence, commercial_proof no willingness-to-pay proof yet, plan_modes persona_model 0 model_free 0, next_plan_proof operator and economic-buyer plan evaluations, focused_plan_proof_action Run Plan Proof"
        let planEvidence = [
          planEvidenceBase,
          TournamentAutomationPlanProofAuditDeltaFinder
            .latest(for: contender, in: config)?
            .contextSummary,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        lines.append(
          "- Contender \(contender.id) [\(contender.status.rawValue), contender_plan \(contender.contenderPlanID), exp \(experiment), seg \(segments), \(planEvidence)]: \(bounded(contender.valueProposition, 100)); risk \(bounded(contender.primaryRisk, 60))."
        )
      }

      let rounds = tournament.roundIDs.compactMap { roundID in
        config.tournamentRounds.first { $0.id == roundID }
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
        return lhs.ordinal < rhs.ordinal
      }
      if !rounds.isEmpty {
        let roundSummary = rounds.prefix(4)
          .map { round in
            let productRequirement = round.requiresBuiltProduct ? "product required" : "no product"
            return
              "R\(round.ordinal) \(round.kind.rawValue) \(round.status.rawValue)/\(productRequirement)"
          }
          .joined(separator: "; ")
        lines.append("- Rounds: \(bounded(roundSummary, 280)).")
      }
      if let currentRound {
        let focus =
          currentRound.evaluationFocus.isEmpty
          ? "no evaluation focus"
          : currentRound.evaluationFocus.prefix(4).joined(separator: "; ")
        lines.append(
          "- Current round goal: \(bounded(currentRound.goal, 160)); focus \(bounded(focus, 160))."
        )
      }
    }
    if tournaments.count > 3 {
      lines.append("- \(tournaments.count - 3) more tournament(s) omitted.")
    }
    return lines
  }

  private static func contenderPlanLines(
    config: ProductTournamentConfig,
    maxContenderPlans: Int
  ) -> [String] {
    let contenderPlans = config.contenderPlans
      .filter { $0.status == .active || $0.status == .candidate || $0.status == .promoted }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.title < rhs.title }
        return contenderPlanStatusRank(lhs.status) < contenderPlanStatusRank(rhs.status)
      }
    guard !contenderPlans.isEmpty else {
      return [
        "Contender plans:",
        "- No active or candidate contender plan is configured.",
      ]
    }

    var lines = ["Contender plans:"]
    for contenderPlan in contenderPlans.prefix(maxContenderPlans) {
      let segments =
        contenderPlan.targetSegmentIDs.isEmpty
        ? "no target segment"
        : contenderPlan.targetSegmentIDs.joined(separator: ", ")
      let proof =
        contenderPlan.requiredProof.isEmpty
        ? "no required proof"
        : bounded(contenderPlan.requiredProof.joined(separator: "; "), 160)
      lines.append(
        "- \(bounded(contenderPlan.title, 120)) [\(contenderPlan.status.rawValue), pain \(contenderPlan.painID), segments \(segments)]: \(bounded(contenderPlan.promise, 150)); proof \(proof)."
      )
    }
    if contenderPlans.count > maxContenderPlans {
      lines.append(
        "- \(contenderPlans.count - maxContenderPlans) more contender plan(s) omitted.")
    }
    return lines
  }

  private static func feasibilityHandoffLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let handoffs = ProductTournamentFeasibilityAdvisor.handoffs(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !handoffs.isEmpty else { return [] }
    return ["Round 2 feasibility handoff:"]
      + handoffs.prefix(3).map { handoff in bounded(handoff.digestLine, 620) }
  }

  private static func roundTwoImplementationTargetLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let handoffs = ProductTournamentFeasibilityAdvisor.handoffs(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard let target = handoffs.first else { return [] }
    var lines = ["Round 2 implementation target:"]
    lines.append(bounded(target.implementationTargetLine, 760))
    if target.implementationBrief.isCandidateDerived {
      let expectedEvidence =
        target.implementationBrief.expectedEvidenceSignal ?? "no expected evidence signal"
      let killCriteria = target.implementationBrief.killCriteria ?? "no kill criteria"
      lines.append(
        bounded(
          "- round_2_candidate_track_signal selected_experiment \(target.experimentID) [tournament \(target.tournamentID), round \(target.roundID), only_contender \(target.contenderID)]: expected_evidence \(expectedEvidence); kill_criteria \(killCriteria); implementation_scope \(target.implementationBrief.scopeSummary).",
          760
        )
      )
    }
    let implementationTarget = ProductTournamentRoundImplementationTarget(
      tournamentID: target.tournamentID,
      roundID: target.roundID,
      contenderID: target.contenderID,
      experimentID: target.experimentID
    )
    let pausedSiblingExperimentIDs =
      ProductTournamentRoundImplementationTargetResolver.blockedSiblingExperimentIDs(
        for: implementationTarget,
        in: config
      )
    if !pausedSiblingExperimentIDs.isEmpty {
      lines.append(
        bounded(
          "- round_2_evidence_lock selected_experiment \(target.experimentID) [tournament \(target.tournamentID), round \(target.roundID), only_contender \(target.contenderID), paused_sibling_experiments \(pausedSiblingExperimentIDs.joined(separator: ", "))]: sibling tournament automation evidence is paused; run only the selected core_technology_proof \(target.coreTechnologyProof).",
          760
        )
      )
    }
    if handoffs.count > 1 {
      lines.append(
        "- \(handoffs.count - 1) additional Round 2 target(s) omitted; keep one Immediate scoped to selected_experiment \(target.experimentID)."
      )
    }
    return lines
  }

  private static func roundEvidenceTransitionLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let proposals = ProductTournamentRoundEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !proposals.isEmpty else { return [] }
    return ["Round 2 evidence transition:"]
      + proposals.prefix(3).map { proposal in bounded(proposal.digestLine, 620) }
  }

  private static func productImplementationEvidenceTransitionLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let proposals = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !proposals.isEmpty else { return [] }
    return ["Round 3 product implementation transition:"]
      + proposals.prefix(3).map { proposal in bounded(proposal.digestLine, 620) }
  }

  private static func experimentLines(
    config: ProductTournamentConfig,
    maxExperiments: Int
  ) -> [String] {
    let experiments = config.tournamentExperiments.sorted { lhs, rhs in
      if lhs.decision == rhs.decision { return lhs.updatedAt > rhs.updatedAt }
      return experimentDecisionRank(lhs.decision) < experimentDecisionRank(rhs.decision)
    }
    guard !experiments.isEmpty else {
      return [
        "Experiments and branches:",
        "- No tournament experiments are configured yet.",
      ]
    }

    var lines = ["Experiments and branches:"]
    for experiment in experiments.prefix(maxExperiments) {
      let sha = experiment.currentSha ?? experiment.baseSha ?? "not-created"
      let evidenceSummary =
        experiment.evidenceSummary.isEmpty
        ? "no evidence recorded"
        : bounded(experiment.evidenceSummary, 120)
      lines.append(
        "- \(bounded(experiment.title, 120)) [\(experiment.decision.rawValue)]: contender_plan \(experiment.contenderPlanID), branch \(bounded(experiment.branchName, 140)), sha \(sha); scope \(bounded(experiment.implementationScope, 140)); evidence \(evidenceSummary)."
      )
    }
    if experiments.count > maxExperiments {
      lines.append("- \(experiments.count - maxExperiments) more experiment(s) omitted.")
    }
    return lines
  }

  private static func decisionLines(
    config: ProductTournamentConfig,
    maxDecisions: Int
  ) -> [String] {
    let decisions = config.decisions
      .sorted { lhs, rhs in
        if lhs.decidedAt == rhs.decidedAt { return lhs.id < rhs.id }
        return lhs.decidedAt > rhs.decidedAt
      }
      .prefix(maxDecisions)
    guard !decisions.isEmpty else { return [] }

    return ["Latest tournament decisions:"]
      + decisions.map { decision in
        let evidence =
          decision.evidenceRunIDs.isEmpty
          ? "no evidence runs"
          : "evidence \(decision.evidenceRunIDs.joined(separator: ", "))"
        return
          "- \(decision.experimentID): \(decision.decision.rawValue) by \(bounded(decision.decidedBy, 80)); \(evidence); \(bounded(decision.summary, 220))."
      }
  }

  private static func unknownLines(config: ProductTournamentConfig) -> [String] {
    let unknowns = config.painHypotheses
      .filter { $0.status == .active || $0.status == .draft }
      .flatMap(\.unknowns)
      .productTournamentUniquedPreservingOrder()
      .prefix(6)
    guard !unknowns.isEmpty else { return [] }
    return ["Unresolved product unknowns:"]
      + unknowns.map { "- \(bounded($0, 220))." }
  }

  private static func decisionProposalLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let candidates = TournamentAutomationDecisionCandidateAdvisor.candidates(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !candidates.isEmpty else { return [] }
    var lines = ["Tournament automation decision candidates:"]
    for candidate in candidates.prefix(4) {
      let evidence =
        candidate.evidenceRunIDs.isEmpty
        ? "no evidence runs"
        : "evidence \(candidate.evidenceRunIDs.prefix(4).joined(separator: ", "))"
      let metadata = [
        "action apply_decision",
        "current \(candidate.currentDecision.rawValue)",
        "target_decision \(candidate.targetDecision.rawValue)",
        "pressure \(candidate.pressure.rawValue)",
        "score \(candidate.readinessScore)/100",
      ]
      lines.append(
        "- \(candidate.experimentID): \(metadata.joined(separator: "; ")); \(evidence); \(bounded(candidate.summary, 220))."
      )
    }
    return lines
  }

  private static func evidenceTensionLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let tensions = TournamentAutomationEvidenceTensionAdvisor.tensions(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !tensions.isEmpty else { return [] }
    var lines = ["Tournament automation evidence tensions:"]
    for tension in tensions.prefix(4) {
      var metadata = [
        "action resolve_signal_split",
        "score \(tension.readinessScore)/100",
        "strongest \(tension.strongestVerdict.rawValue)",
        "weakest \(tension.weakestVerdict.rawValue)",
      ]
      if !tension.positiveEvidenceRunIDs.isEmpty {
        metadata.append("pull \(tension.positiveEvidenceRunIDs.prefix(4).joined(separator: ", "))")
      }
      if !tension.negativeEvidenceRunIDs.isEmpty {
        metadata.append(
          "reject \(tension.negativeEvidenceRunIDs.prefix(4).joined(separator: ", "))")
      }
      if let targetCohortID = tension.targetCohortID {
        metadata.append("cohort \(targetCohortID)")
      }
      if let targetScenarioID = tension.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = tension.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetPersonaName = tension.targetPersonaName {
        metadata.append("target_name \(bounded(targetPersonaName, 80))")
      }
      if let targetDecision = tension.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      lines.append(
        "- \(tension.experimentID): \(metadata.joined(separator: "; ")); \(bounded(tension.summary, 240))."
      )
    }
    return lines
  }

  private static func portfolioPressureLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let signals = TournamentAutomationExperimentRanker.experimentSignals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .filter {
      $0.pressure != .wait || $0.nextActionKind != nil || $0.readinessScore != nil
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
    guard !signals.isEmpty else { return [] }
    var lines = ["Tournament automation portfolio pressure:"]
    for signal in signals.prefix(4) {
      var metadata = [
        "pressure \(signal.pressure.rawValue)",
        "readiness \(bounded(signal.readinessLabel, 80))",
        "next \(bounded(signal.nextActionLabel, 120))",
      ]
      if signal.staleEvidenceCount > 0 {
        metadata.append("stale \(signal.staleEvidenceCount)")
      }
      if let targetDecision = signal.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      if let proofDebtSummary = signal.proofDebtSummary {
        metadata.append("proof_debt \(bounded(proofDebtSummary, 160))")
      }
      lines.append("- \(signal.experimentID): \(metadata.joined(separator: "; ")).")
    }
    return lines
  }

  private static func rationaleSignalLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let signals = TournamentAutomationRationaleSignalAdvisor.signals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !signals.isEmpty else { return [] }
    var lines = ["Tournament automation rationale signals:"]
    for signal in signals.prefix(4) {
      var metadata = [
        "action resolve_rationale_signal",
        "count \(signal.count)",
        "priority \(signal.urgencyScore)",
      ]
      if let targetCohortID = signal.targetCohortID {
        metadata.append("cohort \(targetCohortID)")
      }
      if let targetScenarioID = signal.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = signal.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetPersonaName = signal.targetPersonaName {
        metadata.append("target_name \(bounded(targetPersonaName, 80))")
      }
      if let targetDecision = signal.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      if !signal.runIDs.isEmpty {
        metadata.append("runs \(signal.runIDs.prefix(4).joined(separator: ", "))")
      }
      lines.append(
        "- \(signal.experimentID): \(metadata.joined(separator: "; ")); \(bounded(signal.rationale, 180)); \(bounded(signal.summary, 220))."
      )
    }
    return lines
  }

  private static func targetedProofOutcomeLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let signals = TournamentAutomationTargetedProofOutcomeAdvisor.signals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !signals.isEmpty else { return [] }
    var lines = ["Tournament automation targeted proof outcomes:"]
    for signal in signals.prefix(4) {
      var metadata = [
        "action \(signal.actionKind.rawValue)",
        "target_decision \(signal.targetDecision.rawValue)",
        "outcome \(signal.outcome.rawValue)",
        "count \(signal.count)",
        "priority \(signal.priority)",
      ]
      if let recommendedDecision = signal.recommendedDecision {
        metadata.append("recommended_decision \(recommendedDecision.rawValue)")
      }
      if let targetCohortID = signal.targetCohortID {
        metadata.append("cohort \(targetCohortID)")
      }
      if let targetScenarioID = signal.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = signal.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetPersonaName = signal.targetPersonaName {
        metadata.append("target_name \(bounded(targetPersonaName, 80))")
      }
      if !signal.runIDs.isEmpty {
        metadata.append("runs \(signal.runIDs.prefix(4).joined(separator: ", "))")
      }
      lines.append(
        "- \(signal.experimentID): \(metadata.joined(separator: "; ")); \(bounded(signal.summary, 240))."
      )
    }
    return lines
  }

  private static func revisionBriefLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let briefs = TournamentAutomationRevisionBriefAdvisor.briefs(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !briefs.isEmpty else { return [] }
    var lines = ["Tournament automation revision briefs:"]
    for brief in briefs.prefix(4) {
      var metadata = [
        "action revise_product_contender",
        "source \(brief.source.rawValue)",
        "priority \(brief.priority)",
      ]
      if let validationContextSummary = brief.validationContextSummary {
        metadata.append("validation \(bounded(validationContextSummary, 100))")
      }
      if let targetCohortID = brief.targetCohortID {
        metadata.append("cohort \(targetCohortID)")
      }
      if let targetScenarioID = brief.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = brief.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetPersonaName = brief.targetPersonaName {
        metadata.append("target_name \(bounded(targetPersonaName, 80))")
      }
      if let targetDecision = brief.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      lines.append(
        "- \(brief.experimentID): \(metadata.joined(separator: "; ")); \(bounded(brief.title, 140)); implementation \(bounded(brief.implementationChange, 220)); scenario \(bounded(brief.scenarioChange, 220)); proof \(bounded(brief.proofPlan, 220))."
      )
    }
    return lines
  }

  private static func proofTargetLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let targets = TournamentAutomationProofTargetAdvisor.targets(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
    var lines = ["Tournament automation proof targets:"]
    for target in targets.prefix(4) {
      var metadata = [
        "target \(target.label)",
        "score \(target.readinessScore)/100",
        "debt \(bounded(target.debtSummary, 160))",
      ]
      if let nextActionTitle = target.nextActionTitle {
        metadata.append("next \(bounded(nextActionTitle, 100))")
      }
      if let tournamentPositionSummary = target.tournamentPositionSummary {
        metadata.append("position \(bounded(tournamentPositionSummary, 160))")
      }
      if let tournamentID = target.tournamentID {
        metadata.append("tournament \(tournamentID)")
      }
      if let contenderID = target.contenderID {
        metadata.append("contender \(contenderID)")
      }
      if let roundID = target.roundID {
        metadata.append("round \(roundID)")
      }
      if let cohortID = target.cohortID {
        metadata.append("cohort \(cohortID)")
      }
      if let targetScenarioID = target.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = target.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetPersonaName = target.targetPersonaName {
        metadata.append("target_name \(bounded(targetPersonaName, 80))")
      }
      if let targetDecision = target.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      if let requiredMode = target.requiredSimulationMode {
        metadata.append("required_mode \(requiredMode.rawValue)")
      }
      lines.append("- \(target.experimentID): \(metadata.joined(separator: "; ")).")
    }
    return lines.count > 1 ? lines : []
  }

  private static func tournamentAutomationLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    guard
      let step = TournamentAutomationPlanner.nextStep(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
      )
    else { return [] }
    let cyclePlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
    var metadata = [
      "experiment \(step.experimentID)",
      "kind \(step.kind.rawValue)",
      "action \(step.action.kind.rawValue)",
      "priority \(step.action.priority)",
      "executable \(step.canExecute)",
    ]
    if let cohortID = step.cohortID {
      metadata.append("cohort \(cohortID)")
    }
    if let tournamentID = step.tournamentID {
      metadata.append("tournament \(tournamentID)")
    }
    if let roundID = step.roundID {
      metadata.append("round \(roundID)")
    }
    if let contenderID = step.contenderID {
      metadata.append("contender \(contenderID)")
    }
    if let targetScenarioID = step.targetScenarioID {
      metadata.append("target_scenario \(targetScenarioID)")
    }
    if let targetPersonaID = step.action.targetPersonaID {
      metadata.append("target_persona \(targetPersonaID)")
    }
    if let targetDecision = step.action.targetDecision {
      metadata.append("target_decision \(targetDecision.rawValue)")
    }
    if let requiredMode = step.action.requiredSimulationMode {
      metadata.append("required_mode \(requiredMode.rawValue)")
    }
    if step.kind == .runPlanProof {
      let modeLabel =
        step.action.requiredSimulationMode == .personaModel
        ? "persona_model_plan" : "model_free_plan"
      metadata.append("mode \(modeLabel)")
    } else if step.kind == .prepareWorktree {
      metadata.append("mode prepare_worktree")
    } else if step.kind == .runCohort {
      let mode =
        step.action.requiredSimulationMode
        ?? TournamentAutomationPlanner.cohortSimulationMode(
          isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
        )
      metadata.append("mode \(mode.rawValue)")
    }
    if let blockedReason = step.blockedReason {
      metadata.append("blocked \(bounded(blockedReason, 140))")
    }
    return [
      "Tournament automation step:",
      "- \(metadata.joined(separator: "; ")); \(bounded(step.title, 120)); \(bounded(step.detail, 220)).",
      "- cycle executable \(cyclePlan.executableSteps.count); max \(cyclePlan.maxSteps); capped \(cyclePlan.capped); \(bounded(cyclePlan.summary, 180)).",
      "- cycle queue \(bounded(cyclePlan.queueSummary, 240)).",
    ]
  }

  private static func nextActionLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let actions = ProductTournamentNextActionAdvisor.actions(
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard !actions.isEmpty else { return [] }
    var lines = ["Next tournament automation actions:"]
    for action in actions.prefix(4) {
      var metadata = [
        "kind \(action.kind.rawValue)",
        "priority \(action.priority)",
      ]
      if let cohortID = action.cohortID {
        metadata.append("cohort \(cohortID)")
      }
      if let targetScenarioID = action.targetScenarioID {
        metadata.append("target_scenario \(targetScenarioID)")
      }
      if let targetPersonaID = action.targetPersonaID {
        metadata.append("target_persona \(targetPersonaID)")
      }
      if let targetDecision = action.targetDecision {
        metadata.append("target_decision \(targetDecision.rawValue)")
      }
      if let requiredMode = action.requiredSimulationMode {
        metadata.append("required_mode \(requiredMode.rawValue)")
      }
      lines.append(
        "- \(action.experimentID): \(metadata.joined(separator: "; ")); \(bounded(action.title, 120)); \(bounded(action.detail, 220))."
      )
    }
    return lines
  }

  private static func tournamentAutomationCycleAuditLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let audits = config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(3)
    guard !audits.isEmpty else { return [] }
    return ["Recent tournament automation cycle audits:"]
      + audits.map { audit in
        let experiments =
          audit.experimentIDs.isEmpty
          ? "no experiments"
          : "experiments \(audit.experimentIDs.joined(separator: ", "))"
        let decisionCandidateList = audit.decisionCandidateSummaries.prefix(3)
          .joined(separator: " | ")
        let decisionCandidates =
          audit.decisionCandidateSummaries.isEmpty
          ? ""
          : "; decision candidates \(bounded(decisionCandidateList, 260))"
        let evidenceTensionList = audit.evidenceTensionSummaries.prefix(3)
          .joined(separator: " | ")
        let evidenceTensions =
          audit.evidenceTensionSummaries.isEmpty
          ? ""
          : "; evidence tensions \(bounded(evidenceTensionList, 260))"
        let proofTargetList = audit.proofTargetSummaries.prefix(3).joined(separator: " | ")
        let proofTargets =
          audit.proofTargetSummaries.isEmpty
          ? ""
          : "; proof targets \(bounded(proofTargetList, 260))"
        let actedPressureGroupList = audit.actedProofPressureGroupSummaries.prefix(3)
          .joined(separator: " | ")
        let actedPressureGroups =
          audit.actedProofPressureGroupSummaries.isEmpty
          ? ""
          : "; acted pressure groups \(bounded(actedPressureGroupList, 260))"
        let actedPressureGroupOutcomes =
          TournamentAutomationCycleWorkbenchFacts.actedPressureGroupOutcomeSummary(
            for: audit,
            config: config,
            evidenceIndex: evidenceIndex
          )
          .map { "; acted group outcomes \(bounded($0, 260))" } ?? ""
        let actedPressureGroupLearning =
          TournamentAutomationCycleWorkbenchFacts.actedPressureGroupLearningSummary(
            for: audit,
            config: config,
            evidenceIndex: evidenceIndex
          )
          .map { "; acted group learning \(bounded($0, 260))" } ?? ""
        let targetedProofOutcomeList = audit.targetedProofOutcomeSummaries.prefix(3)
          .joined(separator: " | ")
        let targetedProofOutcomes =
          audit.targetedProofOutcomeSummaries.isEmpty
          ? ""
          : "; targeted proof outcomes \(bounded(targetedProofOutcomeList, 260))"
        let rationaleSignalList = audit.personaRationaleSignalSummaries.prefix(3)
          .joined(separator: " | ")
        let rationaleSignals =
          audit.personaRationaleSignalSummaries.isEmpty
          ? ""
          : "; rationale signals \(bounded(rationaleSignalList, 260))"
        let revisionBriefList = audit.revisionBriefSummaries.prefix(3)
          .joined(separator: " | ")
        let revisionBriefs =
          audit.revisionBriefSummaries.isEmpty
          ? ""
          : "; revisions \(bounded(revisionBriefList, 260))"
        let planModes = audit.planEvaluationModeContext.map { "; \($0)" } ?? ""
        return
          "- \(bounded(audit.id, 100)): \(bounded(audit.summary, 220)); \(experiments)\(planModes)\(decisionCandidates)\(evidenceTensions)\(proofTargets)\(targetedProofOutcomes)\(rationaleSignals)\(revisionBriefs)"
          + "\(actedPressureGroups)\(actedPressureGroupOutcomes)\(actedPressureGroupLearning); stop \(audit.stopReason.rawValue); \(bounded(audit.userMessage, 260))."
      }
  }

  private static func tournamentAutomationWorktreePrepLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    let audits = config.tournamentAutomationCycleAudits
      .filter { $0.prepareWorktreeStepCount > 0 }
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(3)
    guard !audits.isEmpty else { return [] }
    return ["Recent tournament automation worktree preparation:"]
      + audits.map { audit in
        let experimentIDs = audit.experimentIDs.isEmpty ? ["unknown-experiment"] : audit.experimentIDs
        let evidenceRunCount = experimentIDs.reduce(0) { count, experimentID in
          guard
            let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
          else { return count }
          return count + evidenceIndex.summaries(for: experiment).count
        }
        let experiments = bounded(experimentIDs.joined(separator: ", "), 220)
        return
          "- \(bounded(audit.id, 100)): prepare_worktree_steps \(audit.prepareWorktreeStepCount); experiments \(experiments); current_evidence_runs \(evidenceRunCount); \(bounded(audit.stopDetail, 180))."
      }
  }

  private static func tournamentAutomationPlanProofAuditLines(
    config: ProductTournamentConfig
  ) -> [String] {
    let deltas = TournamentAutomationPlanProofAuditDeltaFinder.recent(in: config, limit: 3)
    guard !deltas.isEmpty else { return [] }

    return ["Round 1 plan-proof automation deltas:"]
      + deltas.map(\.auditLine)
  }

  private static func evidenceSignalLines(
    config: ProductTournamentConfig,
    index: ProductTournamentEvidenceIndex,
    maxEvidenceSignals: Int
  ) -> [String] {
    var lines: [String] = []
    let currentSummaries = config.tournamentExperiments
      .flatMap { index.summaries(for: $0) }
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
        return lhs.endedAt > rhs.endedAt
      }
    let currentAggregate = ProductTournamentEvidenceAggregateSummary(summaries: currentSummaries)
    let staleCount = config.tournamentExperiments
      .map { index.staleSummaryCount(for: $0) }
      .reduce(0, +)
    if staleCount > 0 {
      lines.append(
        "Stale product tournament evidence ignored for current tournament decisions: \(staleCount) run(s) from older experiment commits."
      )
    }

    let summaries = currentSummaries.prefix(maxEvidenceSignals)
    if !summaries.isEmpty {
      lines.append("Top current-commit evidence signals and objections:")
      for summary in summaries {
        var parts = [
          "run \(summary.runID)",
          "scenario \(summary.scenarioID)",
          "experiment \(summary.experimentID)",
          "branch \(bounded(summary.branchName, 140))",
          "commit \(bounded(summary.commitSha, 80))",
          "status \(summary.status.rawValue)",
          "model \(bounded(summary.model, 80))",
          "mode \(summary.mode.rawValue)",
          "verdict \(summary.verdict.rawValue)",
        ]
        if let tournamentID = summary.tournamentID {
          parts.append("tournament \(tournamentID)")
        }
        if let roundID = summary.roundID {
          parts.append("round \(roundID)")
        }
        if let contenderID = summary.contenderID {
          parts.append("contender \(contenderID)")
        }
        if let decisionIntent = summary.decisionIntent {
          parts.append("target_decision \(decisionIntent.targetDecision.rawValue)")
          parts.append("current_decision \(decisionIntent.currentDecision.rawValue)")
          if !decisionIntent.scorecardFocus.isEmpty {
            parts.append(
              "intent_focus \(bounded(decisionIntent.scorecardFocus.prefix(5).joined(separator: ", "), 180))"
            )
          }
        }
        if let evaluation = summary.decisionIntentEvaluation {
          parts.append("intent_outcome \(evaluation.outcome.rawValue)")
          if !evaluation.rationale.isEmpty {
            parts.append("intent_rationale \(bounded(evaluation.rationale, 180))")
          }
        }
        if summary.scores.hasScores {
          let scores = [
            summary.scores.painRecognition.map { "pain \($0)" },
            summary.scores.workflowImprovement.map { "workflow \($0)" },
            summary.scores.alternativeAdvantage.map { "alternative \($0)" },
            summary.scores.switchingReadiness.map { "switch \($0)" },
            summary.scores.continuedUsePull.map { "pull \($0)" },
            summary.scores.willingnessToPay.map { "pay \($0)" },
          ].compactMap { $0 }.joined(separator: ", ")
          parts.append("scores \(scores)")
        }
        if let willingnessToPayScore = summary.willingnessToPayScore {
          parts.append("willingness_to_pay \(willingnessToPayScore)/5")
        }
        if !summary.sponsorshipIntent.isEmpty {
          parts.append("sponsorship_intent \(bounded(summary.sponsorshipIntent, 180))")
        }
        parts.append("completed_use_proof \(summary.completedUseProof ? "yes" : "no")")
        if let objection = summary.objections.first, !objection.isEmpty {
          parts.append("objection \(bounded(objection, 180))")
        }
        if !summary.missingCapabilities.isEmpty {
          parts.append(
            "missing \(bounded(summary.missingCapabilities.joined(separator: ", "), 180))")
        }
        if !summary.currentAlternativeComparison.isEmpty {
          parts.append("alternative \(bounded(summary.currentAlternativeComparison, 180))")
        }
        if let rationale = summary.personaActionRationales.first, !rationale.isEmpty {
          parts.append("persona_rationale \(bounded(rationale, 200))")
        }
        if let hash = summary.traceHash {
          parts.append("trace \(bounded(hash, 80))")
        }
        lines.append("- \(parts.joined(separator: "; ")).")
      }
    }

    if !currentAggregate.repeatedObjections.isEmpty {
      let objections = currentAggregate.repeatedObjections.prefix(4)
        .map { "\(bounded($0.objection, 120)) (\($0.count)x)" }
        .joined(separator: "; ")
      lines.append("Repeated objections: \(objections).")
    }

    if !currentAggregate.personaRationaleSignals.isEmpty {
      let signals = currentAggregate.personaRationaleSignals.prefix(4)
        .map { signal in
          let runs =
            signal.runIDs.isEmpty
            ? ""
            : "; runs \(signal.runIDs.prefix(3).joined(separator: ", "))"
          return "\(bounded(signal.rationale, 140)) (\(signal.count)x\(runs))"
        }
        .joined(separator: "; ")
      lines.append("simulated-user rationale signals: \(signals).")
    }

    if !currentAggregate.decisionIntentOutcomes.isEmpty {
      let outcomes = currentAggregate.decisionIntentOutcomes.prefix(4)
        .map { outcome in
          let runs =
            outcome.runIDs.isEmpty
            ? ""
            : "; runs \(outcome.runIDs.prefix(3).joined(separator: ", "))"
          return
            "\(outcome.targetDecision.rawValue) \(outcome.outcome.rawValue) (\(outcome.count)x\(runs))"
        }
        .joined(separator: "; ")
      lines.append("Targeted tournament proof outcomes: \(outcomes).")
    }

    let currentReadiness = config.tournamentExperiments
      .compactMap { index.currentTournamentReadiness(for: $0) }
      .sorted { lhs, rhs in
        if lhs.readinessScore == rhs.readinessScore {
          return lhs.experimentID < rhs.experimentID
        }
        return lhs.readinessScore > rhs.readinessScore
      }
    if !currentReadiness.isEmpty {
      lines.append("Current-commit product tournament readiness:")
      for readiness in currentReadiness.prefix(4) {
        let evidence =
          readiness.evidenceRunIDs.isEmpty
          ? "no evidence runs"
          : "evidence \(readiness.evidenceRunIDs.prefix(4).joined(separator: ", "))"
        let rationale = readiness.rationale.first.map { "; \(bounded($0, 180))" } ?? ""
        let proofDebt =
          readiness.proofDebt.isClear
          ? "proof-debt clear"
          : "proof-debt \(bounded(readiness.proofDebt.summary, 180))"
        lines.append(
          "- \(readiness.experimentID): score \(readiness.scoreLabel)/100; recommend \(readiness.recommendation.rawValue); persona-model \(readiness.personaModelCompletedRunCount) across \(readiness.personaModelDistinctPersonaCount) simulated user(s); alt-proof \(readiness.personaModelCurrentAlternativePersonaCount) persona-model simulated user(s); model-free \(readiness.modelFreeCompletedRunCount); \(proofDebt); \(evidence)\(rationale)."
        )
      }
    }

    if !currentAggregate.missingCapabilityFrequency.isEmpty {
      let missing = currentAggregate.missingCapabilityFrequency.prefix(4)
        .map { "\(bounded($0.capabilityID, 120)) (\($0.count)x)" }
        .joined(separator: "; ")
      lines.append("Missing capabilities: \(missing).")
    }

    if !currentAggregate.currentAlternativeComparisons.isEmpty {
      lines.append("Current alternative comparisons:")
      for comparison in currentAggregate.currentAlternativeComparisons.prefix(3) {
        lines.append(
          "- \(comparison.experimentID) / \(comparison.runID): \(bounded(comparison.comparison, 220)) [\(comparison.verdict.rawValue)]."
        )
      }
    }

    if index.malformedRecordCount > 0 {
      lines.append("\(index.malformedRecordCount) malformed evidence record(s) were skipped.")
    }
    return lines
  }

  private static func contenderPlanStatusRank(_ status: ProductTournamentContenderPlanStatus) -> Int {
    switch status {
    case .promoted: return 0
    case .active: return 1
    case .candidate: return 2
    case .parked: return 3
    case .rejected: return 4
    }
  }

  private static func experimentDecisionRank(_ decision: ProductTournamentExperimentDecision) -> Int {
    switch decision {
    case .promoted: return 0
    case .promote: return 0
    case .keepGoing: return 1
    case .narrow: return 2
    case .pivot: return 3
    case .notRun: return 4
    case .kill: return 5
    case .archived: return 6
    }
  }

  private static func boundedLines(
    _ lines: [String],
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    var selected: [String] = []
    var characterCount = 0
    for line in lines where selected.count < maxLines {
      let nextCount = characterCount + line.count + 1
      guard nextCount <= maxCharacters else { break }
      selected.append(line)
      characterCount = nextCount
    }
    return selected.joined(separator: "\n")
  }

  private static func bounded(_ value: String, _ limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }

  private static func formatScore(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

extension Array where Element == String {
  fileprivate func productTournamentUniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self {
      guard seen.insert(value).inserted else { continue }
      out.append(value)
    }
    return out
  }
}
