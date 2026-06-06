import Foundation

struct ProductTournamentPlanTransitionProposal: Codable, Equatable, Identifiable, Sendable {
  var id: String {
    "\(tournamentID)-\(roundID)-\(contenderID)-\(recommendation.rawValue)"
  }

  var tournamentID: String
  var roundID: String
  var contenderID: String
  var contenderTitle: String
  var recommendation: ProductTournamentPlanRecommendation
  var readinessScore: Double
  var priority: Int
  var title: String
  var detail: String

  var isActionable: Bool {
    switch recommendation {
    case .advanceToFeasibility, .revisePlan, .eliminate:
      return true
    case .gatherEvidence:
      return false
    }
  }
}

struct ProductTournamentPlanTransitionOutcome: Equatable, Sendable {
  var proposal: ProductTournamentPlanTransitionProposal
  var config: ProductTournamentConfig
  var affectedContenderIDs: [String]
  var fromRoundID: String
  var toRoundID: String?

  var userMessage: String {
    switch proposal.recommendation {
    case .advanceToFeasibility:
      return
        "Advanced \(proposal.contenderTitle) to Round 2 feasibility from Round 1 plan evidence."
    case .revisePlan:
      return "Marked \(proposal.contenderTitle) for Round 1 plan revision."
    case .eliminate:
      return "Eliminated \(proposal.contenderTitle) from future tournament rounds."
    case .gatherEvidence:
      return "Round 1 still needs more plan evidence for \(proposal.contenderTitle)."
    }
  }
}

enum ProductTournamentPlanTransitionError: LocalizedError, Equatable {
  case unknownTournament(String)
  case unknownRound(String)
  case unknownContender(String)
  case missingPlanReadiness(String)
  case recommendationNotActionable(String, ProductTournamentPlanRecommendation)
  case missingFeasibilityRound(String)

  var errorDescription: String? {
    switch self {
    case .unknownTournament(let id):
      return "Product tournament \(id) was not found."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unknownContender(let id):
      return "Product tournament contender \(id) was not found."
    case .missingPlanReadiness(let contenderID):
      return "No Round 1 plan readiness exists for contender \(contenderID)."
    case .recommendationNotActionable(let contenderID, let recommendation):
      return
        "Round 1 recommendation \(recommendation.rawValue) for contender \(contenderID) is not a tournament transition."
    case .missingFeasibilityRound(let tournamentID):
      return "Product tournament \(tournamentID) has no Round 2 feasibility round."
    }
  }
}

enum ProductTournamentPlanTransitioner {
  static func proposals(
    tournamentID: String? = nil,
    roundID: String? = nil,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentPlanTransitionProposal] {
    guard
      let tournament = selectedTournament(tournamentID: tournamentID, config: config),
      let planRound = selectedPlanRound(roundID: roundID, tournament: tournament, config: config)
    else { return [] }

    let contenderIDs = Set(
      planRound.contenderIDs.isEmpty ? tournament.contenderIDs : planRound.contenderIDs)
    return evidenceIndex.aggregate.planReadinessByContender
      .filter {
        $0.tournamentID == tournament.id
          && $0.roundID == planRound.id
          && contenderIDs.contains($0.contenderID)
      }
      .compactMap { readiness in
        guard
          let contender = config.tournamentContenders.first(where: {
            $0.id == readiness.contenderID
          }),
          contender.isRoundOneTransitionCandidate
        else { return nil }
        return proposal(for: readiness, contender: contender)
      }
      .sorted { lhs, rhs in
        if lhs.priority == rhs.priority {
          if lhs.readinessScore == rhs.readinessScore { return lhs.contenderID < rhs.contenderID }
          return lhs.readinessScore > rhs.readinessScore
        }
        return lhs.priority > rhs.priority
      }
  }

