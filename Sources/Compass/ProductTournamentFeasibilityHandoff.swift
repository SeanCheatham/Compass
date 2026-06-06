import Foundation

struct ProductTournamentFeasibilityHandoff: Codable, Equatable, Identifiable, Sendable {
  var id: String { "\(tournamentID)-\(roundID)-\(contenderID)-feasibility" }

  var tournamentID: String
  var roundID: String
  var roundTitle: String
  var contenderID: String
  var contenderTitle: String
  var solutionID: String
  var solutionTitle: String
  var experimentID: String
  var experimentTitle: String
  var branchName: String
  var worktreeID: String
  var scenarioCohortIDs: [String]
  var planReadinessScore: Double?
  var planRecommendation: ProductTournamentPlanRecommendation?
  var planEvaluationIDs: [String]
  var feasibilityGoal: String
  var coreTechnologyProof: String
  var acceptanceSignals: [String]
  var riskFocus: String

  var scoreLabel: String {
    guard let planReadinessScore else { return "n/a" }
    return "\(Int(planReadinessScore.rounded()))"
  }

  var digestLine: String {
    let cohorts =
      scenarioCohortIDs.isEmpty ? "no cohorts" : scenarioCohortIDs.joined(separator: ", ")
    let plan =
      planRecommendation.map {
        "plan_readiness \(scoreLabel)/100, recommendation \($0.rawValue)"
      } ?? "no Round 1 readiness"
    let evaluations =
      planEvaluationIDs.isEmpty
      ? "no plan evaluations"
      : "plan_evidence \(planEvaluationIDs.prefix(4).joined(separator: ", "))"
    return
      "- round_2_feasibility contender \(contenderID) [solution \(solutionID), experiment \(experimentID), branch \(branchName), worktree \(worktreeID), cohorts \(cohorts), \(plan), \(evaluations)]: proof \(coreTechnologyProof); acceptance \(acceptanceSignals.prefix(4).joined(separator: "; ")); risk \(riskFocus)."
  }

  var implementationTargetLine: String {
    let cohorts =
      scenarioCohortIDs.isEmpty ? "no cohorts" : scenarioCohortIDs.joined(separator: ", ")
    let acceptance =
      acceptanceSignals.isEmpty
      ? "no acceptance signals"
      : acceptanceSignals.prefix(4).joined(separator: "; ")
    return
      "- round_2_implementation_target selected_experiment \(experimentID) [tournament \(tournamentID), round \(roundID), only_contender \(contenderID), solution \(solutionID), branch \(branchName), worktree \(worktreeID), cohorts \(cohorts), do_not_build_competing_contenders true]: core_technology_proof \(coreTechnologyProof); acceptance \(acceptance); risk \(riskFocus)."
  }
}

enum ProductTournamentFeasibilityAdvisor {
  static func handoffs(
    tournamentID: String? = nil,
    config: ProductizationConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentFeasibilityHandoff] {
    activeCoreTechnologyRounds(tournamentID: tournamentID, config: config)
      .flatMap { tournament, round in
        handoffs(for: tournament, round: round, config: config, evidenceIndex: evidenceIndex)
      }
      .sorted { lhs, rhs in
        let lhsScore = lhs.planReadinessScore ?? -1
        let rhsScore = rhs.planReadinessScore ?? -1
        if lhsScore == rhsScore { return lhs.contenderID < rhs.contenderID }
        return lhsScore > rhsScore
      }
  }

  private static func handoffs(
    for tournament: ProductTournament,
    round: ProductTournamentRound,
    config: ProductizationConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentFeasibilityHandoff] {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.compactMap { contenderID in
      guard
        let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
        contender.status == .narrowed || contender.status == .needsRevision,
        let solution = config.solutionHypotheses.first(where: { $0.id == contender.solutionID }),
        let experimentID = contender.experimentID,
        let experiment = config.experiments.first(where: { $0.id == experimentID })
      else { return nil }

      let readiness = evidenceIndex.aggregate.planReadinessByContender.first {
        $0.contenderID == contender.id && $0.tournamentID == tournament.id
      }
      let scenarioCohortIDs =
        round.scenarioCohortIDs.isEmpty ? experiment.scenarioCohortIDs : round.scenarioCohortIDs
      let acceptanceSignals = acceptanceSignals(for: round, solution: solution)
      return ProductTournamentFeasibilityHandoff(
        tournamentID: tournament.id,
        roundID: round.id,
        roundTitle: round.title,
        contenderID: contender.id,
        contenderTitle: contender.title,
        solutionID: solution.id,
        solutionTitle: solution.title,
        experimentID: experiment.id,
        experimentTitle: experiment.title,
        branchName: experiment.branchName,
        worktreeID: experiment.worktreeID,
        scenarioCohortIDs: scenarioCohortIDs,
        planReadinessScore: readiness?.readinessScore,
        planRecommendation: readiness?.recommendation,
        planEvaluationIDs: readiness?.evaluationIDs ?? [],
        feasibilityGoal: round.goal,
        coreTechnologyProof: coreTechnologyProof(
          contender: contender,
          solution: solution,
          experiment: experiment,
          round: round
        ),
        acceptanceSignals: acceptanceSignals,
        riskFocus: contender.primaryRisk
      )
    }
  }

  private static func activeCoreTechnologyRounds(
    tournamentID: String?,
    config: ProductizationConfig
  ) -> [(ProductTournament, ProductTournamentRound)] {
    let tournaments = config.tournaments
      .filter { tournament in
        (tournamentID == nil || tournament.id == tournamentID)
          && (tournament.status == .active || tournament.status == .drafting)
      }
    var pairs: [(ProductTournament, ProductTournamentRound)] = []
    for tournament in tournaments {
      let currentRound = tournament.currentRoundID.flatMap { roundID in
        config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
      }
      if let currentRound, currentRound.kind == .coreTechnology, currentRound.status == .active {
        pairs.append((tournament, currentRound))
        continue
      }
      guard tournament.currentRoundID == nil else { continue }
      if let activeRound = config.tournamentRounds
        .filter({
          $0.tournamentID == tournament.id && $0.kind == .coreTechnology && $0.status == .active
        })
        .sorted(by: { $0.ordinal < $1.ordinal })
        .first
      {
        pairs.append((tournament, activeRound))
      }
    }
    return pairs
  }

  private static func acceptanceSignals(
    for round: ProductTournamentRound,
    solution: SolutionHypothesis
  ) -> [String] {
    let signals =
      round.evaluationFocus
      + solution.requiredProof
      + [
        "The core technology proves the hard part before Round 3 prototype polish.",
        "The surviving contender is tested against the current workaround.",
      ]
    return signals.productTournamentUniquedPreservingOrder().prefix(8).map { $0 }
  }

  private static func coreTechnologyProof(
    contender: ProductTournamentContender,
    solution: SolutionHypothesis,
    experiment: ProductExperiment,
    round: ProductTournamentRound
  ) -> String {
    let proof = solution.requiredProof.first ?? round.evaluationFocus.first ?? round.goal
    return StringUtils.boundedText(
      "Build only \(experiment.title) for \(contender.title): \(experiment.prototypeScope). Prove \(proof) before adding Round 3 fidelity.",
      limit: 360
    )
  }
}

extension Array where Element == String {
  fileprivate func productTournamentUniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      out.append(trimmed)
    }
    return out
  }
}
