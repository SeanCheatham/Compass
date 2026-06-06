import Foundation

enum ProductTournamentRoundEvidenceRecommendation: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case gatherEvidence = "gather_evidence"
  case advanceToPrototype = "advance_to_prototype"
  case reviseCoreTechnology = "revise_core_technology"
  case eliminate

  var title: String {
    switch self {
    case .gatherEvidence: return "Gather Evidence"
    case .advanceToPrototype: return "Advance"
    case .reviseCoreTechnology: return "Revise"
    case .eliminate: return "Eliminate"
    }
  }
}

struct ProductTournamentRoundEvidenceTransitionProposal: Codable, Equatable, Identifiable,
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
  var recommendation: ProductTournamentRoundEvidenceRecommendation
  var readinessScore: Double
  var averageScore: Double
  var runCount: Int
  var completedRunCount: Int
  var failedRunCount: Int
  var distinctPersonaCount: Int
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
    case .advanceToPrototype, .reviseCoreTechnology, .eliminate:
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
      "- round_2_evidence contender \(contenderID) [round \(roundID), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), missing_capabilities \(missingCapabilityCount), \(evidence)]: \(detail)"
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }
}

struct ProductTournamentRoundEvidenceTransitionOutcome: Equatable, Sendable {
  var proposal: ProductTournamentRoundEvidenceTransitionProposal
  var config: ProductizationConfig
  var affectedContenderIDs: [String]
  var fromRoundID: String
  var toRoundID: String?

  var userMessage: String {
    switch proposal.recommendation {
    case .advanceToPrototype:
      return
        "Advanced \(proposal.contenderTitle) to Round 3 prototype from Round 2 feasibility evidence."
    case .reviseCoreTechnology:
      return "Marked \(proposal.contenderTitle) for Round 2 core-technology revision."
    case .eliminate:
      return "Eliminated \(proposal.contenderTitle) after Round 2 feasibility evidence."
    case .gatherEvidence:
      return "Round 2 still needs more feasibility evidence for \(proposal.contenderTitle)."
    }
  }
}

enum ProductTournamentRoundEvidenceTransitionError: LocalizedError, Equatable {
  case unknownTournament(String)
  case unknownRound(String)
  case unsupportedRound(String)
  case unknownContender(String)
  case missingRoundEvidence(String)
  case recommendationNotActionable(String, ProductTournamentRoundEvidenceRecommendation)
  case missingPrototypeRound(String)

  var errorDescription: String? {
    switch self {
    case .unknownTournament(let id):
      return "Product tournament \(id) was not found."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unsupportedRound(let id):
      return "Product tournament round \(id) is not a core-technology feasibility round."
    case .unknownContender(let id):
      return "Product tournament contender \(id) was not found."
    case .missingRoundEvidence(let contenderID):
      return "No scoped Round 2 evidence exists for contender \(contenderID)."
    case .recommendationNotActionable(let contenderID, let recommendation):
      return
        "Round 2 recommendation \(recommendation.rawValue) for contender \(contenderID) is not a tournament transition."
    case .missingPrototypeRound(let tournamentID):
      return "Product tournament \(tournamentID) has no Round 3 prototype round."
    }
  }
}