  static func bestProposal(
    tournamentID: String? = nil,
    roundID: String? = nil,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentPlanTransitionProposal? {
    proposals(
      tournamentID: tournamentID,
      roundID: roundID,
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first(where: \.isActionable)
  }

  static func applyBestProposal(
    tournamentID: String? = nil,
    roundID: String? = nil,
    to config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    now: Date = Date()
  ) throws -> ProductTournamentPlanTransitionOutcome {
    guard
      let proposal = bestProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else {
      let contenderID =
        selectedTournament(tournamentID: tournamentID, config: config)?.contenderIDs.first
        ?? "unknown"
      throw ProductTournamentPlanTransitionError.missingPlanReadiness(contenderID)
    }
    return try apply(proposal: proposal, to: config, now: now)
  }

  static func apply(
    proposal: ProductTournamentPlanTransitionProposal,
    to config: ProductTournamentConfig,
    now: Date = Date()
  ) throws -> ProductTournamentPlanTransitionOutcome {
    guard proposal.isActionable else {
      throw ProductTournamentPlanTransitionError.recommendationNotActionable(
        proposal.contenderID,
        proposal.recommendation
      )
    }
    guard let tournament = config.tournaments.first(where: { $0.id == proposal.tournamentID })
    else {
      throw ProductTournamentPlanTransitionError.unknownTournament(proposal.tournamentID)
    }
    guard let round = config.tournamentRounds.first(where: { $0.id == proposal.roundID })
    else {
      throw ProductTournamentPlanTransitionError.unknownRound(proposal.roundID)
    }
    guard config.tournamentContenders.contains(where: { $0.id == proposal.contenderID }) else {
      throw ProductTournamentPlanTransitionError.unknownContender(proposal.contenderID)
    }

    var next = config
    let timestamp = now.timeIntervalSince1970
    let destinationRoundID: String?

    switch proposal.recommendation {
    case .advanceToFeasibility:
      let feasibilityRound = try roundTwoFeasibilityRound(
        for: tournament, after: round, config: config)
      destinationRoundID = feasibilityRound.id
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.currentRoundID = feasibilityRound.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .completed
      }
      updateRound(feasibilityRound.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
        round.contenderIDs = [proposal.contenderID]
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .narrowed
      }
      activateSolution(for: proposal.contenderID, in: &next, timestamp: timestamp)

    case .revisePlan:
      destinationRoundID = nil
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.currentRoundID = round.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .needsRevision
      }

    case .eliminate:
      destinationRoundID = nil
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .eliminated
      }
      for futureRound in next.tournamentRounds
      where futureRound.tournamentID == tournament.id
        && futureRound.ordinal > round.ordinal
      {
        updateRound(futureRound.id, in: &next, timestamp: timestamp) { round in
          round.contenderIDs.removeAll { $0 == proposal.contenderID }
        }
      }
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.currentRoundID = round.id
      }

