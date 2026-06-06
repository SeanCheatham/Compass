import Foundation

struct ProductTournamentEvidenceScope: Codable, Equatable, Sendable {
  var tournamentID: String
  var roundID: String
  var contenderID: String

  init(tournamentID: String, roundID: String, contenderID: String) {
    self.tournamentID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      tournamentID,
      fallback: "tournament"
    )
    self.roundID = ProductTournamentEvidenceRecord.cleanedIdentifier(roundID, fallback: "round")
    self.contenderID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      contenderID,
      fallback: "contender"
    )
  }
}

enum ProductTournamentEvidenceScopeResolver {
  static func scope(
    experimentID: String,
    in config: ProductTournamentConfig
  ) -> ProductTournamentEvidenceScope? {
    guard
      let contender = config.tournamentContenders.first(where: {
        $0.experimentID == experimentID && $0.isGeneratedProductEvidenceCandidate
      }),
      let tournament = config.tournaments.first(where: {
        $0.id == contender.tournamentID && ($0.status == .active || $0.status == .drafting)
      }),
      let round = activeBuiltProductRound(
        for: tournament, contenderID: contender.id, config: config)
    else { return nil }

    return ProductTournamentEvidenceScope(
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id
    )
  }

  private static func activeBuiltProductRound(
    for tournament: ProductTournament,
    contenderID: String,
    config: ProductTournamentConfig
  ) -> ProductTournamentRound? {
    let currentRound = tournament.currentRoundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
    }
    if let currentRound,
      currentRound.status == .active,
      currentRound.requiresBuiltProduct,
      currentRound.includes(contenderID: contenderID)
    {
      return currentRound
    }

    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id
          && $0.status == .active
          && $0.requiresBuiltProduct
          && $0.includes(contenderID: contenderID)
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
        return lhs.ordinal < rhs.ordinal
      }
      .first
  }
}

extension ProductTournamentContender {
  fileprivate var isGeneratedProductEvidenceCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision, .winner:
      return true
    case .competing, .eliminated, .archived:
      return false
    }
  }
}

extension ProductTournamentRound {
  fileprivate func includes(contenderID: String) -> Bool {
    contenderIDs.isEmpty || contenderIDs.contains(contenderID)
  }
}
