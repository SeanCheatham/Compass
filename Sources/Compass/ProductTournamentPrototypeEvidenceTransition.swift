import Foundation

enum ProductTournamentPrototypeEvidenceRecommendation: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case gatherEvidence = "gather_evidence"
  case selectWinner = "select_winner"
  case revisePrototype = "revise_prototype"
  case eliminate

  var title: String {
    switch self {
    case .gatherEvidence: return "Gather Evidence"
    case .selectWinner: return "Select Winner"
    case .revisePrototype: return "Revise"
    case .eliminate: return "Eliminate"
    }
  }
}

struct ProductTournamentPrototypeEvidenceTransitionProposal: Codable, Equatable, Identifiable,
  Sendable
{
  var id: String {
    "\(tournamentID)-\(roundID)-\(contenderID)-\(recommendation.rawValue)"
  }

  var tournamentID: String
  var roundID: String
  var roundTitle: String
  var contenderID: String
  var contenderTitle: String
  var recommendation: ProductTournamentPrototypeEvidenceRecommendation
  var readinessScore: Double
  var averageScore: Double
  var willingnessToPayScore: Double
  var runCount: Int
  var completedRunCount: Int
  var failedRunCount: Int
  var distinctPersonaCount: Int
  var currentAlternativeProofCount: Int
  var strongOrPromisingCount: Int
  var weakOrRejectedCount: Int
  var missingCapabilityCount: Int
  var evidenceRunIDs: [String]
  var priority: Int
  var title: String
  var detail: String
  var rationale: [String]

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var isActionable: Bool {
    switch recommendation {
    case .selectWinner, .revisePrototype, .eliminate:
      return true
    case .gatherEvidence:
      return false
    }
  }

  var digestLine: String {
    let evidence =
      evidenceRunIDs.isEmpty
      ? "no scoped evidence"
      : "evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))"
    return
      "- round_3_prototype contender \(contenderID) [round \(roundID), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, willingness_to_pay \(Self.format(willingnessToPayScore))/5, completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), current_alternative_proofs \(currentAlternativeProofCount), missing_capabilities \(missingCapabilityCount), \(evidence)]: \(detail)"
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

struct ProductTournamentPrototypeEvidenceTransitionOutcome: Equatable, Sendable {
  var proposal: ProductTournamentPrototypeEvidenceTransitionProposal
  var config: ProductTournamentConfig
  var affectedContenderIDs: [String]
  var fromRoundID: String
  var toRoundID: String?

  var userMessage: String {
    switch proposal.recommendation {
    case .selectWinner:
      return
        "Selected \(proposal.contenderTitle) as the product tournament winner from Round 3 prototype evidence."
    case .revisePrototype:
      return "Marked \(proposal.contenderTitle) for Round 3 prototype revision."
    case .eliminate:
      return "Eliminated \(proposal.contenderTitle) after Round 3 prototype evidence."
    case .gatherEvidence:
      return "Round 3 still needs more prototype evidence for \(proposal.contenderTitle)."
    }
  }
}

enum ProductTournamentPrototypeEvidenceTransitionError: LocalizedError, Equatable {
  case unknownTournament(String)
  case unknownRound(String)
  case unsupportedRound(String)
  case unknownContender(String)
  case missingPrototypeEvidence(String)
  case recommendationNotActionable(String, ProductTournamentPrototypeEvidenceRecommendation)

  var errorDescription: String? {
    switch self {
    case .unknownTournament(let id):
      return "Product tournament \(id) was not found."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unsupportedRound(let id):
      return "Product tournament round \(id) is not a prototype round."
    case .unknownContender(let id):
      return "Product tournament contender \(id) was not found."
    case .missingPrototypeEvidence(let contenderID):
      return "No scoped Round 3 prototype evidence exists for contender \(contenderID)."
    case .recommendationNotActionable(let contenderID, let recommendation):
      return
        "Round 3 recommendation \(recommendation.rawValue) for contender \(contenderID) is not a tournament transition."
    }
  }
}

enum ProductTournamentPrototypeEvidenceTransitioner {
  static func proposals(
    tournamentID: String? = nil,
    roundID: String? = nil,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentPrototypeEvidenceTransitionProposal] {
    activePrototypeRounds(
      tournamentID: tournamentID,
      roundID: roundID,
      config: config
    )
    .flatMap { tournament, round in
      proposals(
        for: tournament,
        round: round,
        config: config,
        evidenceIndex: evidenceIndex
      )
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
  ) -> ProductTournamentPrototypeEvidenceTransitionProposal? {
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
  ) throws -> ProductTournamentPrototypeEvidenceTransitionOutcome {
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
      throw ProductTournamentPrototypeEvidenceTransitionError.missingPrototypeEvidence(contenderID)
    }
    return try apply(proposal: proposal, to: config, now: now)
  }

  static func apply(
    proposal: ProductTournamentPrototypeEvidenceTransitionProposal,
    to config: ProductTournamentConfig,
    now: Date = Date()
  ) throws -> ProductTournamentPrototypeEvidenceTransitionOutcome {
    guard proposal.isActionable else {
      throw ProductTournamentPrototypeEvidenceTransitionError.recommendationNotActionable(
        proposal.contenderID,
        proposal.recommendation
      )
    }
    guard let tournament = config.tournaments.first(where: { $0.id == proposal.tournamentID })
    else {
      throw ProductTournamentPrototypeEvidenceTransitionError.unknownTournament(
        proposal.tournamentID)
    }
    guard let round = config.tournamentRounds.first(where: { $0.id == proposal.roundID }) else {
      throw ProductTournamentPrototypeEvidenceTransitionError.unknownRound(proposal.roundID)
    }
    guard round.kind == .prototype else {
      throw ProductTournamentPrototypeEvidenceTransitionError.unsupportedRound(round.id)
    }
    guard config.tournamentContenders.contains(where: { $0.id == proposal.contenderID }) else {
      throw ProductTournamentPrototypeEvidenceTransitionError.unknownContender(
        proposal.contenderID)
    }

    var next = config
    let timestamp = now.timeIntervalSince1970
    var affectedContenderIDs = [proposal.contenderID]

    switch proposal.recommendation {
    case .selectWinner:
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.status = .completed
        tournament.currentRoundID = round.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .completed
        round.contenderIDs = [proposal.contenderID]
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .winner
      }
      for losingContender in next.tournamentContenders
      where losingContender.tournamentID == tournament.id
        && losingContender.id != proposal.contenderID
        && losingContender.status != .eliminated
        && losingContender.status != .archived
      {
        affectedContenderIDs.append(losingContender.id)
        updateContender(losingContender.id, in: &next, timestamp: timestamp) { contender in
          contender.status = .eliminated
        }
        updateExperiment(for: losingContender.id, in: &next, timestamp: timestamp) { experiment in
          experiment.decision = .kill
        }
        updateSolution(for: losingContender.id, in: &next) { solution in
          solution.status = .rejected
        }
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .promote
      }
      updateSolution(for: proposal.contenderID, in: &next) { solution in
        solution.status = .promoted
      }

    case .revisePrototype:
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.status = .active
        tournament.currentRoundID = round.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .needsRevision
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .narrow
      }

    case .eliminate:
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.status = .active
        tournament.currentRoundID = round.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .eliminated
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .kill
      }
      updateSolution(for: proposal.contenderID, in: &next) { solution in
        solution.status = .rejected
      }

    case .gatherEvidence:
      break
    }

    return ProductTournamentPrototypeEvidenceTransitionOutcome(
      proposal: proposal,
      config: next,
      affectedContenderIDs: affectedContenderIDs,
      fromRoundID: round.id,
      toRoundID: nil
    )
  }

  private static func proposals(
    for tournament: ProductTournament,
    round: ProductTournamentRound,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentPrototypeEvidenceTransitionProposal] {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.compactMap { contenderID in
      guard
        let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
        contender.isRoundThreePrototypeTransitionCandidate
      else { return nil }
      let summaries = evidenceIndex.summaries.filter {
        $0.tournamentID == tournament.id
          && $0.roundID == round.id
          && $0.contenderID == contender.id
      }
      return proposal(
        for: summaries,
        tournament: tournament,
        round: round,
        contender: contender
      )
    }
  }

  private static func proposal(
    for rawSummaries: [ProductTournamentEvidenceSummary],
    tournament: ProductTournament,
    round: ProductTournamentRound,
    contender: ProductTournamentContender
  ) -> ProductTournamentPrototypeEvidenceTransitionProposal {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let failedCount = summaries.count - completed.count
    let distinctPersonaCount = Set(completed.map(\.personaID).filter { !$0.isEmpty }).count
    let currentAlternativeProofCount = completed.filter(hasCurrentAlternativeProof).count
    let scoreValues = completed.flatMap { summary in
      [
        summary.scores.painRecognition,
        summary.scores.workflowImprovement,
        summary.scores.alternativeAdvantage,
        summary.scores.switchingReadiness,
        summary.scores.continuedUsePull,
        summary.scores.willingnessToPay,
      ].compactMap { $0 }.map(Double.init)
    }
    let averageScore = average(scoreValues)
    let explicitWillingnessToPayScore = average(
      completed.compactMap(\.scores.willingnessToPay).map(Double.init)
    )
    let fallbackPullScore = average(
      completed.flatMap { summary in
        [summary.scores.switchingReadiness, summary.scores.continuedUsePull]
          .compactMap { $0 }
          .map(Double.init)
      }
    )
    let willingnessToPayScore =
      explicitWillingnessToPayScore > 0 ? explicitWillingnessToPayScore : fallbackPullScore
    let missingCapabilityCount = completed.flatMap(\.missingCapabilities).count
    let repeatedObjectionCount = repeatedObjectionCount(in: completed)
    let strongCount = completed.filter {
      $0.verdict == .strongPull || $0.verdict == .promising
    }.count
    let weakCount = completed.filter { $0.verdict == .weak || $0.verdict == .rejected }.count
    let readinessScore = readinessScore(
      summaries: summaries,
      completed: completed,
      averageScore: averageScore,
      willingnessToPayScore: willingnessToPayScore,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      missingCapabilityCount: missingCapabilityCount,
      repeatedObjectionCount: repeatedObjectionCount,
      failedRunCount: failedCount
    )
    let recommendation = recommendation(
      completedRunCount: completed.count,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      readinessScore: readinessScore,
      averageScore: averageScore,
      willingnessToPayScore: willingnessToPayScore,
      strongOrPromisingCount: strongCount,
      weakOrRejectedCount: weakCount,
      missingCapabilityCount: missingCapabilityCount,
      repeatedObjectionCount: repeatedObjectionCount
    )
    let priority = priority(for: recommendation, readinessScore: readinessScore)
    let (title, detail) = copy(
      recommendation: recommendation,
      readinessScore: readinessScore,
      averageScore: averageScore,
      willingnessToPayScore: willingnessToPayScore,
      completedRunCount: completed.count,
      runCount: summaries.count,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      missingCapabilityCount: missingCapabilityCount
    )

    return ProductTournamentPrototypeEvidenceTransitionProposal(
      tournamentID: tournament.id,
      roundID: round.id,
      roundTitle: round.title,
      contenderID: contender.id,
      contenderTitle: contender.title,
      recommendation: recommendation,
      readinessScore: readinessScore,
      averageScore: roundedScore(averageScore, upperBound: 5),
      willingnessToPayScore: roundedScore(willingnessToPayScore, upperBound: 5),
      runCount: summaries.count,
      completedRunCount: completed.count,
      failedRunCount: failedCount,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      strongOrPromisingCount: strongCount,
      weakOrRejectedCount: weakCount,
      missingCapabilityCount: missingCapabilityCount,
      evidenceRunIDs: summaries.prefix(8).map(\.runID),
      priority: priority,
      title: title,
      detail: detail,
      rationale: rationale(
        completedRunCount: completed.count,
        runCount: summaries.count,
        distinctPersonaCount: distinctPersonaCount,
        currentAlternativeProofCount: currentAlternativeProofCount,
        readinessScore: readinessScore,
        averageScore: averageScore,
        willingnessToPayScore: willingnessToPayScore,
        missingCapabilityCount: missingCapabilityCount,
        repeatedObjectionCount: repeatedObjectionCount,
        recommendation: recommendation
      )
    )
  }

  private static func readinessScore(
    summaries: [ProductTournamentEvidenceSummary],
    completed: [ProductTournamentEvidenceSummary],
    averageScore: Double,
    willingnessToPayScore: Double,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int,
    failedRunCount: Int
  ) -> Double {
    var score = 0.0
    switch completed.count {
    case 3...: score += 22
    case 2: score += 14
    case 1: score += 8
    default: break
    }
    switch distinctPersonaCount {
    case 3...: score += 16
    case 2: score += 12
    case 1: score += 4
    default: break
    }
    switch currentAlternativeProofCount {
    case 3...: score += 12
    case 2: score += 9
    case 1: score += 3
    default: break
    }
    if averageScore > 0 {
      score += max(0, min(30, ((averageScore - 1) / 4) * 30))
    } else if !completed.isEmpty {
      score += 8
    }
    if willingnessToPayScore > 0 {
      score += max(0, min(18, ((willingnessToPayScore - 1) / 4) * 18))
    }
    score += average(summaries.map { verdictContribution($0.verdict) })
    score -= Double(min(20, missingCapabilityCount * 5))
    score -= Double(min(12, repeatedObjectionCount * 4))
    score -= Double(min(18, failedRunCount * 6))
    if completed.isEmpty && failedRunCount > 0 {
      score = min(score, 20)
    }
    return roundedScore(score, upperBound: 100)
  }

  private static func recommendation(
    completedRunCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    strongOrPromisingCount: Int,
    weakOrRejectedCount: Int,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int
  ) -> ProductTournamentPrototypeEvidenceRecommendation {
    guard completedRunCount > 0 else { return .gatherEvidence }
    if completedRunCount >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.2
        || weakOrRejectedCount >= 2)
    {
      return .eliminate
    }
    if completedRunCount < 3 || distinctPersonaCount < 2 || currentAlternativeProofCount < 2 {
      return .gatherEvidence
    }
    if readinessScore >= 76
      && averageScore >= 3.8
      && willingnessToPayScore >= 3.6
      && strongOrPromisingCount >= 2
      && missingCapabilityCount == 0
      && repeatedObjectionCount == 0
    {
      return .selectWinner
    }
    return .revisePrototype
  }

  private static func copy(
    recommendation: ProductTournamentPrototypeEvidenceRecommendation,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    missingCapabilityCount: Int
  ) -> (String, String) {
    let score = "\(Int(readinessScore.rounded()))"
    let averageLabel = format(averageScore)
    let payLabel = format(willingnessToPayScore)
    switch recommendation {
    case .selectWinner:
      return (
        "Select Tournament Winner",
        "Readiness \(score)/100 with prototype score \(averageLabel)/5 and willingness to pay \(payLabel)/5."
      )
    case .revisePrototype:
      let blocker =
        missingCapabilityCount > 0
        ? "\(missingCapabilityCount) missing capability signal(s)"
        : "mixed prototype pull"
      return (
        "Revise Prototype",
        "Readiness \(score)/100; \(blocker) before selecting a winner."
      )
    case .eliminate:
      return (
        "Eliminate Contender",
        "Readiness \(score)/100 is too weak to select as the tournament winner."
      )
    case .gatherEvidence:
      return (
        "Gather More Evidence",
        "\(completedRunCount) completed of \(runCount) run(s), \(distinctPersonaCount) persona(s), \(currentAlternativeProofCount) current-alternative proof(s); Round 3 needs broader winner evidence."
      )
    }
  }

  private static func rationale(
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int,
    recommendation: ProductTournamentPrototypeEvidenceRecommendation
  ) -> [String] {
    var lines = [
      "\(completedRunCount) completed of \(runCount) Round 3 run(s) across \(distinctPersonaCount) persona(s)."
    ]
    lines.append("\(currentAlternativeProofCount) run(s) compare against the current alternative.")
    if averageScore > 0 {
      lines.append(
        "Average prototype score \(format(averageScore))/5; readiness \(format(readinessScore))/100."
      )
    }
    if willingnessToPayScore > 0 {
      lines.append("Willingness to pay or sponsor average \(format(willingnessToPayScore))/5.")
    }
    if missingCapabilityCount > 0 {
      lines.append("\(missingCapabilityCount) missing capability signal(s) remain.")
    }
    if repeatedObjectionCount > 0 {
      lines.append("\(repeatedObjectionCount) repeated objection cluster(s) remain.")
    }
    switch recommendation {
    case .selectWinner:
      lines.append("Prototype evidence is strong enough to select a tournament winner.")
    case .revisePrototype:
      lines.append("Prototype evidence needs a revision before winner selection.")
    case .eliminate:
      lines.append("Prototype evidence is weak enough to stop this contender.")
    case .gatherEvidence:
      lines.append("Run more scoped Round 3 scenarios before selecting a winner.")
    }
    return lines
  }

  private static func activePrototypeRounds(
    tournamentID: String?,
    roundID: String?,
    config: ProductTournamentConfig
  ) -> [(ProductTournament, ProductTournamentRound)] {
    let tournaments = config.tournaments
      .filter { tournament in
        (tournamentID == nil || tournament.id == tournamentID)
          && (tournament.status == .active || tournament.status == .drafting)
      }
    var pairs: [(ProductTournament, ProductTournamentRound)] = []
    for tournament in tournaments {
      if let roundID {
        if let round = config.tournamentRounds.first(where: {
          $0.id == roundID
            && $0.tournamentID == tournament.id
            && $0.kind == .prototype
            && $0.status == .active
        }) {
          pairs.append((tournament, round))
        }
        continue
      }

      let currentRound = tournament.currentRoundID.flatMap { roundID in
        config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
      }
      if let currentRound, currentRound.kind == .prototype, currentRound.status == .active {
        pairs.append((tournament, currentRound))
        continue
      }
      guard tournament.currentRoundID == nil else { continue }
      if let activeRound = config.tournamentRounds
        .filter({
          $0.tournamentID == tournament.id && $0.kind == .prototype && $0.status == .active
        })
        .sorted(by: { $0.ordinal < $1.ordinal })
        .first
      {
        pairs.append((tournament, activeRound))
      }
    }
    return pairs
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

  private static func priority(
    for recommendation: ProductTournamentPrototypeEvidenceRecommendation,
    readinessScore: Double
  ) -> Int {
    switch recommendation {
    case .selectWinner:
      return 10_000 + Int(readinessScore.rounded())
    case .eliminate:
      return 8_000 + Int((100 - readinessScore).rounded())
    case .revisePrototype:
      return 6_000 + Int((100 - readinessScore).rounded())
    case .gatherEvidence:
      return Int(readinessScore.rounded())
    }
  }

  private static func verdictContribution(_ verdict: ProductTournamentEvidenceVerdict) -> Double {
    switch verdict {
    case .strongPull: return 18
    case .promising: return 14
    case .unclear: return 6
    case .weak: return -6
    case .rejected: return -12
    }
  }

  private static func hasCurrentAlternativeProof(_ summary: ProductTournamentEvidenceSummary) -> Bool {
    let comparison = normalizedEvidenceText(summary.currentAlternativeComparison)
    guard !comparison.isEmpty else { return false }
    return !comparison.contains("did not address")
      && !comparison.contains("no current alternative comparison")
      && !comparison.contains("no current alternative")
      && !comparison.contains("no current-alternative comparison")
  }

  private static func repeatedObjectionCount(
    in summaries: [ProductTournamentEvidenceSummary]
  ) -> Int {
    var counts: [String: Int] = [:]
    for objection in summaries.flatMap(\.objections) {
      let normalized = normalizedEvidenceText(objection)
      guard !normalized.isEmpty else { continue }
      counts[normalized, default: 0] += 1
    }
    return counts.values.filter { $0 >= 2 }.count
  }

  private static func normalizedEvidenceText(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
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

  private static func updateExperiment(
    for contenderID: String,
    in config: inout ProductTournamentConfig,
    timestamp: Double,
    mutate: (inout ProductExperiment) -> Void
  ) {
    guard
      let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
      let experimentID = contender.experimentID,
      let index = config.experiments.firstIndex(where: { $0.id == experimentID })
    else { return }
    mutate(&config.experiments[index])
    config.experiments[index].updatedAt = timestamp
  }

  private static func updateSolution(
    for contenderID: String,
    in config: inout ProductTournamentConfig,
    mutate: (inout SolutionHypothesis) -> Void
  ) {
    guard
      let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
      let index = config.solutionHypotheses.firstIndex(where: { $0.id == contender.solutionID })
    else { return }
    mutate(&config.solutionHypotheses[index])
  }

  private static func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func roundedScore(_ value: Double, upperBound: Double) -> Double {
    let bounded = max(0, min(upperBound, value))
    return (bounded * 10).rounded() / 10
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

@MainActor
extension CompassProject {
  func applyBestProductTournamentPrototypeEvidenceTransition(
    tournamentID: String? = nil,
    roundID: String? = nil
  ) async -> ProductTournamentPrototypeEvidenceTransitionOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      let config = try workspace.readProductTournamentConfig()
      let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
      let outcome = try ProductTournamentPrototypeEvidenceTransitioner.applyBestProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        to: config,
        evidenceIndex: evidenceIndex
      )
      try workspace.writeProductTournamentConfig(outcome.config)
      productTournamentConfig = outcome.config
      productTournamentEvidenceIndex = evidenceIndex
      log(outcome.userMessage, level: .success)
      return outcome
    } catch {
      fail(error)
      return nil
    }
  }
}

extension ProductTournamentContender {
  fileprivate var isRoundThreePrototypeTransitionCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision:
      return true
    case .competing, .eliminated, .winner, .archived:
      return false
    }
  }
}