    case .gatherEvidence:
      destinationRoundID = nil
    }

    return ProductTournamentPlanTransitionOutcome(
      proposal: proposal,
      config: next,
      affectedContenderIDs: [proposal.contenderID],
      fromRoundID: round.id,
      toRoundID: destinationRoundID
    )
  }

  private static func proposal(
    for readiness: ProductTournamentPlanReadiness,
    contender: ProductTournamentContender
  ) -> ProductTournamentPlanTransitionProposal {
    let priority = priority(for: readiness)
    let title: String
    let detail: String
    switch readiness.recommendation {
    case .advanceToFeasibility:
      title = "Advance to Round 2"
      detail =
        "Readiness \(readiness.scoreLabel)/100 with willingness to pay \(formatScore(readiness.averageWillingnessToPayScore))/5. Commercial proof: \(readiness.commercialProofSummary)."
    case .revisePlan:
      title = "Mark for Plan Revision"
      detail =
        "Readiness \(readiness.scoreLabel)/100; revise objections before implementation. Commercial proof: \(readiness.commercialProofSummary). Next proof target: \(readiness.nextProofTargetSummary)."
    case .eliminate:
      title = "Eliminate Contender"
      detail =
        "Readiness \(readiness.scoreLabel)/100 is too weak for more implementation spend."
    case .gatherEvidence:
      title = "Gather More Evidence"
      detail =
        "Readiness \(readiness.scoreLabel)/100 needs more plan evaluations before a transition: \(readiness.planProofDebt.summary). Commercial proof: \(readiness.commercialProofSummary). Next proof target: \(readiness.nextProofTargetSummary)."
    }
    return ProductTournamentPlanTransitionProposal(
      tournamentID: readiness.tournamentID,
      roundID: readiness.roundID,
      contenderID: readiness.contenderID,
      contenderTitle: contender.title,
      recommendation: readiness.recommendation,
      readinessScore: readiness.readinessScore,
      priority: priority,
      title: title,
      detail: detail
    )
  }

  private static func priority(for readiness: ProductTournamentPlanReadiness) -> Int {
    switch readiness.recommendation {
    case .advanceToFeasibility:
      return 10_000 + Int(readiness.readinessScore.rounded())
    case .eliminate:
      return 8_000 + Int((100 - readiness.readinessScore).rounded())
    case .revisePlan:
      return 6_000 + Int((100 - readiness.readinessScore).rounded())
    case .gatherEvidence:
      return Int(readiness.readinessScore.rounded())
    }
  }

  private static func selectedTournament(
    tournamentID: String?,
    config: ProductTournamentConfig
  ) -> ProductTournament? {
    if let tournamentID {
      return config.tournaments.first { $0.id == tournamentID }
    }
    return config.tournaments
      .filter { $0.status == .active || $0.status == .drafting }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return lhs.status == .active
      }
      .first
  }

  private static func selectedPlanRound(
    roundID: String?,
    tournament: ProductTournament,
    config: ProductTournamentConfig
  ) -> ProductTournamentRound? {
    if let roundID {
      return config.tournamentRounds.first {
        $0.id == roundID && $0.tournamentID == tournament.id && $0.kind == .productPlans
      }
    }
    if let currentRoundID = tournament.currentRoundID,
      let current = config.tournamentRounds.first(where: { $0.id == currentRoundID }),
      current.kind == .productPlans,
      current.status != .completed
    {
      return current
    }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id && $0.kind == .productPlans && $0.status != .completed
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
        return lhs.ordinal < rhs.ordinal
      }
      .first
  }

  private static func roundTwoFeasibilityRound(
    for tournament: ProductTournament,
    after round: ProductTournamentRound,
    config: ProductTournamentConfig
  ) throws -> ProductTournamentRound {
    let rounds = tournament.roundIDs.compactMap { roundID in
      config.tournamentRounds.first { $0.id == roundID }
    }
    if let feasibility = rounds.first(where: {
      $0.kind == .coreTechnology && $0.ordinal > round.ordinal
    }) {
      return feasibility
    }
    throw ProductTournamentPlanTransitionError.missingFeasibilityRound(tournament.id)
  }

  private static func updateTournament(
    _ tournamentID: String,
    in config: inout ProductTournamentConfig,
    timestamp: Double,
    mutate: (inout ProductTournament) -> Void
  ) {
    guard let index = config.tournaments.firstIndex(where: { $0.id == tournamentID }) else {
      return
    }
    mutate(&config.tournaments[index])
    config.tournaments[index].updatedAt = timestamp
  }

  private static func updateRound(
    _ roundID: String,
    in config: inout ProductTournamentConfig,
    timestamp: Double,
    mutate: (inout ProductTournamentRound) -> Void
  ) {
    guard let index = config.tournamentRounds.firstIndex(where: { $0.id == roundID }) else {
      return
    }
    mutate(&config.tournamentRounds[index])
    config.tournamentRounds[index].updatedAt = timestamp
  }

  private static func updateContender(
    _ contenderID: String,
    in config: inout ProductTournamentConfig,
    timestamp: Double,
    mutate: (inout ProductTournamentContender) -> Void
  ) {
    guard let index = config.tournamentContenders.firstIndex(where: { $0.id == contenderID }) else {
      return
    }
    mutate(&config.tournamentContenders[index])
    config.tournamentContenders[index].updatedAt = timestamp
  }

  private static func activateSolution(
    for contenderID: String,
    in config: inout ProductTournamentConfig,
    timestamp _: Double
  ) {
    guard
      let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
      let index = config.solutionHypotheses.firstIndex(where: { $0.id == contender.solutionID })
    else { return }
    config.solutionHypotheses[index].status = .active
  }

  private static func formatScore(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

extension ProductTournamentContender {
  fileprivate var isRoundOneTransitionCandidate: Bool {
    switch status {
    case .competing, .narrowed, .needsRevision:
      return true
    case .eliminated, .winner, .archived:
      return false
    }
  }
}
