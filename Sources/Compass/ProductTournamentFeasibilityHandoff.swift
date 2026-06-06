import Foundation

struct ProductTournamentImplementationTrackBrief: Codable, Equatable, Sendable {
  var scopeSummary: String
  var expectedEvidenceSignal: String?
  var killCriteria: String?

  var isCandidateDerived: Bool {
    expectedEvidenceSignal != nil || killCriteria != nil
  }

  var contextFragments: [String] {
    var fragments: [String] = []
    if let expectedEvidenceSignal {
      fragments.append("expected_evidence \(expectedEvidenceSignal)")
    }
    if let killCriteria {
      fragments.append("kill_criteria \(killCriteria)")
    }
    fragments.append("implementation_scope \(scopeSummary)")
    return fragments
  }

  init(experiment: ProductTournamentExperiment) {
    self = Self.parse(experiment.implementationScope)
  }

  private init(
    scopeSummary: String,
    expectedEvidenceSignal: String?,
    killCriteria: String?
  ) {
    self.scopeSummary = scopeSummary
    self.expectedEvidenceSignal = expectedEvidenceSignal
    self.killCriteria = killCriteria
  }

  private static func parse(_ value: String) -> ProductTournamentImplementationTrackBrief {
    let expectedMarker = "Expected evidence:"
    let killMarker = "Kill or reframe if:"
    let expectedRange = value.range(of: expectedMarker)
    let killRange = value.range(of: killMarker)
    let firstMarker = [expectedRange, killRange]
      .compactMap { $0 }
      .sorted { $0.lowerBound < $1.lowerBound }
      .first
    let scopeSummary = cleaned(
      firstMarker.map { String(value[..<$0.lowerBound]) } ?? value,
      fallback: "Smallest product implementation needed for evidence",
      limit: 500
    )
    let expectedEvidenceSignal: String?
    if let expectedRange {
      let end = killRange?.lowerBound ?? value.endIndex
      expectedEvidenceSignal = optionalCleaned(
        String(value[expectedRange.upperBound..<end]),
        limit: 500
      )
    } else {
      expectedEvidenceSignal = nil
    }
    let killCriteria = killRange.map {
      optionalCleaned(String(value[$0.upperBound...]), limit: 500)
    } ?? nil
    return ProductTournamentImplementationTrackBrief(
      scopeSummary: scopeSummary,
      expectedEvidenceSignal: expectedEvidenceSignal,
      killCriteria: killCriteria
    )
  }

  private static func cleaned(_ value: String, fallback: String, limit: Int) -> String {
    optionalCleaned(value, limit: limit) ?? fallback
  }

  private static func optionalCleaned(_ value: String, limit: Int) -> String? {
    let trimmed = value.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;"))
    )
    let bounded = StringUtils.boundedText(trimmed, limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}

struct ProductTournamentFeasibilityHandoff: Codable, Equatable, Identifiable, Sendable {
  var id: String { "\(tournamentID)-\(roundID)-\(contenderID)-feasibility" }

  var tournamentID: String
  var roundID: String
  var roundTitle: String
  var contenderID: String
  var contenderTitle: String
  var contenderPlanID: String
  var contenderPlanTitle: String
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
  var implementationBrief: ProductTournamentImplementationTrackBrief

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
    let implementation = implementationBrief.contextFragments.prefix(3).joined(separator: "; ")
    return
      "- round_2_feasibility contender \(contenderID) [contender_plan \(contenderPlanID), experiment \(experimentID), branch \(branchName), worktree \(worktreeID), cohorts \(cohorts), \(plan), \(evaluations)]: \(implementation); proof \(coreTechnologyProof); acceptance \(acceptanceSignals.prefix(4).joined(separator: "; ")); risk \(riskFocus)."
  }

  var implementationTargetLine: String {
    let cohorts =
      scenarioCohortIDs.isEmpty ? "no cohorts" : scenarioCohortIDs.joined(separator: ", ")
    let acceptance =
      acceptanceSignals.isEmpty
      ? "no acceptance signals"
      : acceptanceSignals.prefix(4).joined(separator: "; ")
    let implementation = implementationBrief.contextFragments.prefix(3).joined(separator: "; ")
    return
      "- round_2_implementation_target selected_experiment \(experimentID) [tournament \(tournamentID), round \(roundID), only_contender \(contenderID), contender_plan \(contenderPlanID), branch \(branchName), worktree \(worktreeID), cohorts \(cohorts), do_not_build_competing_contenders true]: \(implementation); core_technology_proof \(coreTechnologyProof); acceptance \(acceptance); risk \(riskFocus)."
  }
}

enum ProductTournamentFeasibilityAdvisor {
  static func handoffs(
    tournamentID: String? = nil,
    config: ProductTournamentConfig,
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
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentFeasibilityHandoff] {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.compactMap { contenderID in
      guard
        let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
        contender.status == .narrowed || contender.status == .needsRevision,
        let contenderPlan = config.contenderPlans.first(where: { $0.id == contender.contenderPlanID }),
        let experimentID = contender.experimentID,
        let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
      else { return nil }

      let readiness = evidenceIndex.aggregate.planReadinessByContender.first {
        $0.contenderID == contender.id && $0.tournamentID == tournament.id
      }
      let scenarioCohortIDs =
        round.scenarioCohortIDs.isEmpty ? experiment.scenarioCohortIDs : round.scenarioCohortIDs
      let implementationBrief = ProductTournamentImplementationTrackBrief(experiment: experiment)
      let acceptanceSignals = acceptanceSignals(
        for: round,
        contenderPlan: contenderPlan,
        implementationBrief: implementationBrief
      )
      return ProductTournamentFeasibilityHandoff(
        tournamentID: tournament.id,
        roundID: round.id,
        roundTitle: round.title,
        contenderID: contender.id,
        contenderTitle: contender.title,
        contenderPlanID: contenderPlan.id,
        contenderPlanTitle: contenderPlan.title,
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
          contenderPlan: contenderPlan,
          experiment: experiment,
          round: round
        ),
        acceptanceSignals: acceptanceSignals,
        riskFocus: contender.primaryRisk,
        implementationBrief: implementationBrief
      )
    }
  }

  private static func activeCoreTechnologyRounds(
    tournamentID: String?,
    config: ProductTournamentConfig
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
    contenderPlan: ProductTournamentContenderPlan,
    implementationBrief: ProductTournamentImplementationTrackBrief
  ) -> [String] {
    let signals =
      round.evaluationFocus
      + contenderPlan.requiredProof
      + [implementationBrief.expectedEvidenceSignal].compactMap { $0 }
      + [
        "The core technology proves the hard part before Round 3 product implementation fidelity.",
        "The surviving contender is tested against the current workaround.",
      ]
    return signals.productTournamentUniquedPreservingOrder().prefix(8).map { $0 }
  }

  private static func coreTechnologyProof(
    contender: ProductTournamentContender,
    contenderPlan: ProductTournamentContenderPlan,
    experiment: ProductTournamentExperiment,
    round: ProductTournamentRound
  ) -> String {
    let proof = contenderPlan.requiredProof.first ?? round.evaluationFocus.first ?? round.goal
    let implementationBrief = ProductTournamentImplementationTrackBrief(experiment: experiment)
    return StringUtils.boundedText(
      "Build only \(experiment.title) for \(contender.title): \(implementationBrief.scopeSummary). Prove \(proof) before adding Round 3 fidelity.",
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
