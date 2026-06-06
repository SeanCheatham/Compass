import Foundation

struct TournamentAutomationProofTargetScoreboardRow: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var contenderID: String?
  var contenderTitle: String
  var targetLabel: String
  var readinessScore: Int
  var urgencyScore: Int
  var debtSummary: String
  var nextActionTitle: String?
  var tournamentPositionSummary: String?

  var displaySummary: String {
    var parts = [
      targetLabel,
      "score \(readinessScore)/100",
    ]
    if let nextActionTitle {
      parts.append("next \(nextActionTitle)")
    }
    if let tournamentPositionSummary {
      parts.append(tournamentPositionSummary)
    }
    return parts.joined(separator: " - ")
  }

  var contextSummary: String {
    var parts = [
      "contender \(contenderID ?? experimentID)",
      "target \(targetLabel)",
      "score \(readinessScore)/100",
      "debt \(StringUtils.boundedText(debtSummary, limit: 120))",
    ]
    if let nextActionTitle {
      parts.append("next \(StringUtils.boundedText(nextActionTitle, limit: 80))")
    }
    if let tournamentPositionSummary {
      parts.append("position \(StringUtils.boundedText(tournamentPositionSummary, limit: 120))")
    }
    return parts.joined(separator: "; ")
  }
}

struct TournamentAutomationProofTargetScoreboardItem: Equatable, Sendable, Identifiable {
  var id: String { "\(tournamentID ?? "unknown-tournament"):\(roundID ?? "unknown-round")" }

  var tournamentID: String?
  var roundID: String?
  var roundTitle: String
  var contenderCount: Int
  var rows: [TournamentAutomationProofTargetScoreboardRow]

  var targetCount: Int { rows.count }

  var displayTitle: String {
    roundTitle
  }

  var displaySubtitle: String {
    "\(targetCount)/\(contenderCount) contender proof target(s)"
  }

  var displayDetail: String {
    guard !rows.isEmpty else { return "No proof targets queued for this round." }
    return rows.prefix(4)
      .map { "\($0.contenderTitle): \($0.targetLabel)" }
      .joined(separator: "; ")
  }

  var workbenchAccessibilityID: String {
    "proof-target-scoreboard-\(roundID ?? "unknown-round")"
  }

  var contextLine: String {
    let rowText = rows.prefix(4).map(\.contextSummary).joined(separator: " | ")
    return "- proof_target_scoreboard \(roundID ?? "unknown_round") [tournament \(tournamentID ?? "unknown_tournament"), targets \(targetCount)/\(contenderCount)]: \(StringUtils.boundedText(rowText, limit: 420))."
  }
}

enum TournamentAutomationProofTargetScoreboard {
  static func items(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 4,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [TournamentAutomationProofTargetScoreboardItem] {
    guard limit > 0 else { return [] }
    let targets = TournamentAutomationProofTargetAdvisor.targets(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    guard !targets.isEmpty else { return [] }

    let grouped = Dictionary(grouping: targets) { target in
      scopeKey(for: target, config: config)
    }
    return grouped.map { key, targets in
      item(for: key, targets: targets, config: config)
    }
    .sorted { lhs, rhs in
      let lhsMaxUrgency = lhs.rows.map(\.urgencyScore).max() ?? 0
      let rhsMaxUrgency = rhs.rows.map(\.urgencyScore).max() ?? 0
      if lhsMaxUrgency == rhsMaxUrgency {
        if lhs.targetCount == rhs.targetCount {
          return lhs.displayTitle < rhs.displayTitle
        }
        return lhs.targetCount > rhs.targetCount
      }
      return lhsMaxUrgency > rhsMaxUrgency
    }
    .prefix(limit)
    .map { $0 }
  }

  static func contextLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [String] {
    let items = items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: limit,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    guard !items.isEmpty else { return [] }
    return ["Tournament automation proof scoreboard:"] + items.map(\.contextLine)
  }

  private struct ScopeKey: Hashable {
    var tournamentID: String?
    var roundID: String?
  }

  private static func item(
    for key: ScopeKey,
    targets: [TournamentAutomationProofTarget],
    config: ProductTournamentConfig
  ) -> TournamentAutomationProofTargetScoreboardItem {
    let tournament = key.tournamentID.flatMap { tournamentID in
      config.tournaments.first { $0.id == tournamentID }
    }
    let round = key.roundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID }
    }
    let contenderCount = max(
      1,
      activeContenderCount(round: round, tournament: tournament, config: config)
    )
    let rows = targets
      .map { row(for: $0, config: config) }
      .sorted {
        if $0.urgencyScore == $1.urgencyScore {
          return $0.contenderTitle < $1.contenderTitle
        }
        return $0.urgencyScore > $1.urgencyScore
      }
    return TournamentAutomationProofTargetScoreboardItem(
      tournamentID: key.tournamentID,
      roundID: key.roundID,
      roundTitle: round?.title ?? "Tournament proof targets",
      contenderCount: contenderCount,
      rows: rows
    )
  }

  private static func row(
    for target: TournamentAutomationProofTarget,
    config: ProductTournamentConfig
  ) -> TournamentAutomationProofTargetScoreboardRow {
    let contender = target.contenderID.flatMap { contenderID in
      config.tournamentContenders.first { $0.id == contenderID }
    }
    return TournamentAutomationProofTargetScoreboardRow(
      experimentID: target.experimentID,
      contenderID: target.contenderID,
      contenderTitle: contender?.title ?? target.contenderID ?? target.experimentID,
      targetLabel: target.label,
      readinessScore: target.readinessScore,
      urgencyScore: target.urgencyScore,
      debtSummary: target.debtSummary,
      nextActionTitle: target.nextActionTitle,
      tournamentPositionSummary: target.tournamentPositionSummary
    )
  }

  private static func scopeKey(
    for target: TournamentAutomationProofTarget,
    config: ProductTournamentConfig
  ) -> ScopeKey {
    let contender = target.contenderID.flatMap { contenderID in
      config.tournamentContenders.first { $0.id == contenderID }
    } ?? config.tournamentContenders.first { $0.experimentID == target.experimentID }
    let tournamentID = target.tournamentID ?? contender?.tournamentID
    let tournament = tournamentID.flatMap { id in config.tournaments.first { $0.id == id } }
    let roundID = target.roundID ?? tournament?.currentRoundID
    return ScopeKey(tournamentID: tournamentID, roundID: roundID)
  }

  private static func activeContenderCount(
    round: ProductTournamentRound?,
    tournament: ProductTournament?,
    config: ProductTournamentConfig
  ) -> Int {
    let roundContenderIDs: [String]
    if let round, !round.contenderIDs.isEmpty {
      roundContenderIDs = round.contenderIDs
    } else {
      roundContenderIDs = tournament?.contenderIDs ?? []
    }
    let contendersByID = Dictionary(
      uniqueKeysWithValues: config.tournamentContenders.map { ($0.id, $0) }
    )
    let roundContenders = roundContenderIDs.compactMap { contendersByID[$0] }
    let active = roundContenders.filter { contender in
      switch contender.status {
      case .competing, .narrowed, .needsRevision:
        return true
      case .eliminated, .winner, .archived:
        return false
      }
    }
    return active.isEmpty ? roundContenders.count : active.count
  }
}
