import Foundation

/// Drift between parallel tournament status fields in ``ProductTournamentConfig``.
///
/// V1 config stores lifecycle state in several places:
/// - ``ProductTournament/currentRoundID`` and ``ProductTournamentRound/status``
/// - ``ProductTournamentContender/status`` and ``ProductTournamentContenderPlan/status``
/// - ``PainHypothesis/status`` alongside ``ProductTournament/status``
///
/// ``ProductTournamentStateV2`` is the consolidated read model used for Rust
/// cutover; these checks keep the legacy config honest until that migration lands.
enum ProductTournamentConfigStatusIssue: Equatable, Sendable {
  case currentRoundNotActive(
    tournamentID: String,
    roundID: String,
    status: ProductTournamentRoundStatus
  )
  case multipleActiveRounds(tournamentID: String, roundIDs: [String])
  case activeRoundPointerMismatch(
    tournamentID: String,
    currentRoundID: String,
    activeRoundID: String
  )
}

enum ProductTournamentConfigStatusConsistency {
  static func issues(in config: ProductTournamentConfig) -> [ProductTournamentConfigStatusIssue] {
    config.tournaments.flatMap { issues(for: $0, in: config) }
  }

  static func issues(
    for tournament: ProductTournament,
    in config: ProductTournamentConfig
  ) -> [ProductTournamentConfigStatusIssue] {
    guard tournament.status == .active || tournament.status == .drafting else {
      return []
    }

    let rounds = tournament.roundIDs.compactMap { roundID in
      config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
    }
    let activeRounds = rounds.filter { $0.status == .active }
    var issues: [ProductTournamentConfigStatusIssue] = []

    if activeRounds.count > 1 {
      issues.append(
        .multipleActiveRounds(
          tournamentID: tournament.id,
          roundIDs: activeRounds.map(\.id).sorted()
        )
      )
    }

    if let currentRoundID = tournament.currentRoundID {
      if let currentRound = rounds.first(where: { $0.id == currentRoundID }) {
        if currentRound.status != .active {
          issues.append(
            .currentRoundNotActive(
              tournamentID: tournament.id,
              roundID: currentRoundID,
              status: currentRound.status
            )
          )
        }
      }

      if activeRounds.count == 1,
        let activeRoundID = activeRounds.first?.id,
        activeRoundID != currentRoundID
      {
        issues.append(
          .activeRoundPointerMismatch(
            tournamentID: tournament.id,
            currentRoundID: currentRoundID,
            activeRoundID: activeRoundID
          )
        )
      }
    }

    return issues
  }
}