enum ProductTournamentRoundEvidenceTransitioner {
  static func proposals(
    tournamentID: String? = nil,
    roundID: String? = nil,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductTournamentRoundEvidenceTransitionProposal] {
    activeCoreTechnologyRounds(
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
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductTournamentRoundEvidenceTransitionProposal? {
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
    to config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    now: Date = Date()
  ) throws -> ProductTournamentRoundEvidenceTransitionOutcome {
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
      throw ProductTournamentRoundEvidenceTransitionError.missingRoundEvidence(contenderID)
    }
    return try apply(proposal: proposal, to: config, now: now)
  }

  static func apply(
    proposal: ProductTournamentRoundEvidenceTransitionProposal,
    to config: ProductizationConfig,
    now: Date = Date()
  ) throws -> ProductTournamentRoundEvidenceTransitionOutcome {
    guard proposal.isActionable else {
      throw ProductTournamentRoundEvidenceTransitionError.recommendationNotActionable(
        proposal.contenderID,
        proposal.recommendation
      )
    }
    guard let tournament = config.tournaments.first(where: { $0.id == proposal.tournamentID })
    else {
      throw ProductTournamentRoundEvidenceTransitionError.unknownTournament(proposal.tournamentID)
    }
    guard let round = config.tournamentRounds.first(where: { $0.id == proposal.roundID }) else {
      throw ProductTournamentRoundEvidenceTransitionError.unknownRound(proposal.roundID)
    }
    guard round.kind == .coreTechnology else {
      throw ProductTournamentRoundEvidenceTransitionError.unsupportedRound(round.id)
    }
    guard config.tournamentContenders.contains(where: { $0.id == proposal.contenderID }) else {
      throw ProductTournamentRoundEvidenceTransitionError.unknownContender(proposal.contenderID)
    }

    var next = config
    let timestamp = now.timeIntervalSince1970
    let destinationRoundID: String?

    switch proposal.recommendation {
    case .advanceToPrototype:
      let prototypeRound = try roundThreePrototypeRound(
        for: tournament, after: round, config: config)
      destinationRoundID = prototypeRound.id
      updateTournament(tournament.id, in: &next, timestamp: timestamp) { tournament in
        tournament.currentRoundID = prototypeRound.id
      }
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .completed
      }
      updateRound(prototypeRound.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
        round.contenderIDs = [proposal.contenderID]
      }
      updateContender(proposal.contenderID, in: &next, timestamp: timestamp) { contender in
        contender.status = .narrowed
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .keepGoing
      }
      updateSolution(for: proposal.contenderID, in: &next) { solution in
        solution.status = .active
      }

    case .reviseCoreTechnology:
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
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .narrow
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
      updateRound(round.id, in: &next, timestamp: timestamp) { round in
        round.status = .active
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .kill
      }
      updateSolution(for: proposal.contenderID, in: &next) { solution in
        solution.status = .rejected
      }

    case .gatherEvidence:
      destinationRoundID = nil
    }

    return ProductTournamentRoundEvidenceTransitionOutcome(
      proposal: proposal,
      config: next,
      affectedContenderIDs: [proposal.contenderID],
      fromRoundID: round.id,
      toRoundID: destinationRoundID
    )
  }

