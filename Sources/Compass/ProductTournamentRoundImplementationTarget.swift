import Foundation

struct ProductTournamentRoundImplementationTarget: Equatable, Sendable {
  var tournamentID: String
  var roundID: String
  var contenderID: String
  var experimentID: String
}

enum ProductTournamentRoundImplementationTargetResolver {
  static func defaultActiveRoundTwoTarget(
    in config: ProductTournamentConfig
  ) -> ProductTournamentRoundImplementationTarget? {
    let targets = activeRoundTwoTargets(in: config)
    guard targets.count == 1 else { return nil }
    return targets[0]
  }

  static func activeRoundTwoTargets(
    in config: ProductTournamentConfig
  ) -> [ProductTournamentRoundImplementationTarget] {
    config.tournaments
      .filter { $0.status == .active || $0.status == .drafting }
      .compactMap { roundTwoTarget(tournamentID: $0.id, in: config) }
      .sorted { lhs, rhs in
        if lhs.tournamentID == rhs.tournamentID { return lhs.roundID < rhs.roundID }
        return lhs.tournamentID < rhs.tournamentID
      }
  }

  static func roundTwoTarget(
    forExperimentInTargetTournament experimentID: String,
    in config: ProductTournamentConfig
  ) -> ProductTournamentRoundImplementationTarget? {
    guard
      let contender = config.tournamentContenders.first(where: {
        $0.experimentID == experimentID
      })
    else { return nil }

    return roundTwoTarget(tournamentID: contender.tournamentID, in: config)
  }

  static func activeRoundTwoTargetBlockingExperiment(
    _ experimentID: String,
    in config: ProductTournamentConfig
  ) -> ProductTournamentRoundImplementationTarget? {
    guard
      let target = roundTwoTarget(
        forExperimentInTargetTournament: experimentID,
        in: config
      ),
      target.experimentID != experimentID
    else { return nil }
    return target
  }

  static func blocksEvidenceLaunch(
    experimentID: String,
    in config: ProductTournamentConfig
  ) -> Bool {
    activeRoundTwoTargetBlockingExperiment(experimentID, in: config) != nil
  }

  static func blockedSiblingExperimentIDs(
    for target: ProductTournamentRoundImplementationTarget,
    in config: ProductTournamentConfig
  ) -> [String] {
    guard roundTwoTarget(tournamentID: target.tournamentID, in: config) == target else {
      return []
    }
    return config.tournamentContenders
      .filter {
        $0.tournamentID == target.tournamentID
          && $0.experimentID != nil
          && $0.experimentID != target.experimentID
      }
      .compactMap(\.experimentID)
      .sorted()
  }

  static func roundTwoTarget(
    tournamentID: String,
    in config: ProductTournamentConfig
  ) -> ProductTournamentRoundImplementationTarget? {
    guard
      let tournament = config.tournaments.first(where: {
        $0.id == tournamentID && ($0.status == .active || $0.status == .drafting)
      }),
      let round = activeCoreTechnologyRound(for: tournament, in: config)
    else { return nil }

    let candidateIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    let candidates = candidateIDs.compactMap { contenderID in
      config.tournamentContenders.first {
        $0.id == contenderID
          && $0.tournamentID == tournament.id
          && $0.isRoundTwoImplementationCandidate
          && $0.experimentID != nil
      }
    }
    guard candidates.count == 1, let target = candidates.first,
      let targetExperimentID = target.experimentID
    else {
      return nil
    }

    return ProductTournamentRoundImplementationTarget(
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: target.id,
      experimentID: targetExperimentID
    )
  }

  private static func activeCoreTechnologyRound(
    for tournament: ProductTournament,
    in config: ProductTournamentConfig
  ) -> ProductTournamentRound? {
    let currentRound = tournament.currentRoundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
    }
    if let currentRound,
      currentRound.kind == .coreTechnology,
      currentRound.status == .active
    {
      return currentRound
    }
    guard tournament.currentRoundID == nil else { return nil }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id
          && $0.kind == .coreTechnology
          && $0.status == .active
      }
      .sorted {
        if $0.ordinal == $1.ordinal { return $0.id < $1.id }
        return $0.ordinal < $1.ordinal
      }
      .first
  }
}

extension ProductTournamentContender {
  fileprivate var isRoundTwoImplementationCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision:
      return true
    case .competing, .winner, .eliminated, .archived:
      return false
    }
  }
}