  private static func proposals(
    for tournament: ProductTournament,
    round: ProductTournamentRound,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductTournamentRoundEvidenceTransitionProposal] {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.compactMap { contenderID in
      guard
        let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
        contender.isRoundTwoEvidenceTransitionCandidate
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
    for rawSummaries: [ProductizationEvidenceSummary],
    tournament: ProductTournament,
    round: ProductTournamentRound,
    contender: ProductTournamentContender
  ) -> ProductTournamentRoundEvidenceTransitionProposal {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let failedCount = summaries.count - completed.count
    let distinctPersonaCount = Set(completed.map(\.personaID).filter { !$0.isEmpty }).count
    let scoreValues = completed.flatMap { summary in
      [
        summary.scores.painRecognition,
        summary.scores.workflowImprovement,
        summary.scores.alternativeAdvantage,
        summary.scores.switchingReadiness,
        summary.scores.continuedUsePull,
      ].compactMap { $0 }.map(Double.init)
    }
    let averageScore = average(scoreValues)
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
      distinctPersonaCount: distinctPersonaCount,
      missingCapabilityCount: missingCapabilityCount,
      repeatedObjectionCount: repeatedObjectionCount,
      failedRunCount: failedCount
    )
    let recommendation = recommendation(
      completedRunCount: completed.count,
      distinctPersonaCount: distinctPersonaCount,
      readinessScore: readinessScore,
      averageScore: averageScore,
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
      completedRunCount: completed.count,
      runCount: summaries.count,
      distinctPersonaCount: distinctPersonaCount,
      missingCapabilityCount: missingCapabilityCount
    )

    return ProductTournamentRoundEvidenceTransitionProposal(
      tournamentID: tournament.id,
      roundID: round.id,
      roundTitle: round.title,
      contenderID: contender.id,
      contenderTitle: contender.title,
      recommendation: recommendation,
      readinessScore: readinessScore,
      averageScore: roundedScore(averageScore, upperBound: 5),
      runCount: summaries.count,
      completedRunCount: completed.count,
      failedRunCount: failedCount,
      distinctPersonaCount: distinctPersonaCount,
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
        readinessScore: readinessScore,
        averageScore: averageScore,
        missingCapabilityCount: missingCapabilityCount,
        repeatedObjectionCount: repeatedObjectionCount,
        recommendation: recommendation
      )
    )
  }

  private static func readinessScore(
    summaries: [ProductizationEvidenceSummary],
    completed: [ProductizationEvidenceSummary],
    averageScore: Double,
    distinctPersonaCount: Int,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int,
    failedRunCount: Int
  ) -> Double {
    var score = 0.0
    switch completed.count {
    case 3...: score += 26
    case 2: score += 20
    case 1: score += 10
    default: break
    }
    switch distinctPersonaCount {
    case 3...: score += 18
    case 2: score += 14
    case 1: score += 6
    default: break
    }
    if averageScore > 0 {
      score += max(0, min(34, ((averageScore - 1) / 4) * 34))
    } else if !completed.isEmpty {
      score += 10
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
    readinessScore: Double,
    averageScore: Double,
    strongOrPromisingCount: Int,
    weakOrRejectedCount: Int,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int
  ) -> ProductTournamentRoundEvidenceRecommendation {
    guard completedRunCount > 0 else { return .gatherEvidence }
    if completedRunCount >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.2
        || weakOrRejectedCount >= 2)
    {
      return .eliminate
    }
    if completedRunCount < 2 || distinctPersonaCount < 2 {
      return .gatherEvidence
    }
    if completedRunCount >= 2
      && distinctPersonaCount >= 2
      && readinessScore >= 66
      && averageScore >= 3.4
      && strongOrPromisingCount >= 2
      && missingCapabilityCount == 0
      && repeatedObjectionCount == 0
    {
      return .advanceToPrototype
    }
    return .reviseCoreTechnology
  }

  private static func copy(
    recommendation: ProductTournamentRoundEvidenceRecommendation,
    readinessScore: Double,
    averageScore: Double,
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    missingCapabilityCount: Int
  ) -> (String, String) {
    let score = "\(Int(readinessScore.rounded()))"
    let averageLabel = format(averageScore)
    switch recommendation {
    case .advanceToPrototype:
      return (
        "Advance to Round 3",
        "Readiness \(score)/100 with average feasibility evidence \(averageLabel)/5 across \(distinctPersonaCount) persona(s)."
      )
    case .reviseCoreTechnology:
      let blocker =
        missingCapabilityCount > 0
        ? "\(missingCapabilityCount) missing capability signal(s)"
        : "mixed simulated-user pull"
      return (
        "Revise Core Technology",
        "Readiness \(score)/100; \(blocker) before prototype fidelity."
      )
    case .eliminate:
      return (
        "Eliminate Contender",
        "Readiness \(score)/100 is too weak for more Round 3 implementation spend."
      )
    case .gatherEvidence:
      return (
        "Gather More Evidence",
        "\(completedRunCount) completed of \(runCount) run(s); Round 2 needs at least 2 personas before transition."
      )
    }
  }

  private static func rationale(
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    readinessScore: Double,
    averageScore: Double,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int,
    recommendation: ProductTournamentRoundEvidenceRecommendation
  ) -> [String] {
    var lines = [
      "\(completedRunCount) completed of \(runCount) Round 2 run(s) across \(distinctPersonaCount) persona(s)."
    ]
    if averageScore > 0 {
      lines.append(
        "Average feasibility score \(format(averageScore))/5; readiness \(format(readinessScore))/100."
      )
    }
    if missingCapabilityCount > 0 {
      lines.append("\(missingCapabilityCount) missing capability signal(s) remain.")
    }
    if repeatedObjectionCount > 0 {
      lines.append("\(repeatedObjectionCount) repeated objection cluster(s) remain.")
    }
    switch recommendation {
    case .advanceToPrototype:
      lines.append("Core technology evidence is strong enough to justify Round 3 fidelity.")
    case .reviseCoreTechnology:
      lines.append("Core technology should be revised before increasing prototype fidelity.")
    case .eliminate:
      lines.append("Feasibility evidence is weak enough to stop this contender.")
    case .gatherEvidence:
      lines.append("Run more scoped Round 2 scenarios before advancing or eliminating.")
    }
    return lines
  }

  private static func activeCoreTechnologyRounds(
    tournamentID: String?,
    roundID: String?,
    config: ProductizationConfig
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
            && $0.kind == .coreTechnology
            && $0.status == .active
        }) {
          pairs.append((tournament, round))
        }
        continue
      }

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

  private static func selectedTournament(
    tournamentID: String?,
    config: ProductizationConfig
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

  private static func roundThreePrototypeRound(
    for tournament: ProductTournament,
    after round: ProductTournamentRound,
    config: ProductizationConfig
  ) throws -> ProductTournamentRound {
    let rounds = tournament.roundIDs.compactMap { roundID in
      config.tournamentRounds.first { $0.id == roundID }
    }
    if let prototype = rounds.first(where: {
      $0.kind == .prototype && $0.ordinal > round.ordinal
    }) {
      return prototype
    }
    throw ProductTournamentRoundEvidenceTransitionError.missingPrototypeRound(tournament.id)
  }

  private static func priority(
    for recommendation: ProductTournamentRoundEvidenceRecommendation,
    readinessScore: Double
  ) -> Int {
    switch recommendation {
    case .advanceToPrototype:
      return 10_000 + Int(readinessScore.rounded())
    case .eliminate:
      return 8_000 + Int((100 - readinessScore).rounded())
    case .reviseCoreTechnology:
      return 6_000 + Int((100 - readinessScore).rounded())
    case .gatherEvidence:
      return Int(readinessScore.rounded())
    }
  }

  private static func verdictContribution(_ verdict: ProductizationEvidenceVerdict) -> Double {
    switch verdict {
    case .strongPull: return 18
    case .promising: return 14
    case .unclear: return 6
    case .weak: return -6
    case .rejected: return -12
    }
  }

  private static func repeatedObjectionCount(
    in summaries: [ProductizationEvidenceSummary]
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
    in config: inout ProductizationConfig,
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
    in config: inout ProductizationConfig,
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
    in config: inout ProductizationConfig,
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
    in config: inout ProductizationConfig,
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
    in config: inout ProductizationConfig,
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
  func applyBestProductTournamentRoundEvidenceTransition(
    tournamentID: String? = nil,
    roundID: String? = nil
  ) async -> ProductTournamentRoundEvidenceTransitionOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      let config = try workspace.readProductTournamentConfig()
      let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
      let outcome = try ProductTournamentRoundEvidenceTransitioner.applyBestProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        to: config,
        evidenceIndex: evidenceIndex
      )
      try workspace.writeProductTournamentConfig(outcome.config)
      productizationConfig = outcome.config
      productizationEvidenceIndex = evidenceIndex
      log(outcome.userMessage, level: .success)
      return outcome
    } catch {
      fail(error)
      return nil
    }
  }
}

extension ProductTournamentContender {
  fileprivate var isRoundTwoEvidenceTransitionCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision:
      return true
    case .competing, .eliminated, .winner, .archived:
      return false
    }
  }
}
