import Foundation

enum ProductTournamentSimulationMode: String, Codable, CaseIterable, Equatable, Sendable {
  case modelFree = "model_free"
  case personaModel = "persona_model"
  case marketPressure = "market_pressure"

  var tournamentAutomationLabel: String {
    switch self {
    case .modelFree: return "Model-free"
    case .personaModel: return "Persona-model"
    case .marketPressure: return "Market-pressure"
    }
  }
}

enum ProductTournamentRunStatus: String, Codable, Equatable, Sendable {
  case completed
  case appContractMissing
  case appCommandFailed
  case appOutputNotJSON
  case noAllowedActions
  case invalidPersonaAction
  case personaCallFailed
  case maxTurnsReached
  case nondeterministicExperienceTrace
}

enum ProductTournamentEvidenceVerdict: String, Codable, CaseIterable, Equatable, Sendable {
  case strongPull = "strong_pull"
  case promising
  case unclear
  case weak
  case rejected
}

enum ProductTournamentReadinessRecommendation: String, Codable, CaseIterable, Equatable, Sendable {
  case gatherEvidence = "gather_evidence"
  case keepGoing = "continue"
  case narrow
  case pivot
  case kill
  case promote

  var title: String {
    switch self {
    case .gatherEvidence: return "Gather Evidence"
    case .keepGoing: return "Continue"
    case .narrow: return "Narrow"
    case .pivot: return "Pivot"
    case .kill: return "Kill"
    case .promote: return "Promote"
    }
  }
}

struct ProductTournamentProofDebt: Codable, Equatable, Sendable {
  var completedRunDeficit: Int
  var personaDeficit: Int
  var personaModelSimulatedUserDeficit: Int
  var personaModelCurrentAlternativeDeficit: Int
  var failedRunCount: Int

  var isClear: Bool {
    blockingDebtCount == 0
  }

  var blockingDebtCount: Int {
    completedRunDeficit + personaDeficit + personaModelSimulatedUserDeficit
      + personaModelCurrentAlternativeDeficit + (failedRunCount > 0 ? 1 : 0)
  }

  var summary: String {
    let labels = debtLabels
    guard !labels.isEmpty else { return "proof complete" }
    return labels.joined(separator: ", ")
  }

  var debtLabels: [String] {
    var labels: [String] = []
    if completedRunDeficit > 0 {
      labels.append("\(completedRunDeficit) completed run(s)")
    }
    if personaDeficit > 0 {
      labels.append("\(personaDeficit) persona(s)")
    }
    if personaModelSimulatedUserDeficit > 0 {
      labels.append("\(personaModelSimulatedUserDeficit) persona-model simulated user(s)")
    }
    if personaModelCurrentAlternativeDeficit > 0 {
      labels.append(
        "\(personaModelCurrentAlternativeDeficit) persona-model current-alternative proof(s)")
    }
    if failedRunCount > 0 {
      labels.append("\(failedRunCount) failed run(s) to repair")
    }
    return labels
  }

  init(
    completedRunCount: Int,
    distinctPersonaCount: Int,
    personaModelDistinctPersonaCount: Int,
    personaModelCurrentAlternativePersonaCount: Int,
    failedRunCount: Int,
    minimumCompletedRuns: Int = 2,
    minimumPersonaCount: Int = 2,
    minimumPersonaModelSimulatedUserCount: Int = 2,
    minimumPersonaModelCurrentAlternativePersonaCount: Int = 2
  ) {
    self.completedRunDeficit = max(0, minimumCompletedRuns - completedRunCount)
    self.personaDeficit = max(0, minimumPersonaCount - distinctPersonaCount)
    self.personaModelSimulatedUserDeficit = max(
      0,
      minimumPersonaModelSimulatedUserCount - personaModelDistinctPersonaCount
    )
    self.personaModelCurrentAlternativeDeficit = max(
      0,
      minimumPersonaModelCurrentAlternativePersonaCount - personaModelCurrentAlternativePersonaCount
    )
    self.failedRunCount = max(0, failedRunCount)
  }

  init(
    completedRunDeficit: Int,
    personaDeficit: Int,
    personaModelSimulatedUserDeficit: Int,
    personaModelCurrentAlternativeDeficit: Int,
    failedRunCount: Int
  ) {
    self.completedRunDeficit = max(0, completedRunDeficit)
    self.personaDeficit = max(0, personaDeficit)
    self.personaModelSimulatedUserDeficit = max(0, personaModelSimulatedUserDeficit)
    self.personaModelCurrentAlternativeDeficit = max(0, personaModelCurrentAlternativeDeficit)
    self.failedRunCount = max(0, failedRunCount)
  }
}

struct ProductTournamentReadiness: Codable, Equatable, Identifiable, Sendable {
  var id: String { experimentID }

  var experimentID: String
  var runCount: Int
  var completedRunCount: Int
  var failedRunCount: Int
  var personaModelCompletedRunCount: Int
  var personaModelDistinctPersonaCount: Int
  var currentAlternativeComparisonCount: Int
  var personaModelCurrentAlternativePersonaCount: Int
  var modelFreeCompletedRunCount: Int
  var distinctPersonaCount: Int
  var latestRunID: String?
  var readinessScore: Double
  var averageScore: Double
  var strongestVerdict: ProductTournamentEvidenceVerdict
  var weakestVerdict: ProductTournamentEvidenceVerdict
  var recommendation: ProductTournamentReadinessRecommendation
  var proofDebt: ProductTournamentProofDebt
  var rationale: [String]
  var evidenceRunIDs: [String]

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  private enum CodingKeys: String, CodingKey {
    case experimentID
    case runCount
    case completedRunCount
    case failedRunCount
    case personaModelCompletedRunCount
    case personaModelDistinctPersonaCount
    case currentAlternativeComparisonCount
    case personaModelCurrentAlternativePersonaCount
    case modelFreeCompletedRunCount
    case distinctPersonaCount
    case latestRunID
    case readinessScore
    case averageScore
    case strongestVerdict
    case weakestVerdict
    case recommendation
    case proofDebt
    case rationale
    case evidenceRunIDs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let personaModelCompletedRunCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .personaModelCompletedRunCount
      ) ?? 0
    let distinctPersonaCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .distinctPersonaCount
      ) ?? 0
    let personaModelDistinctPersonaCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .personaModelDistinctPersonaCount
      ) ?? min(personaModelCompletedRunCount, distinctPersonaCount)
    let currentAlternativeComparisonCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .currentAlternativeComparisonCount
      ) ?? 0
    let personaModelCurrentAlternativePersonaCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .personaModelCurrentAlternativePersonaCount
      ) ?? 0
    let completedRunCount = try container.decode(Int.self, forKey: .completedRunCount)
    let failedRunCount = try container.decode(Int.self, forKey: .failedRunCount)
    let modelFreeCompletedRunCount =
      try container.decodeIfPresent(
        Int.self,
        forKey: .modelFreeCompletedRunCount
      ) ?? 0

    self.init(
      experimentID: try container.decode(String.self, forKey: .experimentID),
      runCount: try container.decode(Int.self, forKey: .runCount),
      completedRunCount: completedRunCount,
      failedRunCount: failedRunCount,
      personaModelCompletedRunCount: personaModelCompletedRunCount,
      personaModelDistinctPersonaCount: personaModelDistinctPersonaCount,
      currentAlternativeComparisonCount: currentAlternativeComparisonCount,
      personaModelCurrentAlternativePersonaCount: personaModelCurrentAlternativePersonaCount,
      modelFreeCompletedRunCount: modelFreeCompletedRunCount,
      distinctPersonaCount: distinctPersonaCount,
      latestRunID: try container.decodeIfPresent(String.self, forKey: .latestRunID),
      readinessScore: try container.decode(Double.self, forKey: .readinessScore),
      averageScore: try container.decode(Double.self, forKey: .averageScore),
      strongestVerdict: try container.decode(
        ProductTournamentEvidenceVerdict.self,
        forKey: .strongestVerdict
      ),
      weakestVerdict: try container.decode(
        ProductTournamentEvidenceVerdict.self,
        forKey: .weakestVerdict
      ),
      recommendation: try container.decode(
        ProductTournamentReadinessRecommendation.self,
        forKey: .recommendation
      ),
      proofDebt: try container.decodeIfPresent(
        ProductTournamentProofDebt.self,
        forKey: .proofDebt
      ),
      rationale: try container.decodeIfPresent([String].self, forKey: .rationale) ?? [],
      evidenceRunIDs: try container.decodeIfPresent([String].self, forKey: .evidenceRunIDs)
        ?? []
    )
  }

  init(
    experimentID: String,
    runCount: Int,
    completedRunCount: Int,
    failedRunCount: Int,
    personaModelCompletedRunCount: Int,
    personaModelDistinctPersonaCount: Int,
    currentAlternativeComparisonCount: Int,
    personaModelCurrentAlternativePersonaCount: Int,
    modelFreeCompletedRunCount: Int,
    distinctPersonaCount: Int,
    latestRunID: String?,
    readinessScore: Double,
    averageScore: Double,
    strongestVerdict: ProductTournamentEvidenceVerdict,
    weakestVerdict: ProductTournamentEvidenceVerdict,
    recommendation: ProductTournamentReadinessRecommendation,
    proofDebt: ProductTournamentProofDebt? = nil,
    rationale: [String],
    evidenceRunIDs: [String]
  ) {
    self.experimentID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      experimentID,
      fallback: "experiment"
    )
    self.runCount = max(0, runCount)
    self.completedRunCount = max(0, completedRunCount)
    self.failedRunCount = max(0, failedRunCount)
    self.personaModelCompletedRunCount = max(0, personaModelCompletedRunCount)
    self.personaModelDistinctPersonaCount = max(0, personaModelDistinctPersonaCount)
    self.currentAlternativeComparisonCount = max(0, currentAlternativeComparisonCount)
    self.personaModelCurrentAlternativePersonaCount = max(
      0, personaModelCurrentAlternativePersonaCount)
    self.modelFreeCompletedRunCount = max(0, modelFreeCompletedRunCount)
    self.distinctPersonaCount = max(0, distinctPersonaCount)
    self.latestRunID = ProductTournamentEvidenceRecord.optionalBounded(latestRunID, limit: 96)
    self.readinessScore = Self.roundedScore(readinessScore, upperBound: 100)
    self.averageScore = Self.roundedScore(averageScore, upperBound: 5)
    self.strongestVerdict = strongestVerdict
    self.weakestVerdict = weakestVerdict
    self.recommendation = recommendation
    self.proofDebt =
      proofDebt
      ?? ProductTournamentProofDebt(
        completedRunCount: self.completedRunCount,
        distinctPersonaCount: self.distinctPersonaCount,
        personaModelDistinctPersonaCount: self.personaModelDistinctPersonaCount,
        personaModelCurrentAlternativePersonaCount: self.personaModelCurrentAlternativePersonaCount,
        failedRunCount: self.failedRunCount
      )
    self.rationale = ProductTournamentEvidenceRecord.cleanedList(rationale, limit: 260)
    self.evidenceRunIDs = ProductTournamentEvidenceRecord.cleanedList(evidenceRunIDs, limit: 96)
  }

  init(summaries rawSummaries: [ProductTournamentEvidenceSummary]) {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let failedCount = summaries.count - completed.count
    let personaModelCompleted = completed.filter { $0.mode == .personaModel }
    let personaModelCompletedCount = personaModelCompleted.count
    let personaModelUserCount = Set(personaModelCompleted.map(\.personaID).filter { !$0.isEmpty })
      .count
    let currentAlternativeProof = completed.filter(Self.hasCurrentAlternativeProof)
    let personaModelCurrentAlternativePersonaCount = Set(
      personaModelCompleted.filter(Self.hasCurrentAlternativeProof)
        .map(\.personaID)
        .filter { !$0.isEmpty }
    ).count
    let modelFreeCompletedCount = completed.filter { $0.mode == .modelFree }.count
    let personaCount = Set(completed.map(\.personaID).filter { !$0.isEmpty }).count
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
    let averageScore = Self.average(scoreValues)
    let readinessScore = Self.readinessScore(
      summaries: summaries,
      completed: completed,
      averageScore: averageScore,
      distinctPersonaCount: personaCount,
      failedRunCount: failedCount
    )
    let strongest =
      summaries.map(\.verdict).max(by: { Self.verdictRank($0) < Self.verdictRank($1) })
      ?? .unclear
    let weakest =
      summaries.map(\.verdict).min(by: { Self.verdictRank($0) < Self.verdictRank($1) })
      ?? .unclear
    let recommendation = Self.recommendation(
      summaries: summaries,
      completed: completed,
      readinessScore: readinessScore,
      averageScore: averageScore,
      distinctPersonaCount: personaCount,
      personaModelDistinctPersonaCount: personaModelUserCount,
      personaModelCurrentAlternativePersonaCount: personaModelCurrentAlternativePersonaCount,
      failedRunCount: failedCount
    )
    let proofDebt = ProductTournamentProofDebt(
      completedRunCount: completed.count,
      distinctPersonaCount: personaCount,
      personaModelDistinctPersonaCount: personaModelUserCount,
      personaModelCurrentAlternativePersonaCount: personaModelCurrentAlternativePersonaCount,
      failedRunCount: failedCount
    )

    self.init(
      experimentID: summaries.first?.experimentID ?? "experiment",
      runCount: summaries.count,
      completedRunCount: completed.count,
      failedRunCount: failedCount,
      personaModelCompletedRunCount: personaModelCompletedCount,
      personaModelDistinctPersonaCount: personaModelUserCount,
      currentAlternativeComparisonCount: currentAlternativeProof.count,
      personaModelCurrentAlternativePersonaCount: personaModelCurrentAlternativePersonaCount,
      modelFreeCompletedRunCount: modelFreeCompletedCount,
      distinctPersonaCount: personaCount,
      latestRunID: summaries.first?.runID,
      readinessScore: readinessScore,
      averageScore: averageScore,
      strongestVerdict: strongest,
      weakestVerdict: weakest,
      recommendation: recommendation,
      proofDebt: proofDebt,
      rationale: Self.rationale(
        summaries: summaries,
        completed: completed,
        readinessScore: readinessScore,
        averageScore: averageScore,
        distinctPersonaCount: personaCount,
        personaModelCompletedRunCount: personaModelCompletedCount,
        personaModelDistinctPersonaCount: personaModelUserCount,
        currentAlternativeComparisonCount: currentAlternativeProof.count,
        personaModelCurrentAlternativePersonaCount: personaModelCurrentAlternativePersonaCount,
        modelFreeCompletedRunCount: modelFreeCompletedCount,
        failedRunCount: failedCount,
        recommendation: recommendation,
        proofDebt: proofDebt
      ),
      evidenceRunIDs: summaries.prefix(8).map(\.runID)
    )
  }

  private static func readinessScore(
    summaries: [ProductTournamentEvidenceSummary],
    completed: [ProductTournamentEvidenceSummary],
    averageScore: Double,
    distinctPersonaCount: Int,
    failedRunCount: Int
  ) -> Double {
    var score = 0.0
    switch completed.count {
    case 3...: score += 20
    case 2: score += 14
    case 1: score += 8
    default: break
    }
    switch distinctPersonaCount {
    case 3...: score += 15
    case 2: score += 10
    case 1: score += 4
    default: break
    }
    if averageScore > 0 {
      score += max(0, min(40, ((averageScore - 1) / 4) * 40))
    } else if !completed.isEmpty {
      score += 12
    }
    score += Self.average(summaries.map { verdictContribution($0.verdict) })
    score -= Double(min(18, completed.flatMap(\.missingCapabilities).count * 4))
    score -= Double(min(15, repeatedObjectionCount(in: completed) * 5))
    score -= Double(min(18, failedRunCount * 6))
    if completed.isEmpty && failedRunCount > 0 {
      score = min(score, 20)
    }
    return roundedScore(score, upperBound: 100)
  }

  private static func recommendation(
    summaries: [ProductTournamentEvidenceSummary],
    completed: [ProductTournamentEvidenceSummary],
    readinessScore: Double,
    averageScore: Double,
    distinctPersonaCount: Int,
    personaModelDistinctPersonaCount: Int,
    personaModelCurrentAlternativePersonaCount: Int,
    failedRunCount: Int
  ) -> ProductTournamentReadinessRecommendation {
    guard !completed.isEmpty else { return .gatherEvidence }

    let rejectedOrWeakCount = summaries.filter {
      $0.verdict == .rejected || $0.verdict == .weak
    }.count
    let strongOrPromisingCount = summaries.filter {
      $0.verdict == .strongPull || $0.verdict == .promising
    }.count
    let missingCount = completed.flatMap(\.missingCapabilities).count
    let repeatedObjections = repeatedObjectionCount(in: completed)
    let painRecognition = dimensionAverage(completed.compactMap(\.scores.painRecognition))
    let workflowImprovement = dimensionAverage(completed.compactMap(\.scores.workflowImprovement))
    let alternativeAdvantage = dimensionAverage(completed.compactMap(\.scores.alternativeAdvantage))
    let switchingReadiness = dimensionAverage(completed.compactMap(\.scores.switchingReadiness))
    let continuedUsePull = dimensionAverage(completed.compactMap(\.scores.continuedUsePull))
    let willingnessToPay = dimensionAverage(completed.compactMap(\.scores.willingnessToPay))
    let productPull =
      [workflowImprovement, alternativeAdvantage, switchingReadiness, continuedUsePull]
      .filter { $0 > 0 }
      .max() ?? 0

    if completed.count >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.1
        || rejectedOrWeakCount >= 2)
    {
      return personaModelDistinctPersonaCount >= 2
        && personaModelCurrentAlternativePersonaCount >= 2
        ? .kill
        : .gatherEvidence
    }
    if completed.count >= 2 && painRecognition >= 4 && productPull > 0 && productPull <= 2.8 {
      return .pivot
    }
    if completed.count >= 3
      && distinctPersonaCount >= 2
      && personaModelDistinctPersonaCount >= 2
      && personaModelCurrentAlternativePersonaCount >= 2
      && readinessScore >= 76
      && (willingnessToPay == 0 || willingnessToPay >= 3.2)
      && missingCount == 0
      && repeatedObjections == 0
      && strongOrPromisingCount >= 2
    {
      return .promote
    }
    if completed.count < 2 || distinctPersonaCount < 2 {
      return failedRunCount > completed.count ? .narrow : .gatherEvidence
    }
    if missingCount > 0 || repeatedObjections > 0 || readinessScore < 60 {
      return .narrow
    }
    return .keepGoing
  }

  private static func rationale(
    summaries: [ProductTournamentEvidenceSummary],
    completed: [ProductTournamentEvidenceSummary],
    readinessScore: Double,
    averageScore: Double,
    distinctPersonaCount: Int,
    personaModelCompletedRunCount: Int,
    personaModelDistinctPersonaCount: Int,
    currentAlternativeComparisonCount: Int,
    personaModelCurrentAlternativePersonaCount: Int,
    modelFreeCompletedRunCount: Int,
    failedRunCount: Int,
    recommendation: ProductTournamentReadinessRecommendation,
    proofDebt: ProductTournamentProofDebt
  ) -> [String] {
    var lines = [
      "\(completed.count) completed of \(summaries.count) run(s) across \(distinctPersonaCount) persona(s)."
    ]
    if averageScore > 0 {
      lines.append(
        "Average tournament score \(format(averageScore))/5; readiness \(format(readinessScore))/100."
      )
    } else {
      lines.append(
        "No persona scorecard is available yet; readiness depends on run status and verdicts.")
    }
    let missing = completed.flatMap(\.missingCapabilities)
      .map(\.normalizedProductTournamentEvidenceText)
      .filter { !$0.isEmpty }
    if !missing.isEmpty {
      lines.append("Missing capabilities: \(missing.prefix(3).joined(separator: ", ")).")
    }
    let repeatedObjections = repeatedObjections(in: completed)
    if !repeatedObjections.isEmpty {
      lines.append("Repeated objections: \(repeatedObjections.prefix(3).joined(separator: "; ")).")
    }
    if failedRunCount > 0 {
      lines.append("\(failedRunCount) failed run(s) reduce confidence in the evidence.")
    }
    let willingnessToPay = dimensionAverage(completed.compactMap(\.scores.willingnessToPay))
    lines.append(
      "\(personaModelCompletedRunCount) persona-model run(s) across \(personaModelDistinctPersonaCount) simulated user(s), \(modelFreeCompletedRunCount) model-free run(s)."
    )
    lines.append(
      "\(currentAlternativeComparisonCount) current-alternative comparison(s), including \(personaModelCurrentAlternativePersonaCount) persona-model simulated user(s)."
    )
    if willingnessToPay > 0 {
      lines.append("Average willingness to pay or sponsor \(format(willingnessToPay))/5.")
    }
    let isStopGate =
      completed.count >= 2
      && (readinessScore <= 40
        || averageScore > 0 && averageScore <= 2.5
        || summaries.contains { $0.verdict == .rejected })
    if personaModelCompletedRunCount == 0 && !completed.isEmpty {
      if isStopGate {
        lines.append(
          "No persona-model evidence has tested this contender yet; stopping requires simulated-user rejection."
        )
      } else {
        lines.append(
          "No persona-model evidence has tested this contender yet; promotion requires simulated-user pull."
        )
      }
    } else if personaModelDistinctPersonaCount < 2 && !completed.isEmpty {
      if isStopGate {
        lines.append(
          "Stopping a contender requires persona-model rejection evidence across at least 2 simulated users."
        )
      } else {
        lines.append(
          "Decisive tournament decisions require persona-model evidence across at least 2 simulated users."
        )
      }
    }
    if personaModelCurrentAlternativePersonaCount < 2 && !completed.isEmpty {
      if isStopGate {
        lines.append(
          "Stopping a contender requires current-alternative rejection proof from at least 2 persona-model simulated users."
        )
      } else {
        lines.append(
          "Decisive tournament decisions require current-alternative proof from at least 2 persona-model simulated users."
        )
      }
    }
    if !proofDebt.isClear {
      lines.append("Proof debt: \(proofDebt.summary).")
    }
    switch recommendation {
    case .promote:
      lines.append("Evidence breadth and pull are high enough to consider promotion.")
    case .kill:
      lines.append("Evidence is consistently weak enough to stop this contender.")
    case .pivot:
      lines.append("The pain is recognized, but this contender shape is not creating enough pull.")
    case .narrow:
      lines.append("Evidence points to a smaller next proof before broader investment.")
    case .keepGoing:
      lines.append("Signals are positive but need more proof before promotion.")
    case .gatherEvidence:
      lines.append("Run more scenarios before changing the tournament decision.")
    }
    return lines
  }

  private static func hasCurrentAlternativeProof(
    _ summary: ProductTournamentEvidenceSummary
  ) -> Bool {
    let comparison = summary.currentAlternativeComparison.normalizedProductTournamentEvidenceText
    guard !comparison.isEmpty else { return false }
    let lowercased = comparison.lowercased()
    return !lowercased.contains("did not address")
      && !lowercased.contains("no current-alternative comparison")
      && !lowercased.contains("no current alternative")
  }

  private static func roundedScore(_ value: Double, upperBound: Double) -> Double {
    let clamped = min(upperBound, max(0, value))
    return (clamped * 10).rounded() / 10
  }

  private static func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func dimensionAverage(_ values: [Int]) -> Double {
    average(values.map(Double.init))
  }

  private static func repeatedObjectionCount(
    in summaries: [ProductTournamentEvidenceSummary]
  ) -> Int {
    repeatedObjections(in: summaries).count
  }

  private static func repeatedObjections(
    in summaries: [ProductTournamentEvidenceSummary]
  ) -> [String] {
    let counts = Dictionary(
      grouping: summaries.flatMap(\.objections).map(\.normalizedProductTournamentEvidenceText),
      by: { $0 }
    )
    .mapValues(\.count)
    return
      counts
      .filter { !$0.key.isEmpty && $0.value > 1 }
      .sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
      }
      .map { "\($0.key) (\($0.value)x)" }
  }

  private static func verdictRank(_ verdict: ProductTournamentEvidenceVerdict) -> Int {
    switch verdict {
    case .rejected: return 0
    case .weak: return 1
    case .unclear: return 2
    case .promising: return 3
    case .strongPull: return 4
    }
  }

  private static func verdictContribution(_ verdict: ProductTournamentEvidenceVerdict) -> Double {
    switch verdict {
    case .strongPull: return 18
    case .promising: return 12
    case .unclear: return 0
    case .weak: return -12
    case .rejected: return -22
    }
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.1f", value)
  }
}

struct ProductTournamentRunFailure: Codable, Equatable, Sendable {
  var status: ProductTournamentRunStatus
  var message: String
  var stdout: String
  var stderr: String

  init(
    status: ProductTournamentRunStatus,
    message: String,
    stdout: String = "",
    stderr: String = ""
  ) {
    self.status = status
    self.message = StringUtils.boundedText(message, limit: 2_000)
    self.stdout = StringUtils.boundedText(stdout, limit: 4_000)
    self.stderr = StringUtils.boundedText(stderr, limit: 4_000)
  }
}

struct ProductTournamentEvidenceScores: Codable, Equatable, Sendable {
  var painRecognition: Int?
  var workflowImprovement: Int?
  var alternativeAdvantage: Int?
  var switchingReadiness: Int?
  var continuedUsePull: Int?
  var willingnessToPay: Int?

  init(
    painRecognition: Int? = nil,
    workflowImprovement: Int? = nil,
    alternativeAdvantage: Int? = nil,
    switchingReadiness: Int? = nil,
    continuedUsePull: Int? = nil,
    willingnessToPay: Int? = nil
  ) {
    self.painRecognition = Self.clamped(painRecognition)
    self.workflowImprovement = Self.clamped(workflowImprovement)
    self.alternativeAdvantage = Self.clamped(alternativeAdvantage)
    self.switchingReadiness = Self.clamped(switchingReadiness)
    self.continuedUsePull = Self.clamped(continuedUsePull)
    self.willingnessToPay = Self.clamped(willingnessToPay)
  }

  var hasScores: Bool {
    painRecognition != nil
      || workflowImprovement != nil
      || alternativeAdvantage != nil
      || switchingReadiness != nil
      || continuedUsePull != nil
      || willingnessToPay != nil
  }

  private static func clamped(_ value: Int?) -> Int? {
    value.map { min(5, max(1, $0)) }
  }
}

enum ProductTournamentEvidenceDecisionIntentOutcome: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case supportsTarget = "supports_target"
  case contradictsTarget = "contradicts_target"
  case inconclusive
}

struct ProductTournamentEvidenceDecisionIntentEvaluation: Codable, Equatable, Sendable {
  var outcome: ProductTournamentEvidenceDecisionIntentOutcome
  var rationale: String

  init(
    outcome: ProductTournamentEvidenceDecisionIntentOutcome,
    rationale: String
  ) {
    self.outcome = outcome
    self.rationale = StringUtils.boundedText(rationale, limit: 500)
  }
}

struct ProductTournamentEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
  static let supportedSchemaVersion = 1

  var id: String
  var schemaVersion: Int
  var projectID: String?
  var experimentID: String
  var contenderPlanID: String
  var painID: String
  var tournamentID: String?
  var roundID: String?
  var contenderID: String?
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductTournamentSimulationMode
  var decisionIntent: ProductTournamentSimulationDecisionIntent?
  var decisionIntentEvaluation: ProductTournamentEvidenceDecisionIntentEvaluation?
  var status: ProductTournamentRunStatus
  var startedAt: Double
  var endedAt: Double
  var traceHash: String?
  var traceArtifactPath: String?
  var feedbackArtifactPath: String?
  var transcriptArtifactPath: String?
  var summaryArtifactPath: String?
  var completedUseProof: Bool
  var promptVersions: [String]
  var personaActionRationales: [String]
  var model: String
  var scores: ProductTournamentEvidenceScores
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var willingnessToPayScore: Int?
  var sponsorshipIntent: String
  var verdict: ProductTournamentEvidenceVerdict
  var summary: String
  var failure: ProductTournamentRunFailure?

  private enum CodingKeys: String, CodingKey {
    case id
    case schemaVersion
    case projectID
    case experimentID
    case contenderPlanID
    case painID
    case tournamentID
    case roundID
    case contenderID
    case branchName
    case commitSha
    case scenarioID
    case personaID
    case mode
    case decisionIntent
    case decisionIntentEvaluation
    case status
    case startedAt
    case endedAt
    case traceHash
    case traceArtifactPath
    case feedbackArtifactPath
    case transcriptArtifactPath
    case summaryArtifactPath
    case completedUseProof
    case promptVersions
    case personaActionRationales
    case model
    case scores
    case objections
    case missingCapabilities
    case currentAlternativeComparison
    case willingnessToPayScore
    case sponsorshipIntent
    case verdict
    case summary
    case failure
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        ?? Self.supportedSchemaVersion,
      projectID: try container.decodeIfPresent(String.self, forKey: .projectID),
      experimentID: try container.decode(String.self, forKey: .experimentID),
      contenderPlanID: try container.decode(String.self, forKey: .contenderPlanID),
      painID: try container.decode(String.self, forKey: .painID),
      tournamentID: try container.decodeIfPresent(String.self, forKey: .tournamentID),
      roundID: try container.decodeIfPresent(String.self, forKey: .roundID),
      contenderID: try container.decodeIfPresent(String.self, forKey: .contenderID),
      branchName: try container.decode(String.self, forKey: .branchName),
      commitSha: try container.decode(String.self, forKey: .commitSha),
      scenarioID: try container.decode(String.self, forKey: .scenarioID),
      personaID: try container.decode(String.self, forKey: .personaID),
      mode: try container.decode(ProductTournamentSimulationMode.self, forKey: .mode),
      decisionIntent: try container.decodeIfPresent(
        ProductTournamentSimulationDecisionIntent.self,
        forKey: .decisionIntent
      ),
      decisionIntentEvaluation: try container.decodeIfPresent(
        ProductTournamentEvidenceDecisionIntentEvaluation.self,
        forKey: .decisionIntentEvaluation
      ),
      status: try container.decode(ProductTournamentRunStatus.self, forKey: .status),
      startedAt: try container.decode(Double.self, forKey: .startedAt),
      endedAt: try container.decode(Double.self, forKey: .endedAt),
      traceHash: try container.decodeIfPresent(String.self, forKey: .traceHash),
      traceArtifactPath: try container.decodeIfPresent(String.self, forKey: .traceArtifactPath),
      feedbackArtifactPath: try container.decodeIfPresent(
        String.self,
        forKey: .feedbackArtifactPath
      ),
      transcriptArtifactPath: try container.decodeIfPresent(
        String.self,
        forKey: .transcriptArtifactPath
      ),
      summaryArtifactPath: try container.decodeIfPresent(String.self, forKey: .summaryArtifactPath),
      completedUseProof: try container.decodeIfPresent(Bool.self, forKey: .completedUseProof)
        ?? false,
      promptVersions: try container.decodeIfPresent([String].self, forKey: .promptVersions) ?? [],
      model: try container.decodeIfPresent(String.self, forKey: .model) ?? "",
      scores: try container.decodeIfPresent(
        ProductTournamentEvidenceScores.self,
        forKey: .scores
      ) ?? ProductTournamentEvidenceScores(),
      objections: try container.decodeIfPresent([String].self, forKey: .objections) ?? [],
      missingCapabilities: try container.decodeIfPresent(
        [String].self,
        forKey: .missingCapabilities
      ) ?? [],
      currentAlternativeComparison: try container.decodeIfPresent(
        String.self,
        forKey: .currentAlternativeComparison
      ) ?? "",
      willingnessToPayScore: try container.decodeIfPresent(
        Int.self,
        forKey: .willingnessToPayScore
      ),
      sponsorshipIntent: try container.decodeIfPresent(
        String.self,
        forKey: .sponsorshipIntent
      ) ?? "",
      personaActionRationales: try container.decodeIfPresent(
        [String].self,
        forKey: .personaActionRationales
      ) ?? [],
      verdict: try container.decodeIfPresent(
        ProductTournamentEvidenceVerdict.self,
        forKey: .verdict
      ) ?? .unclear,
      summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "No summary.",
      failure: try container.decodeIfPresent(ProductTournamentRunFailure.self, forKey: .failure)
    )
  }

  init(
    id: String,
    schemaVersion: Int = Self.supportedSchemaVersion,
    projectID: String? = nil,
    experimentID: String,
    contenderPlanID: String,
    painID: String,
    tournamentID: String? = nil,
    roundID: String? = nil,
    contenderID: String? = nil,
    branchName: String,
    commitSha: String,
    scenarioID: String,
    personaID: String,
    mode: ProductTournamentSimulationMode,
    decisionIntent: ProductTournamentSimulationDecisionIntent? = nil,
    decisionIntentEvaluation: ProductTournamentEvidenceDecisionIntentEvaluation? = nil,
    status: ProductTournamentRunStatus,
    startedAt: Double,
    endedAt: Double,
    traceHash: String? = nil,
    traceArtifactPath: String? = nil,
    feedbackArtifactPath: String? = nil,
    transcriptArtifactPath: String? = nil,
    summaryArtifactPath: String? = nil,
    completedUseProof: Bool = false,
    promptVersions: [String] = [],
    model: String = "",
    scores: ProductTournamentEvidenceScores = ProductTournamentEvidenceScores(),
    objections: [String] = [],
    missingCapabilities: [String] = [],
    currentAlternativeComparison: String = "",
    willingnessToPayScore: Int? = nil,
    sponsorshipIntent: String = "",
    personaActionRationales: [String] = [],
    verdict: ProductTournamentEvidenceVerdict = .unclear,
    summary: String,
    failure: ProductTournamentRunFailure? = nil
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "product-tournament-run")
    self.schemaVersion = schemaVersion
    self.projectID = Self.optionalBounded(projectID, limit: 80)
    self.experimentID = Self.cleanedIdentifier(experimentID, fallback: "experiment")
    self.contenderPlanID = Self.cleanedIdentifier(
      contenderPlanID, fallback: "contender-plan")
    self.painID = Self.cleanedIdentifier(painID, fallback: "pain")
    self.tournamentID = Self.optionalIdentifier(tournamentID, fallback: "tournament")
    self.roundID = Self.optionalIdentifier(roundID, fallback: "round")
    self.contenderID = Self.optionalIdentifier(contenderID, fallback: "contender")
    self.branchName = StringUtils.boundedText(branchName, limit: 200)
    let boundedCommit = StringUtils.boundedText(commitSha, limit: 80)
    self.commitSha = boundedCommit.isEmpty ? "unknown" : boundedCommit
    self.scenarioID = Self.cleanedIdentifier(scenarioID, fallback: "scenario")
    self.personaID = Self.cleanedIdentifier(personaID, fallback: "persona")
    self.mode = mode
    self.decisionIntent = decisionIntent
    self.decisionIntentEvaluation =
      decisionIntentEvaluation
      ?? Self.derivedDecisionIntentEvaluation(
        intent: decisionIntent,
        status: status,
        verdict: verdict,
        scores: scores,
        missingCapabilities: missingCapabilities,
        currentAlternativeComparison: currentAlternativeComparison
      )
    self.status = status
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.traceHash = Self.optionalBounded(traceHash, limit: 128)
    self.traceArtifactPath = Self.optionalBounded(traceArtifactPath, limit: 500)
    self.feedbackArtifactPath = Self.optionalBounded(feedbackArtifactPath, limit: 500)
    self.transcriptArtifactPath = Self.optionalBounded(transcriptArtifactPath, limit: 500)
    self.summaryArtifactPath = Self.optionalBounded(summaryArtifactPath, limit: 500)
    self.completedUseProof = status == .completed && completedUseProof
    self.promptVersions = Self.cleanedList(promptVersions, limit: 160)
    self.personaActionRationales = Self.cleanedList(personaActionRationales, limit: 360)
    self.model = StringUtils.boundedText(model, limit: 160)
    self.scores = scores
    self.objections = Self.cleanedList(objections, limit: 500)
    self.missingCapabilities = Self.cleanedList(missingCapabilities, limit: 160)
    self.currentAlternativeComparison = StringUtils.boundedText(
      currentAlternativeComparison, limit: 1_000)
    self.willingnessToPayScore = Self.clampedScore(willingnessToPayScore)
    self.sponsorshipIntent = StringUtils.boundedText(sponsorshipIntent, limit: 700)
    self.verdict = verdict
    self.summary = StringUtils.boundedText(summary, limit: 1_500)
    self.failure = failure
  }

  init(
    runResult: ProductTournamentRunResult,
    tournamentScope: ProductTournamentEvidenceScope? = nil,
    id: String = UUID().uuidString,
    startedAt: Double,
    endedAt: Double
  ) {
    let traceSignals = runResult.tournamentTrace?.painReliefSignals
    let missing = traceSignals?.missingCapabilityIDs ?? []
    let comparison = Self.currentAlternativeComparison(from: traceSignals)
    let willingnessToPayScore = Self.derivedWillingnessToPayScore(
      status: runResult.status,
      signals: traceSignals
    )
    self.init(
      id: id,
      projectID: runResult.projectID?.uuidString,
      experimentID: runResult.experimentID,
      contenderPlanID: runResult.contenderPlanID,
      painID: runResult.painID,
      tournamentID: tournamentScope?.tournamentID,
      roundID: tournamentScope?.roundID,
      contenderID: tournamentScope?.contenderID ?? runResult.contenderID,
      branchName: runResult.branchName,
      commitSha: runResult.commitSha,
      scenarioID: runResult.scenarioID,
      personaID: runResult.personaID,
      mode: runResult.mode,
      decisionIntent: runResult.decisionIntent,
      status: runResult.status,
      startedAt: startedAt,
      endedAt: endedAt,
      traceHash: runResult.experienceTraceHash,
      completedUseProof: Self.completedUseProof(from: runResult.tournamentTrace),
      promptVersions: runResult.rawPersonaActionTranscript.map(\.promptVersionID)
        .productTournamentEvidenceUniquedPreservingOrder(),
      model: runResult.model,
      scores: Self.derivedScores(status: runResult.status, signals: traceSignals),
      objections: [],
      missingCapabilities: missing,
      currentAlternativeComparison: comparison,
      willingnessToPayScore: willingnessToPayScore,
      sponsorshipIntent: Self.sponsorshipIntent(
        from: traceSignals,
        willingnessToPayScore: willingnessToPayScore
      ),
      personaActionRationales: Self.personaActionRationales(
        from: runResult.rawPersonaActionTranscript
      ),
      verdict: Self.derivedVerdict(status: runResult.status, signals: traceSignals),
      summary: traceSignals?.evidenceSummary ?? runResult.failure?.message ?? "No summary.",
      failure: runResult.failure
    )
  }

  private static func currentAlternativeComparison(
    from signals: ProductTournamentPainReliefSignals?
  ) -> String {
    guard let signals else {
      return "The deterministic trace did not address the current alternative."
    }
    let explicit = signals.currentAlternativeComparison
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !explicit.isEmpty {
      return explicit
    }
    return signals.currentAlternativeAddressed
      ? "The deterministic trace addressed the current alternative."
      : "The deterministic trace did not address the current alternative."
  }

  private static func personaActionRationales(
    from transcript: [ProductTournamentPersonaActionTranscriptEntry]
  ) -> [String] {
    let lines = transcript.compactMap { entry -> String? in
      let rationale = StringUtils.boundedText(entry.rationale, limit: 260)
      guard !rationale.isEmpty else { return nil }
      let validity = entry.wasValid ? "valid" : "invalid"
      let actionID = StringUtils.boundedText(entry.chosenActionID, limit: 96)
      return
        "turn \(max(0, entry.turnIndex)) \(entry.phase.rawValue) \(validity) action \(actionID): \(rationale)"
    }
    return Array(cleanedList(lines, limit: 360).prefix(8))
  }

  private static func completedUseProof(from trace: ProductTournamentExperienceTrace?) -> Bool {
    guard let trace, trace.terminalStatus == .completed else { return false }
    let actionIDs = trace.turns.map(\.action.id)
    guard actionIDsContainCompletedUseSequence(actionIDs) else { return false }
    let missingCapabilityIDs = Set(
      trace.painReliefSignals.missingCapabilityIDs.map(\.normalizedProductTournamentEvidenceText)
    )
    return trace.painReliefSignals.painRecognized
      && trace.painReliefSignals.workflowAdvanced
      && trace.painReliefSignals.currentAlternativeAddressed
      && trace.painReliefSignals.switchingObjectionReduced
      && !missingCapabilityIDs.contains("workflow_advancement")
      && !missingCapabilityIDs.contains("workflow_completion")
  }

  private static let completedUseActionSequence = [
    "inspect_pain",
    "compare_current_alternative",
    "reduce_switching_objection",
    "start_contender_workflow",
    "provide_requested_input",
  ]

  private static func actionIDsContainCompletedUseSequence(_ actionIDs: [String]) -> Bool {
    var nextIndex = completedUseActionSequence.startIndex
    for actionID in actionIDs where actionID == completedUseActionSequence[nextIndex] {
      nextIndex = completedUseActionSequence.index(after: nextIndex)
      if nextIndex == completedUseActionSequence.endIndex {
        return true
      }
    }
    return false
  }

  private static func derivedDecisionIntentEvaluation(
    intent: ProductTournamentSimulationDecisionIntent?,
    status: ProductTournamentRunStatus,
    verdict: ProductTournamentEvidenceVerdict,
    scores: ProductTournamentEvidenceScores,
    missingCapabilities: [String],
    currentAlternativeComparison: String
  ) -> ProductTournamentEvidenceDecisionIntentEvaluation? {
    guard let intent else { return nil }
    guard status == .completed else {
      return ProductTournamentEvidenceDecisionIntentEvaluation(
        outcome: .inconclusive,
        rationale:
          "Run ended with status \(status.rawValue), so it did not answer the targeted \(intent.targetDecision.rawValue) decision."
      )
    }

    let missing = cleanedList(missingCapabilities, limit: 160)
    let hasMissingCapabilities = !missing.isEmpty
    let strongVerdict = verdict == .strongPull || verdict == .promising
    let weakVerdict = verdict == .weak || verdict == .rejected
    let productPullScores = [
      scores.workflowImprovement,
      scores.alternativeAdvantage,
      scores.switchingReadiness,
      scores.continuedUsePull,
      scores.willingnessToPay,
    ].compactMap { $0 }
    let productPullCeiling = productPullScores.max() ?? 0
    let productPullFloor = productPullScores.min() ?? 0
    let painRecognition = scores.painRecognition ?? 0
    let comparedAlternative = hasSubstantiveCurrentAlternativeComparison(
      currentAlternativeComparison
    )

    switch intent.targetDecision {
    case .promote, .promoted:
      if strongVerdict && !hasMissingCapabilities
        && (productPullFloor == 0 || productPullFloor >= 3)
      {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .supportsTarget,
          rationale:
            "The run produced \(verdict.rawValue) evidence without missing capabilities, supporting the targeted promotion proof."
        )
      }
      if weakVerdict || hasMissingCapabilities
        || (productPullCeiling > 0 && productPullCeiling <= 2)
      {
        let blocker =
          hasMissingCapabilities
          ? "missing \(missing.prefix(3).joined(separator: ", "))"
          : "weak pull"
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .contradictsTarget,
          rationale:
            "The targeted promotion proof was contradicted by \(verdict.rawValue) evidence and \(blocker)."
        )
      }
    case .kill, .archived:
      if weakVerdict || (productPullCeiling > 0 && productPullCeiling <= 2) {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .supportsTarget,
          rationale:
            "The run produced \(verdict.rawValue) evidence with weak contender pull, supporting the targeted stop decision."
        )
      }
      if strongVerdict && !hasMissingCapabilities
        && (productPullCeiling == 0 || productPullCeiling >= 3)
      {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .contradictsTarget,
          rationale:
            "The targeted stop decision was contradicted by \(verdict.rawValue) evidence and no missing capabilities."
        )
      }
    case .narrow:
      if hasMissingCapabilities || (productPullFloor > 0 && productPullFloor <= 2) {
        let pressure =
          hasMissingCapabilities
          ? "missing \(missing.prefix(3).joined(separator: ", "))"
          : "low scorecard pull"
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .supportsTarget,
          rationale:
            "The run exposed narrower scope pressure through \(pressure)."
        )
      }
      if verdict == .strongPull && !hasMissingCapabilities
        && (productPullFloor == 0 || productPullFloor >= 4)
      {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .contradictsTarget,
          rationale:
            "The targeted narrow decision was contradicted by strong pull without missing capabilities."
        )
      }
    case .pivot:
      if painRecognition >= 4 && productPullCeiling > 0 && productPullCeiling <= 2 {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .supportsTarget,
          rationale:
            "The pain was recognized, but the current product shape did not create enough pull."
        )
      }
      if strongVerdict && !hasMissingCapabilities
        && (productPullCeiling == 0 || productPullCeiling >= 4)
      {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .contradictsTarget,
          rationale:
            "The targeted pivot decision was contradicted by strong pull for the current product shape."
        )
      }
    case .keepGoing:
      if strongVerdict || verdict == .unclear || comparedAlternative {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .supportsTarget,
          rationale:
            "The run reduced uncertainty enough to support continuing the current product contender."
        )
      }
      if verdict == .rejected {
        return ProductTournamentEvidenceDecisionIntentEvaluation(
          outcome: .contradictsTarget,
          rationale: "The continue target was contradicted by rejected evidence."
        )
      }
    case .notRun:
      return ProductTournamentEvidenceDecisionIntentEvaluation(
        outcome: .supportsTarget,
        rationale:
          "The first targeted evidence run completed and moved the contender out of not-run state."
      )
    }

    return ProductTournamentEvidenceDecisionIntentEvaluation(
      outcome: .inconclusive,
      rationale:
        "The run produced \(verdict.rawValue) evidence, but it did not decisively answer the targeted \(intent.targetDecision.rawValue) decision."
    )
  }

  private static func hasSubstantiveCurrentAlternativeComparison(_ value: String) -> Bool {
    let normalized = value.normalizedProductTournamentEvidenceText
    guard !normalized.isEmpty else { return false }
    return !normalized.contains("did not address")
      && !normalized.contains("no current-alternative comparison")
      && !normalized.contains("no current alternative")
  }

  var summaryRecord: ProductTournamentEvidenceSummary {
    ProductTournamentEvidenceSummary(record: self)
  }

  static func cleanedIdentifier(_ value: String, fallback: String) -> String {
    let cleaned =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((cleaned.isEmpty ? fallback : cleaned).prefix(96))
  }

  static func cleanedList(_ values: [String], limit: Int) -> [String] {
    values
      .map { StringUtils.boundedText($0, limit: limit) }
      .filter { !$0.isEmpty }
      .productTournamentEvidenceUniquedPreservingOrder()
  }

  static func optionalBounded(_ value: String?, limit: Int) -> String? {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }

  static func optionalIdentifier(_ value: String?, fallback: String) -> String? {
    guard let value else { return nil }
    let cleaned = cleanedIdentifier(value, fallback: fallback)
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func clampedScore(_ value: Int?) -> Int? {
    value.map { min(5, max(1, $0)) }
  }

  private static func derivedScores(
    status: ProductTournamentRunStatus,
    signals: ProductTournamentPainReliefSignals?
  ) -> ProductTournamentEvidenceScores {
    guard status == .completed, let signals else {
      return ProductTournamentEvidenceScores()
    }
    let missingPenalty = signals.missingCapabilityIDs.isEmpty ? 0 : 1
    let positiveWithPenalty = max(2, 4 - missingPenalty)
    return ProductTournamentEvidenceScores(
      painRecognition: signals.painRecognized ? 4 : 1,
      workflowImprovement: signals.workflowAdvanced ? positiveWithPenalty : 2,
      alternativeAdvantage: signals.currentAlternativeAddressed ? positiveWithPenalty : 2,
      switchingReadiness: signals.switchingObjectionReduced ? positiveWithPenalty : 2,
      continuedUsePull: continuedUsePullScore(signals: signals),
      willingnessToPay: derivedWillingnessToPayScore(status: status, signals: signals)
    )
  }

  private static func continuedUsePullScore(signals: ProductTournamentPainReliefSignals) -> Int {
    if signals.workflowAdvanced && signals.currentAlternativeAddressed
      && signals.missingCapabilityIDs.isEmpty
    {
      return 4
    }
    if signals.workflowAdvanced {
      return 3
    }
    return 2
  }

  private static func derivedWillingnessToPayScore(
    status: ProductTournamentRunStatus,
    signals: ProductTournamentPainReliefSignals?
  ) -> Int? {
    guard status == .completed, let signals else { return nil }
    if let explicit = clampedScore(signals.willingnessToPayScore) {
      return explicit
    }
    if signals.workflowAdvanced && signals.currentAlternativeAddressed
      && signals.switchingObjectionReduced && signals.missingCapabilityIDs.isEmpty
    {
      return 4
    }
    if signals.workflowAdvanced && signals.switchingObjectionReduced {
      return 3
    }
    if signals.painRecognized || signals.workflowAdvanced {
      return 2
    }
    return 1
  }

  private static func sponsorshipIntent(
    from signals: ProductTournamentPainReliefSignals?,
    willingnessToPayScore: Int?
  ) -> String {
    guard let signals else { return "" }
    let explicit = signals.sponsorshipIntent.trimmingCharacters(in: .whitespacesAndNewlines)
    if !explicit.isEmpty {
      return explicit
    }
    guard let willingnessToPayScore else { return "" }
    switch willingnessToPayScore {
    case 4...:
      return "The simulated user shows strong willingness to pay for or sponsor this contender."
    case 3:
      return
        "The simulated user shows moderate willingness to pay for or sponsor this contender after more proof."
    case 2:
      return
        "The simulated user recognizes some contender value but is not ready to pay or sponsor."
    default:
      return "The simulated user shows weak willingness to pay for or sponsor this contender."
    }
  }

  private static func derivedVerdict(
    status: ProductTournamentRunStatus,
    signals: ProductTournamentPainReliefSignals?
  ) -> ProductTournamentEvidenceVerdict {
    guard status == .completed, let signals else { return .unclear }
    guard signals.painRecognized, signals.workflowAdvanced else { return .weak }
    guard signals.missingCapabilityIDs.isEmpty else { return .unclear }
    return signals.currentAlternativeAddressed ? .promising : .unclear
  }
}

struct ProductTournamentEvidenceSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var runID: String
  var experimentID: String
  var contenderPlanID: String
  var painID: String
  var tournamentID: String?
  var roundID: String?
  var contenderID: String?
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductTournamentSimulationMode
  var decisionIntent: ProductTournamentSimulationDecisionIntent?
  var decisionIntentEvaluation: ProductTournamentEvidenceDecisionIntentEvaluation?
  var status: ProductTournamentRunStatus
  var startedAt: Double
  var endedAt: Double
  var model: String
  var verdict: ProductTournamentEvidenceVerdict
  var scores: ProductTournamentEvidenceScores
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var willingnessToPayScore: Int?
  var sponsorshipIntent: String
  var personaActionRationales: [String]
  var traceHash: String?
  var completedUseProof: Bool
  var summary: String
  var failureKind: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case runID
    case experimentID
    case contenderPlanID
    case painID
    case tournamentID
    case roundID
    case contenderID
    case branchName
    case commitSha
    case scenarioID
    case personaID
    case mode
    case decisionIntent
    case decisionIntentEvaluation
    case status
    case startedAt
    case endedAt
    case model
    case verdict
    case scores
    case objections
    case missingCapabilities
    case currentAlternativeComparison
    case willingnessToPayScore
    case sponsorshipIntent
    case personaActionRationales
    case traceHash
    case completedUseProof
    case summary
    case failureKind
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    runID = try container.decodeIfPresent(String.self, forKey: .runID) ?? id
    experimentID = try container.decode(String.self, forKey: .experimentID)
    contenderPlanID = try container.decode(String.self, forKey: .contenderPlanID)
    painID = try container.decode(String.self, forKey: .painID)
    tournamentID = try container.decodeIfPresent(String.self, forKey: .tournamentID)
    roundID = try container.decodeIfPresent(String.self, forKey: .roundID)
    contenderID = try container.decodeIfPresent(String.self, forKey: .contenderID)
    branchName = try container.decode(String.self, forKey: .branchName)
    commitSha = try container.decode(String.self, forKey: .commitSha)
    scenarioID = try container.decode(String.self, forKey: .scenarioID)
    personaID = try container.decode(String.self, forKey: .personaID)
    mode = try container.decode(ProductTournamentSimulationMode.self, forKey: .mode)
    decisionIntent = try container.decodeIfPresent(
      ProductTournamentSimulationDecisionIntent.self,
      forKey: .decisionIntent
    )
    decisionIntentEvaluation = try container.decodeIfPresent(
      ProductTournamentEvidenceDecisionIntentEvaluation.self,
      forKey: .decisionIntentEvaluation
    )
    status = try container.decode(ProductTournamentRunStatus.self, forKey: .status)
    startedAt = try container.decode(Double.self, forKey: .startedAt)
    endedAt = try container.decode(Double.self, forKey: .endedAt)
    model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
    verdict =
      try container.decodeIfPresent(ProductTournamentEvidenceVerdict.self, forKey: .verdict)
      ?? .unclear
    scores =
      try container.decodeIfPresent(ProductTournamentEvidenceScores.self, forKey: .scores)
      ?? ProductTournamentEvidenceScores()
    objections = try container.decodeIfPresent([String].self, forKey: .objections) ?? []
    missingCapabilities =
      try container.decodeIfPresent([String].self, forKey: .missingCapabilities) ?? []
    currentAlternativeComparison =
      try container.decodeIfPresent(String.self, forKey: .currentAlternativeComparison) ?? ""
    willingnessToPayScore = try container.decodeIfPresent(Int.self, forKey: .willingnessToPayScore)
      .map { min(5, max(1, $0)) }
    sponsorshipIntent = try container.decodeIfPresent(String.self, forKey: .sponsorshipIntent) ?? ""
    personaActionRationales =
      try container.decodeIfPresent([String].self, forKey: .personaActionRationales) ?? []
    traceHash = try container.decodeIfPresent(String.self, forKey: .traceHash)
    completedUseProof =
      try container.decodeIfPresent(Bool.self, forKey: .completedUseProof)
      ?? false
    summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? "No summary."
    failureKind = try container.decodeIfPresent(String.self, forKey: .failureKind)
  }

  init(record: ProductTournamentEvidenceRecord) {
    id = record.id
    runID = record.id
    experimentID = record.experimentID
    contenderPlanID = record.contenderPlanID
    painID = record.painID
    tournamentID = record.tournamentID
    roundID = record.roundID
    contenderID = record.contenderID
    branchName = record.branchName
    commitSha = record.commitSha
    scenarioID = record.scenarioID
    personaID = record.personaID
    mode = record.mode
    decisionIntent = record.decisionIntent
    decisionIntentEvaluation = record.decisionIntentEvaluation
    status = record.status
    startedAt = record.startedAt
    endedAt = record.endedAt
    model = record.model
    verdict = record.verdict
    scores = record.scores
    objections = record.objections
    missingCapabilities = record.missingCapabilities
    currentAlternativeComparison = record.currentAlternativeComparison
    willingnessToPayScore = record.willingnessToPayScore
    sponsorshipIntent = record.sponsorshipIntent
    personaActionRationales = record.personaActionRationales
    traceHash = record.traceHash
    completedUseProof = record.completedUseProof
    summary = record.summary
    failureKind = record.failure?.status.rawValue
  }

  var isCompleted: Bool {
    status == .completed
  }
}

enum ProductTournamentPlanRecommendation: String, Codable, CaseIterable, Equatable, Sendable {
  case gatherEvidence = "gather_evidence"
  case advanceToFeasibility = "advance_to_feasibility"
  case revisePlan = "revise_plan"
  case eliminate

  var title: String {
    switch self {
    case .gatherEvidence: return "Gather Evidence"
    case .advanceToFeasibility: return "Advance"
    case .revisePlan: return "Revise"
    case .eliminate: return "Eliminate"
    }
  }
}

struct ProductTournamentPlanProofDebt: Codable, Equatable, Sendable {
  var evaluationDeficit: Int
  var personaDeficit: Int
  var buyerOrSponsorDeficit: Int
  var willingnessToPayDeficit: Int

  var isClear: Bool {
    blockingDebtCount == 0
  }

  var hasActionableFocusedProof: Bool {
    !isClear
  }

  var hasCoverageDebt: Bool {
    evaluationDeficit + personaDeficit + buyerOrSponsorDeficit > 0
  }

  var blockingDebtCount: Int {
    evaluationDeficit + personaDeficit + buyerOrSponsorDeficit + willingnessToPayDeficit
  }

  var summary: String {
    let labels = debtLabels
    guard !labels.isEmpty else { return "plan proof complete" }
    return labels.joined(separator: ", ")
  }

  var focusedActionTitle: String {
    if isClear {
      return "Proof Complete"
    }
    if evaluationDeficit > 1 && personaDeficit > 1 && buyerOrSponsorDeficit > 0 {
      return "Run Plan Proof"
    }
    if buyerOrSponsorDeficit > 0 {
      return "Run Buyer Proof"
    }
    if personaDeficit > 0 {
      return "Run Persona Proof"
    }
    if evaluationDeficit > 0 {
      return "Run Plan Proof"
    }
    if willingnessToPayDeficit > 0 {
      return "Run Price/ROI Proof"
    }
    return "Run Proof Target"
  }

  var nextProofTargetSummary: String {
    if isClear {
      return "Round 2 feasibility transition"
    }
    if evaluationDeficit > 1 && personaDeficit > 1 && buyerOrSponsorDeficit > 0 {
      return "operator and economic-buyer plan evaluations"
    }
    if buyerOrSponsorDeficit > 0 {
      return "economic-buyer simulated-user plan evaluation"
    }
    if personaDeficit > 0 {
      return "new distinct simulated-user plan evaluation"
    }
    if evaluationDeficit > 0 {
      return "additional plan evaluation"
    }
    if willingnessToPayDeficit > 0 {
      return "price and ROI willingness-to-pay proof"
    }
    return "plan proof review"
  }

  var debtLabels: [String] {
    var labels: [String] = []
    if evaluationDeficit > 0 {
      labels.append("\(evaluationDeficit) plan evaluation(s)")
    }
    if personaDeficit > 0 {
      labels.append("\(personaDeficit) simulated-user persona(s)")
    }
    if buyerOrSponsorDeficit > 0 {
      labels.append("\(buyerOrSponsorDeficit) buyer/sponsor signal(s)")
    }
    if willingnessToPayDeficit > 0 {
      labels.append("willingness to pay at least 3.2/5")
    }
    return labels
  }

  init(
    completedEvaluationCount: Int,
    distinctPersonaCount: Int,
    buyerOrSponsorPersonaCount: Int,
    averageWillingnessToPayScore: Double,
    minimumCompletedEvaluations: Int = 2,
    minimumPersonaCount: Int = 2,
    minimumBuyerOrSponsorPersonaCount: Int = 1,
    minimumWillingnessToPayScore: Double = 3.2
  ) {
    self.evaluationDeficit = max(0, minimumCompletedEvaluations - completedEvaluationCount)
    self.personaDeficit = max(0, minimumPersonaCount - distinctPersonaCount)
    self.buyerOrSponsorDeficit = max(
      0,
      minimumBuyerOrSponsorPersonaCount - buyerOrSponsorPersonaCount
    )
    self.willingnessToPayDeficit =
      averageWillingnessToPayScore >= minimumWillingnessToPayScore ? 0 : 1
  }

  init(
    evaluationDeficit: Int,
    personaDeficit: Int,
    buyerOrSponsorDeficit: Int,
    willingnessToPayDeficit: Int
  ) {
    self.evaluationDeficit = max(0, evaluationDeficit)
    self.personaDeficit = max(0, personaDeficit)
    self.buyerOrSponsorDeficit = max(0, buyerOrSponsorDeficit)
    self.willingnessToPayDeficit = max(0, willingnessToPayDeficit)
  }
}

struct ProductTournamentPlanReadiness: Codable, Equatable, Identifiable, Sendable {
  var id: String { contenderID }

  var contenderID: String
  var tournamentID: String
  var roundID: String
  var evaluationCount: Int
  var completedEvaluationCount: Int
  var personaModelEvaluationCount: Int
  var modelFreeEvaluationCount: Int
  var distinctPersonaCount: Int
  var buyerOrSponsorPersonaCount: Int
  var latestEvaluationID: String?
  var readinessScore: Double
  var averageScore: Double
  var averageWillingnessToPayScore: Double
  var estimatedMonthlyPriceCents: Int?
  var strongestVerdict: ProductTournamentEvidenceVerdict
  var weakestVerdict: ProductTournamentEvidenceVerdict
  var recommendation: ProductTournamentPlanRecommendation
  var planProofDebt: ProductTournamentPlanProofDebt
  var rationale: [String]
  var evaluationIDs: [String]

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var nextProofTargetSummary: String {
    planProofDebt.nextProofTargetSummary
  }

  var commercialProofSummary: String {
    Self.commercialProofSummary(
      completedEvaluationCount: completedEvaluationCount,
      buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
      averageWillingnessToPayScore: averageWillingnessToPayScore,
      estimatedMonthlyPriceCents: estimatedMonthlyPriceCents,
      planProofDebt: planProofDebt
    )
  }

  init(
    contenderID: String,
    tournamentID: String,
    roundID: String,
    evaluationCount: Int,
    completedEvaluationCount: Int,
    personaModelEvaluationCount: Int = 0,
    modelFreeEvaluationCount: Int = 0,
    distinctPersonaCount: Int,
    buyerOrSponsorPersonaCount: Int,
    latestEvaluationID: String?,
    readinessScore: Double,
    averageScore: Double,
    averageWillingnessToPayScore: Double,
    estimatedMonthlyPriceCents: Int?,
    strongestVerdict: ProductTournamentEvidenceVerdict,
    weakestVerdict: ProductTournamentEvidenceVerdict,
    recommendation: ProductTournamentPlanRecommendation,
    planProofDebt: ProductTournamentPlanProofDebt? = nil,
    rationale: [String],
    evaluationIDs: [String]
  ) {
    self.contenderID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      contenderID,
      fallback: "contender"
    )
    self.tournamentID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      tournamentID,
      fallback: "tournament"
    )
    self.roundID = ProductTournamentEvidenceRecord.cleanedIdentifier(roundID, fallback: "round")
    self.evaluationCount = max(0, evaluationCount)
    self.completedEvaluationCount = max(0, completedEvaluationCount)
    self.personaModelEvaluationCount = max(0, personaModelEvaluationCount)
    self.modelFreeEvaluationCount = max(0, modelFreeEvaluationCount)
    self.distinctPersonaCount = max(0, distinctPersonaCount)
    self.buyerOrSponsorPersonaCount = max(0, buyerOrSponsorPersonaCount)
    self.latestEvaluationID = ProductTournamentEvidenceRecord.optionalBounded(
      latestEvaluationID,
      limit: 96
    )
    self.readinessScore = Self.roundedScore(readinessScore, upperBound: 100)
    self.averageScore = Self.roundedScore(averageScore, upperBound: 5)
    self.averageWillingnessToPayScore = Self.roundedScore(
      averageWillingnessToPayScore,
      upperBound: 5
    )
    self.estimatedMonthlyPriceCents = estimatedMonthlyPriceCents.map { max(0, $0) }
    self.strongestVerdict = strongestVerdict
    self.weakestVerdict = weakestVerdict
    self.recommendation = recommendation
    self.planProofDebt =
      planProofDebt
      ?? ProductTournamentPlanProofDebt(
        completedEvaluationCount: self.completedEvaluationCount,
        distinctPersonaCount: self.distinctPersonaCount,
        buyerOrSponsorPersonaCount: self.buyerOrSponsorPersonaCount,
        averageWillingnessToPayScore: self.averageWillingnessToPayScore
      )
    self.rationale = ProductTournamentEvidenceRecord.cleanedList(rationale, limit: 260)
    self.evaluationIDs = ProductTournamentEvidenceRecord.cleanedList(evaluationIDs, limit: 96)
  }

  private enum CodingKeys: String, CodingKey {
    case contenderID
    case tournamentID
    case roundID
    case evaluationCount
    case completedEvaluationCount
    case personaModelEvaluationCount
    case modelFreeEvaluationCount
    case distinctPersonaCount
    case buyerOrSponsorPersonaCount
    case latestEvaluationID
    case readinessScore
    case averageScore
    case averageWillingnessToPayScore
    case estimatedMonthlyPriceCents
    case strongestVerdict
    case weakestVerdict
    case recommendation
    case planProofDebt
    case rationale
    case evaluationIDs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let completedEvaluationCount =
      try container.decodeIfPresent(Int.self, forKey: .completedEvaluationCount) ?? 0
    let distinctPersonaCount =
      try container.decodeIfPresent(Int.self, forKey: .distinctPersonaCount) ?? 0
    let buyerOrSponsorPersonaCount =
      try container.decodeIfPresent(Int.self, forKey: .buyerOrSponsorPersonaCount) ?? 0
    let averageWillingnessToPayScore =
      try container.decodeIfPresent(Double.self, forKey: .averageWillingnessToPayScore) ?? 0
    self.init(
      contenderID: try container.decode(String.self, forKey: .contenderID),
      tournamentID: try container.decode(String.self, forKey: .tournamentID),
      roundID: try container.decode(String.self, forKey: .roundID),
      evaluationCount: try container.decodeIfPresent(Int.self, forKey: .evaluationCount) ?? 0,
      completedEvaluationCount: completedEvaluationCount,
      personaModelEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .personaModelEvaluationCount
      ) ?? 0,
      modelFreeEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .modelFreeEvaluationCount
      ) ?? 0,
      distinctPersonaCount: distinctPersonaCount,
      buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
      latestEvaluationID: try container.decodeIfPresent(String.self, forKey: .latestEvaluationID),
      readinessScore: try container.decodeIfPresent(Double.self, forKey: .readinessScore) ?? 0,
      averageScore: try container.decodeIfPresent(Double.self, forKey: .averageScore) ?? 0,
      averageWillingnessToPayScore: averageWillingnessToPayScore,
      estimatedMonthlyPriceCents: try container.decodeIfPresent(
        Int.self,
        forKey: .estimatedMonthlyPriceCents
      ),
      strongestVerdict: try container.decodeIfPresent(
        ProductTournamentEvidenceVerdict.self,
        forKey: .strongestVerdict
      ) ?? .unclear,
      weakestVerdict: try container.decodeIfPresent(
        ProductTournamentEvidenceVerdict.self,
        forKey: .weakestVerdict
      ) ?? .unclear,
      recommendation: try container.decodeIfPresent(
        ProductTournamentPlanRecommendation.self,
        forKey: .recommendation
      ) ?? .gatherEvidence,
      planProofDebt: try container.decodeIfPresent(
        ProductTournamentPlanProofDebt.self,
        forKey: .planProofDebt
      ),
      rationale: try container.decodeIfPresent([String].self, forKey: .rationale) ?? [],
      evaluationIDs: try container.decodeIfPresent([String].self, forKey: .evaluationIDs) ?? []
    )
  }

  init(summaries rawSummaries: [ProductTournamentPlanEvaluationSummary]) {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.evaluationID < rhs.evaluationID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let personaModelEvaluationCount = completed.filter { $0.mode == .personaModel }.count
    let modelFreeEvaluationCount = completed.filter { $0.mode == .modelFree }.count
    let personaCount = Set(completed.map(\.personaID).filter { !$0.isEmpty }).count
    let scoreValues = completed.flatMap { summary in
      [
        summary.scores.painRecognition,
        summary.scores.workflowImprovement,
        summary.scores.alternativeAdvantage,
        summary.scores.switchingReadiness,
        summary.scores.continuedUsePull,
      ].compactMap { $0 }.map(Double.init)
    }
    let averageScore = Self.average(scoreValues)
    let willingnessValues = completed.compactMap(\.willingnessToPayScore).map(Double.init)
    let averageWillingness = Self.average(willingnessValues)
    let estimatedMonthlyPriceCents = Self.estimatedMonthlyPriceCents(completed)
    let buyerOrSponsorPersonaCount = Self.buyerOrSponsorPersonaCount(in: completed)
    let planProofDebt = ProductTournamentPlanProofDebt(
      completedEvaluationCount: completed.count,
      distinctPersonaCount: personaCount,
      buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
      averageWillingnessToPayScore: averageWillingness
    )
    let readinessScore = Self.readinessScore(
      completed: completed,
      averageScore: averageScore,
      averageWillingnessToPayScore: averageWillingness,
      distinctPersonaCount: personaCount
    )
    let strongest =
      summaries.map(\.verdict).max(by: { Self.verdictRank($0) < Self.verdictRank($1) })
      ?? .unclear
    let weakest =
      summaries.map(\.verdict).min(by: { Self.verdictRank($0) < Self.verdictRank($1) })
      ?? .unclear
    let recommendation = Self.recommendation(
      completed: completed,
      readinessScore: readinessScore,
      averageScore: averageScore,
      averageWillingnessToPayScore: averageWillingness,
      distinctPersonaCount: personaCount,
      planProofDebt: planProofDebt
    )

    self.init(
      contenderID: summaries.first?.contenderID ?? "contender",
      tournamentID: summaries.first?.tournamentID ?? "tournament",
      roundID: summaries.first?.roundID ?? "round",
      evaluationCount: summaries.count,
      completedEvaluationCount: completed.count,
      personaModelEvaluationCount: personaModelEvaluationCount,
      modelFreeEvaluationCount: modelFreeEvaluationCount,
      distinctPersonaCount: personaCount,
      buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
      latestEvaluationID: summaries.first?.evaluationID,
      readinessScore: readinessScore,
      averageScore: averageScore,
      averageWillingnessToPayScore: averageWillingness,
      estimatedMonthlyPriceCents: estimatedMonthlyPriceCents,
      strongestVerdict: strongest,
      weakestVerdict: weakest,
      recommendation: recommendation,
      planProofDebt: planProofDebt,
      rationale: Self.rationale(
        completed: completed,
        readinessScore: readinessScore,
        averageScore: averageScore,
        averageWillingnessToPayScore: averageWillingness,
        distinctPersonaCount: personaCount,
        buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
        personaModelEvaluationCount: personaModelEvaluationCount,
        modelFreeEvaluationCount: modelFreeEvaluationCount,
        estimatedMonthlyPriceCents: estimatedMonthlyPriceCents,
        planProofDebt: planProofDebt,
        recommendation: recommendation
      ),
      evaluationIDs: summaries.prefix(8).map(\.evaluationID)
    )
  }

  private static func readinessScore(
    completed: [ProductTournamentPlanEvaluationSummary],
    averageScore: Double,
    averageWillingnessToPayScore: Double,
    distinctPersonaCount: Int
  ) -> Double {
    var score = 0.0
    switch completed.count {
    case 3...: score += 18
    case 2: score += 12
    case 1: score += 7
    default: break
    }
    switch distinctPersonaCount {
    case 3...: score += 14
    case 2: score += 10
    case 1: score += 4
    default: break
    }
    if averageScore > 0 {
      score += max(0, min(34, ((averageScore - 1) / 4) * 34))
    }
    if averageWillingnessToPayScore > 0 {
      score += max(0, min(22, ((averageWillingnessToPayScore - 1) / 4) * 22))
    }
    score += Self.average(completed.map { Self.verdictContribution($0.verdict) })
    score -= Double(min(14, Self.repeatedObjectionCount(in: completed) * 4))
    score -= Double(min(12, completed.flatMap(\.missingCapabilities).count * 3))
    return Self.roundedScore(score, upperBound: 100)
  }

  private static func recommendation(
    completed: [ProductTournamentPlanEvaluationSummary],
    readinessScore: Double,
    averageScore: Double,
    averageWillingnessToPayScore: Double,
    distinctPersonaCount: Int,
    planProofDebt: ProductTournamentPlanProofDebt
  ) -> ProductTournamentPlanRecommendation {
    guard !completed.isEmpty else { return .gatherEvidence }
    let weakCount = completed.filter { $0.verdict == .weak || $0.verdict == .rejected }.count
    let strongCount = completed.filter { $0.verdict == .strongPull || $0.verdict == .promising }
      .count
    if completed.count >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.2 || weakCount >= 2)
    {
      return .eliminate
    }
    if planProofDebt.hasCoverageDebt {
      return .gatherEvidence
    }
    if completed.count >= 2
      && distinctPersonaCount >= 2
      && planProofDebt.isClear
      && readinessScore >= 66
      && averageWillingnessToPayScore >= 3.2
      && strongCount >= 2
    {
      return .advanceToFeasibility
    }
    if completed.count < 2 || distinctPersonaCount < 2 {
      return .gatherEvidence
    }
    return .revisePlan
  }

  private static func rationale(
    completed: [ProductTournamentPlanEvaluationSummary],
    readinessScore: Double,
    averageScore: Double,
    averageWillingnessToPayScore: Double,
    distinctPersonaCount: Int,
    buyerOrSponsorPersonaCount: Int,
    personaModelEvaluationCount: Int,
    modelFreeEvaluationCount: Int,
    estimatedMonthlyPriceCents: Int?,
    planProofDebt: ProductTournamentPlanProofDebt,
    recommendation: ProductTournamentPlanRecommendation
  ) -> [String] {
    var lines = [
      "\(completed.count) completed plan evaluation(s) across \(distinctPersonaCount) persona(s)."
    ]
    if averageScore > 0 {
      lines.append(
        "Average plan score \(Self.format(averageScore))/5; readiness \(Self.format(readinessScore))/100."
      )
    }
    if averageWillingnessToPayScore > 0 {
      lines.append("Average willingness to pay \(Self.format(averageWillingnessToPayScore))/5.")
    }
    lines.append(
      "\(personaModelEvaluationCount) persona-model and \(modelFreeEvaluationCount) model-free plan evaluation(s)."
    )
    lines.append("\(buyerOrSponsorPersonaCount) buyer/sponsor simulated-user signal(s).")
    let commercialProof = Self.commercialProofSummary(
      completedEvaluationCount: completed.count,
      buyerOrSponsorPersonaCount: buyerOrSponsorPersonaCount,
      averageWillingnessToPayScore: averageWillingnessToPayScore,
      estimatedMonthlyPriceCents: estimatedMonthlyPriceCents,
      planProofDebt: planProofDebt
    )
    lines.append(
      "Commercial proof: \(commercialProof)."
    )
    if !planProofDebt.isClear {
      lines.append("Plan proof debt: \(planProofDebt.summary).")
    }
    lines.append("Next plan proof target: \(planProofDebt.nextProofTargetSummary).")
    let repeated = Self.repeatedObjections(in: completed)
    if !repeated.isEmpty {
      lines.append("Repeated objections: \(repeated.prefix(3).joined(separator: "; ")).")
    }
    switch recommendation {
    case .advanceToFeasibility:
      lines.append("Plan evidence is strong enough to consider Round 2 feasibility work.")
    case .eliminate:
      lines.append("Plan evidence is weak enough to eliminate or substantially reframe.")
    case .revisePlan:
      lines.append("Plan evidence points to revisions before implementation.")
    case .gatherEvidence:
      lines.append("Run more plan evaluations before advancing or eliminating.")
    }
    return lines
  }

  private static func commercialProofSummary(
    completedEvaluationCount: Int,
    buyerOrSponsorPersonaCount: Int,
    averageWillingnessToPayScore: Double,
    estimatedMonthlyPriceCents: Int?,
    planProofDebt: ProductTournamentPlanProofDebt
  ) -> String {
    guard completedEvaluationCount > 0 else {
      return "no willingness-to-pay proof yet"
    }
    let payLabel = "\(format(averageWillingnessToPayScore))/5"
    let priceText = estimatedMonthlyPriceCents.map { " at \(priceLabel(cents: $0))" } ?? ""
    if buyerOrSponsorPersonaCount == 0 {
      return "needs buyer/sponsor price and ROI proof; willingness to pay \(payLabel)\(priceText)"
    }
    if planProofDebt.willingnessToPayDeficit > 0 {
      return "needs stronger price and ROI proof; willingness to pay \(payLabel)\(priceText)"
    }
    if let estimatedMonthlyPriceCents {
      return
        "buyer/sponsor willingness to pay \(payLabel) at \(priceLabel(cents: estimatedMonthlyPriceCents))"
    }
    return "buyer/sponsor willingness to pay \(payLabel); price not estimated"
  }

  private static func estimatedMonthlyPriceCents(
    _ summaries: [ProductTournamentPlanEvaluationSummary]
  ) -> Int? {
    let prices = summaries.compactMap(\.estimatedMonthlyPriceCents).filter { $0 > 0 }
    guard !prices.isEmpty else { return nil }
    return prices.reduce(0, +) / prices.count
  }

  private static func buyerOrSponsorPersonaCount(
    in summaries: [ProductTournamentPlanEvaluationSummary]
  ) -> Int {
    let personas = summaries.filter(Self.isBuyerOrSponsorSignal)
      .map(\.personaID)
      .filter { !$0.isEmpty }
    return Set(personas).count
  }

  private static func isBuyerOrSponsorSignal(
    _ summary: ProductTournamentPlanEvaluationSummary
  ) -> Bool {
    ProductTournamentPlanPersonaSignals.isBuyerOrSponsor(
      personaID: summary.personaID,
      personaName: summary.personaName
    )
  }

  private static func repeatedObjectionCount(
    in summaries: [ProductTournamentPlanEvaluationSummary]
  ) -> Int {
    repeatedObjections(in: summaries).count
  }

  private static func repeatedObjections(
    in summaries: [ProductTournamentPlanEvaluationSummary]
  ) -> [String] {
    let counts = Dictionary(
      grouping: summaries.flatMap(\.objections).map(\.normalizedProductTournamentEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    return
      counts
      .filter { !$0.key.isEmpty && $0.value > 1 }
      .sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
      }
      .map { "\($0.key) (\($0.value)x)" }
  }

  private static func verdictRank(_ verdict: ProductTournamentEvidenceVerdict) -> Int {
    switch verdict {
    case .rejected: return 0
    case .weak: return 1
    case .unclear: return 2
    case .promising: return 3
    case .strongPull: return 4
    }
  }

  private static func verdictContribution(_ verdict: ProductTournamentEvidenceVerdict) -> Double {
    switch verdict {
    case .strongPull: return 12
    case .promising: return 8
    case .unclear: return 0
    case .weak: return -8
    case .rejected: return -14
    }
  }

  private static func roundedScore(_ value: Double, upperBound: Double) -> Double {
    let clamped = min(upperBound, max(0, value))
    return (clamped * 10).rounded() / 10
  }

  private static func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private static func priceLabel(cents: Int) -> String {
    String(format: "$%.0f/month", Double(max(0, cents)) / 100)
  }
}

struct ProductTournamentPlanEvaluationRecord: Codable, Equatable, Identifiable, Sendable {
  static let supportedSchemaVersion = 1

  var id: String
  var schemaVersion: Int
  var projectID: String?
  var tournamentID: String
  var roundID: String
  var contenderID: String
  var contenderPlanID: String
  var experimentID: String?
  var painID: String
  var personaID: String
  var personaName: String
  var currentWorkflowID: String?
  var alternativeID: String?
  var mode: ProductTournamentSimulationMode
  var status: ProductTournamentRunStatus
  var startedAt: Double
  var endedAt: Double
  var model: String
  var scores: ProductTournamentEvidenceScores
  var willingnessToPayScore: Int?
  var estimatedMonthlyPriceCents: Int?
  var commercialProofSummary: String?
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var verdict: ProductTournamentEvidenceVerdict
  var summary: String
  var rationale: [String]
  var planStrengths: [String]
  var planRisks: [String]
  var promptVersions: [String]
  var summaryArtifactPath: String?
  var failure: ProductTournamentRunFailure?

  init(
    id: String,
    schemaVersion: Int = Self.supportedSchemaVersion,
    projectID: String? = nil,
    tournamentID: String,
    roundID: String,
    contenderID: String,
    contenderPlanID: String,
    experimentID: String? = nil,
    painID: String,
    personaID: String,
    personaName: String,
    currentWorkflowID: String? = nil,
    alternativeID: String? = nil,
    mode: ProductTournamentSimulationMode = .modelFree,
    status: ProductTournamentRunStatus = .completed,
    startedAt: Double,
    endedAt: Double,
    model: String = "model-free-plan-evaluator",
    scores: ProductTournamentEvidenceScores,
    willingnessToPayScore: Int?,
    estimatedMonthlyPriceCents: Int?,
    commercialProofSummary: String? = nil,
    objections: [String] = [],
    missingCapabilities: [String] = [],
    currentAlternativeComparison: String,
    verdict: ProductTournamentEvidenceVerdict,
    summary: String,
    rationale: [String] = [],
    planStrengths: [String] = [],
    planRisks: [String] = [],
    promptVersions: [String] = [],
    summaryArtifactPath: String? = nil,
    failure: ProductTournamentRunFailure? = nil
  ) {
    self.id = ProductTournamentEvidenceRecord.cleanedIdentifier(
      id,
      fallback: "plan-evaluation"
    )
    self.schemaVersion = schemaVersion
    self.projectID = ProductTournamentEvidenceRecord.optionalBounded(projectID, limit: 80)
    self.tournamentID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      tournamentID,
      fallback: "tournament"
    )
    self.roundID = ProductTournamentEvidenceRecord.cleanedIdentifier(roundID, fallback: "round")
    self.contenderID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      contenderID,
      fallback: "contender"
    )
    self.contenderPlanID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      contenderPlanID,
      fallback: "contender-plan"
    )
    self.experimentID = ProductTournamentEvidenceRecord.optionalBounded(experimentID, limit: 96)
    self.painID = ProductTournamentEvidenceRecord.cleanedIdentifier(painID, fallback: "pain")
    self.personaID = ProductTournamentEvidenceRecord.cleanedIdentifier(
      personaID,
      fallback: "persona"
    )
    self.personaName = StringUtils.boundedText(personaName, limit: 160)
    self.currentWorkflowID = ProductTournamentEvidenceRecord.optionalBounded(
      currentWorkflowID,
      limit: 96
    )
    self.alternativeID = ProductTournamentEvidenceRecord.optionalBounded(
      alternativeID,
      limit: 96
    )
    self.mode = mode
    self.status = status
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.model = StringUtils.boundedText(model, limit: 160)
    self.scores = scores
    self.willingnessToPayScore = Self.clampedScore(willingnessToPayScore)
    self.estimatedMonthlyPriceCents = estimatedMonthlyPriceCents.map { max(0, $0) }
    self.commercialProofSummary = ProductTournamentEvidenceRecord.optionalBounded(
      commercialProofSummary,
      limit: 500
    )
    self.objections = ProductTournamentEvidenceRecord.cleanedList(objections, limit: 500)
    self.missingCapabilities = ProductTournamentEvidenceRecord.cleanedList(
      missingCapabilities,
      limit: 160
    )
    self.currentAlternativeComparison = StringUtils.boundedText(
      currentAlternativeComparison,
      limit: 1_000
    )
    self.verdict = verdict
    self.summary = StringUtils.boundedText(summary, limit: 1_500)
    self.rationale = ProductTournamentEvidenceRecord.cleanedList(rationale, limit: 360)
    self.planStrengths = ProductTournamentEvidenceRecord.cleanedList(planStrengths, limit: 240)
    self.planRisks = ProductTournamentEvidenceRecord.cleanedList(planRisks, limit: 240)
    self.promptVersions = ProductTournamentEvidenceRecord.cleanedList(promptVersions, limit: 160)
    self.summaryArtifactPath = ProductTournamentEvidenceRecord.optionalBounded(
      summaryArtifactPath,
      limit: 500
    )
    self.failure = failure
  }

  var summaryRecord: ProductTournamentPlanEvaluationSummary {
    ProductTournamentPlanEvaluationSummary(record: self)
  }

  private static func clampedScore(_ value: Int?) -> Int? {
    value.map { min(5, max(1, $0)) }
  }
}

struct ProductTournamentPlanEvaluationSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var evaluationID: String
  var tournamentID: String
  var roundID: String
  var contenderID: String
  var contenderPlanID: String
  var experimentID: String?
  var painID: String
  var personaID: String
  var personaName: String
  var mode: ProductTournamentSimulationMode
  var status: ProductTournamentRunStatus
  var startedAt: Double
  var endedAt: Double
  var model: String
  var verdict: ProductTournamentEvidenceVerdict
  var scores: ProductTournamentEvidenceScores
  var willingnessToPayScore: Int?
  var estimatedMonthlyPriceCents: Int?
  var commercialProofSummary: String?
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var rationale: [String]
  var summary: String
  var failureKind: String?

  init(record: ProductTournamentPlanEvaluationRecord) {
    id = record.id
    evaluationID = record.id
    tournamentID = record.tournamentID
    roundID = record.roundID
    contenderID = record.contenderID
    contenderPlanID = record.contenderPlanID
    experimentID = record.experimentID
    painID = record.painID
    personaID = record.personaID
    personaName = record.personaName
    mode = record.mode
    status = record.status
    startedAt = record.startedAt
    endedAt = record.endedAt
    model = record.model
    verdict = record.verdict
    scores = record.scores
    willingnessToPayScore = record.willingnessToPayScore
    estimatedMonthlyPriceCents = record.estimatedMonthlyPriceCents
    commercialProofSummary = record.commercialProofSummary
    objections = record.objections
    missingCapabilities = record.missingCapabilities
    currentAlternativeComparison = record.currentAlternativeComparison
    rationale = record.rationale
    summary = record.summary
    failureKind = record.failure?.status.rawValue
  }

  var isCompleted: Bool {
    status == .completed
  }
}

struct ProductTournamentEvidenceIndex: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1
  static let empty = ProductTournamentEvidenceIndex()

  var schemaVersion: Int
  var updatedAt: Double
  var summaries: [ProductTournamentEvidenceSummary]
  var planEvaluationSummaries: [ProductTournamentPlanEvaluationSummary]
  var marketPressureSummaries: [MarketPressureEvaluationSummary]
  var distributionPressureSummaries: [DistributionPressureSummary]
  var aggregate: ProductTournamentEvidenceAggregateSummary
  var malformedRecordCount: Int

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    updatedAt: Double = 0,
    summaries: [ProductTournamentEvidenceSummary] = [],
    planEvaluationSummaries: [ProductTournamentPlanEvaluationSummary] = [],
    marketPressureSummaries: [MarketPressureEvaluationSummary] = [],
    distributionPressureSummaries: [DistributionPressureSummary] = [],
    aggregate: ProductTournamentEvidenceAggregateSummary = .empty,
    malformedRecordCount: Int = 0
  ) {
    self.schemaVersion = schemaVersion
    self.updatedAt = updatedAt
    self.summaries = summaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    self.planEvaluationSummaries = planEvaluationSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.evaluationID < rhs.evaluationID }
      return lhs.endedAt > rhs.endedAt
    }
    self.marketPressureSummaries = marketPressureSummaries.sorted { lhs, rhs in
      if lhs.createdAt == rhs.createdAt { return lhs.evaluationID < rhs.evaluationID }
      return lhs.createdAt > rhs.createdAt
    }
    self.distributionPressureSummaries = distributionPressureSummaries.sorted { lhs, rhs in
      if lhs.createdAt == rhs.createdAt { return lhs.pressureID < rhs.pressureID }
      return lhs.createdAt > rhs.createdAt
    }
    self.aggregate = aggregate
    self.malformedRecordCount = malformedRecordCount
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case updatedAt
    case summaries
    case planEvaluationSummaries
    case marketPressureSummaries
    case distributionPressureSummaries
    case aggregate
    case malformedRecordCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        ?? Self.supportedSchemaVersion,
      updatedAt: try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0,
      summaries: try container.decodeIfPresent(
        [ProductTournamentEvidenceSummary].self,
        forKey: .summaries
      ) ?? [],
      planEvaluationSummaries: try container.decodeIfPresent(
        [ProductTournamentPlanEvaluationSummary].self,
        forKey: .planEvaluationSummaries
      ) ?? [],
      marketPressureSummaries: try container.decodeIfPresent(
        [MarketPressureEvaluationSummary].self,
        forKey: .marketPressureSummaries
      ) ?? [],
      distributionPressureSummaries: try container.decodeIfPresent(
        [DistributionPressureSummary].self,
        forKey: .distributionPressureSummaries
      ) ?? [],
      aggregate: try container.decodeIfPresent(
        ProductTournamentEvidenceAggregateSummary.self,
        forKey: .aggregate
      ) ?? .empty,
      malformedRecordCount: try container.decodeIfPresent(
        Int.self,
        forKey: .malformedRecordCount
      ) ?? 0
    )
  }

  static func build(
    records: [ProductTournamentEvidenceRecord],
    planEvaluationRecords: [ProductTournamentPlanEvaluationRecord] = [],
    marketPressureRecords: [MarketPressureEvaluationRecord] = [],
    distributionPressureRecords: [DistributionPressureRecord] = [],
    malformedRecordCount: Int = 0,
    now: Date = Date()
  ) -> ProductTournamentEvidenceIndex {
    let summaries = records.map(\.summaryRecord)
    let planEvaluationSummaries = planEvaluationRecords.map(\.summaryRecord)
    let marketPressureSummaries = marketPressureRecords.map(\.summaryRecord)
    let distributionPressureSummaries = distributionPressureRecords.map(\.summaryRecord)
    return ProductTournamentEvidenceIndex(
      updatedAt: now.timeIntervalSince1970,
      summaries: summaries,
      planEvaluationSummaries: planEvaluationSummaries,
      marketPressureSummaries: marketPressureSummaries,
      distributionPressureSummaries: distributionPressureSummaries,
      aggregate: ProductTournamentEvidenceAggregateSummary(
        summaries: summaries,
        planEvaluationSummaries: planEvaluationSummaries,
        marketPressureSummaries: marketPressureSummaries,
        distributionPressureSummaries: distributionPressureSummaries
      ),
      malformedRecordCount: malformedRecordCount
    )
  }

  func planEvaluations(
    for tournament: ProductTournament,
    round: ProductTournamentRound? = nil
  ) -> [ProductTournamentPlanEvaluationSummary] {
    planEvaluationSummaries.filter { summary in
      summary.tournamentID == tournament.id && (round == nil || summary.roundID == round?.id)
    }
  }

  func evidenceSummaries(
    for tournament: ProductTournament,
    round: ProductTournamentRound? = nil
  ) -> [ProductTournamentEvidenceSummary] {
    summaries.filter { summary in
      summary.tournamentID == tournament.id && (round == nil || summary.roundID == round?.id)
    }
  }

  func targetCommit(for experiment: ProductTournamentExperiment) -> String? {
    let commit = experiment.currentSha ?? experiment.baseSha ?? ""
    let trimmed = commit.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func summaries(
    for experiment: ProductTournamentExperiment,
    currentCommitOnly: Bool = true
  ) -> [ProductTournamentEvidenceSummary] {
    let experimentSummaries = summaries.filter { $0.experimentID == experiment.id }
    guard currentCommitOnly, let targetCommit = targetCommit(for: experiment) else {
      return experimentSummaries
    }
    return experimentSummaries.filter {
      ProductTournamentExperimentGit.commitMatches(expected: targetCommit, actual: $0.commitSha)
    }
  }

  func staleSummaryCount(for experiment: ProductTournamentExperiment) -> Int {
    let all = summaries(for: experiment, currentCommitOnly: false)
    return max(0, all.count - summaries(for: experiment).count)
  }

  func currentTournamentReadiness(for experiment: ProductTournamentExperiment)
    -> ProductTournamentReadiness?
  {
    let currentSummaries = summaries(for: experiment)
    guard !currentSummaries.isEmpty else { return nil }
    return ProductTournamentReadiness(summaries: currentSummaries)
  }
}

struct ProductTournamentEvidenceAggregateSummary: Codable, Equatable, Sendable {
  static let empty = ProductTournamentEvidenceAggregateSummary(
    latestRunByExperiment: [:],
    tournamentReadinessByExperiment: [],
    latestPlanEvaluationByContender: [:],
    planReadinessByContender: [],
    latestMarketPressureByContender: [:],
    marketPressureByContender: [:],
    marketPressureObjections: [],
    latestDistributionPressureByContender: [:],
    distributionChannelProofByContender: [],
    distributionPressureObjections: [],
    repeatedObjections: [],
    lowScoreClusters: [],
    missingCapabilityFrequency: [],
    verdictCounts: [:],
    failuresByKind: [:],
    personaRationaleSignals: [],
    currentAlternativeComparisons: []
  )

  var latestRunByExperiment: [String: String]
  var tournamentReadinessByExperiment: [ProductTournamentReadiness]
  var latestPlanEvaluationByContender: [String: String]
  var planReadinessByContender: [ProductTournamentPlanReadiness]
  var latestMarketPressureByContender: [String: String]
  var marketPressureByContender: [String: [MarketPressureEvaluationSummary]]
  var marketPressureObjections: [ProductTournamentEvidenceRepeatedObjection]
  var latestDistributionPressureByContender: [String: String]
  var distributionChannelProofByContender: [DistributionChannelProof]
  var distributionPressureObjections: [ProductTournamentEvidenceRepeatedObjection]
  var repeatedObjections: [ProductTournamentEvidenceRepeatedObjection]
  var lowScoreClusters: [ProductTournamentEvidenceScoreCluster]
  var missingCapabilityFrequency: [ProductTournamentEvidenceMissingCapabilityCount]
  var verdictCounts: [String: Int]
  var failuresByKind: [String: Int]
  var personaRationaleSignals: [ProductTournamentPersonaRationaleSignal]
  var currentAlternativeComparisons: [ProductTournamentEvidenceAlternativeComparisonSummary]
  var decisionIntentOutcomes: [ProductTournamentEvidenceDecisionIntentOutcomeCount]

  enum CodingKeys: String, CodingKey {
    case latestRunByExperiment
    case tournamentReadinessByExperiment
    case latestPlanEvaluationByContender
    case planReadinessByContender
    case latestMarketPressureByContender
    case marketPressureByContender
    case marketPressureObjections
    case latestDistributionPressureByContender
    case distributionChannelProofByContender
    case distributionPressureObjections
    case repeatedObjections
    case lowScoreClusters
    case missingCapabilityFrequency
    case verdictCounts
    case failuresByKind
    case personaRationaleSignals
    case currentAlternativeComparisons
    case decisionIntentOutcomes
  }

  init(
    latestRunByExperiment: [String: String],
    tournamentReadinessByExperiment: [ProductTournamentReadiness] = [],
    latestPlanEvaluationByContender: [String: String] = [:],
    planReadinessByContender: [ProductTournamentPlanReadiness] = [],
    latestMarketPressureByContender: [String: String] = [:],
    marketPressureByContender: [String: [MarketPressureEvaluationSummary]] = [:],
    marketPressureObjections: [ProductTournamentEvidenceRepeatedObjection] = [],
    latestDistributionPressureByContender: [String: String] = [:],
    distributionChannelProofByContender: [DistributionChannelProof] = [],
    distributionPressureObjections: [ProductTournamentEvidenceRepeatedObjection] = [],
    repeatedObjections: [ProductTournamentEvidenceRepeatedObjection],
    lowScoreClusters: [ProductTournamentEvidenceScoreCluster],
    missingCapabilityFrequency: [ProductTournamentEvidenceMissingCapabilityCount],
    verdictCounts: [String: Int],
    failuresByKind: [String: Int],
    personaRationaleSignals: [ProductTournamentPersonaRationaleSignal] = [],
    currentAlternativeComparisons: [ProductTournamentEvidenceAlternativeComparisonSummary],
    decisionIntentOutcomes: [ProductTournamentEvidenceDecisionIntentOutcomeCount] = []
  ) {
    self.latestRunByExperiment = latestRunByExperiment
    self.tournamentReadinessByExperiment = tournamentReadinessByExperiment
    self.latestPlanEvaluationByContender = latestPlanEvaluationByContender
    self.planReadinessByContender = planReadinessByContender
    self.latestMarketPressureByContender = latestMarketPressureByContender
    self.marketPressureByContender = marketPressureByContender
    self.marketPressureObjections = marketPressureObjections
    self.latestDistributionPressureByContender = latestDistributionPressureByContender
    self.distributionChannelProofByContender = distributionChannelProofByContender
    self.distributionPressureObjections = distributionPressureObjections
    self.repeatedObjections = repeatedObjections
    self.lowScoreClusters = lowScoreClusters
    self.missingCapabilityFrequency = missingCapabilityFrequency
    self.verdictCounts = verdictCounts
    self.failuresByKind = failuresByKind
    self.personaRationaleSignals = personaRationaleSignals
    self.currentAlternativeComparisons = currentAlternativeComparisons
    self.decisionIntentOutcomes = decisionIntentOutcomes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      latestRunByExperiment: try container.decodeIfPresent(
        [String: String].self,
        forKey: .latestRunByExperiment
      ) ?? [:],
      tournamentReadinessByExperiment: try container.decodeIfPresent(
        [ProductTournamentReadiness].self,
        forKey: .tournamentReadinessByExperiment
      ) ?? [],
      latestPlanEvaluationByContender: try container.decodeIfPresent(
        [String: String].self,
        forKey: .latestPlanEvaluationByContender
      ) ?? [:],
      planReadinessByContender: try container.decodeIfPresent(
        [ProductTournamentPlanReadiness].self,
        forKey: .planReadinessByContender
      ) ?? [],
      latestMarketPressureByContender: try container.decodeIfPresent(
        [String: String].self,
        forKey: .latestMarketPressureByContender
      ) ?? [:],
      marketPressureByContender: try container.decodeIfPresent(
        [String: [MarketPressureEvaluationSummary]].self,
        forKey: .marketPressureByContender
      ) ?? [:],
      marketPressureObjections: try container.decodeIfPresent(
        [ProductTournamentEvidenceRepeatedObjection].self,
        forKey: .marketPressureObjections
      ) ?? [],
      latestDistributionPressureByContender: try container.decodeIfPresent(
        [String: String].self,
        forKey: .latestDistributionPressureByContender
      ) ?? [:],
      distributionChannelProofByContender: try container.decodeIfPresent(
        [DistributionChannelProof].self,
        forKey: .distributionChannelProofByContender
      ) ?? [],
      distributionPressureObjections: try container.decodeIfPresent(
        [ProductTournamentEvidenceRepeatedObjection].self,
        forKey: .distributionPressureObjections
      ) ?? [],
      repeatedObjections: try container.decodeIfPresent(
        [ProductTournamentEvidenceRepeatedObjection].self,
        forKey: .repeatedObjections
      ) ?? [],
      lowScoreClusters: try container.decodeIfPresent(
        [ProductTournamentEvidenceScoreCluster].self,
        forKey: .lowScoreClusters
      ) ?? [],
      missingCapabilityFrequency: try container.decodeIfPresent(
        [ProductTournamentEvidenceMissingCapabilityCount].self,
        forKey: .missingCapabilityFrequency
      ) ?? [],
      verdictCounts: try container.decodeIfPresent(
        [String: Int].self,
        forKey: .verdictCounts
      ) ?? [:],
      failuresByKind: try container.decodeIfPresent(
        [String: Int].self,
        forKey: .failuresByKind
      ) ?? [:],
      personaRationaleSignals: try container.decodeIfPresent(
        [ProductTournamentPersonaRationaleSignal].self,
        forKey: .personaRationaleSignals
      ) ?? [],
      currentAlternativeComparisons: try container.decodeIfPresent(
        [ProductTournamentEvidenceAlternativeComparisonSummary].self,
        forKey: .currentAlternativeComparisons
      ) ?? [],
      decisionIntentOutcomes: try container.decodeIfPresent(
        [ProductTournamentEvidenceDecisionIntentOutcomeCount].self,
        forKey: .decisionIntentOutcomes
      ) ?? []
    )
  }

  init(
    summaries: [ProductTournamentEvidenceSummary],
    planEvaluationSummaries: [ProductTournamentPlanEvaluationSummary] = [],
    marketPressureSummaries: [MarketPressureEvaluationSummary] = [],
    distributionPressureSummaries: [DistributionPressureSummary] = []
  ) {
    var latest: [String: ProductTournamentEvidenceSummary] = [:]
    for summary in summaries {
      if let current = latest[summary.experimentID] {
        if summary.endedAt > current.endedAt
          || (summary.endedAt == current.endedAt && summary.runID < current.runID)
        {
          latest[summary.experimentID] = summary
        }
      } else {
        latest[summary.experimentID] = summary
      }
    }
    latestRunByExperiment = latest.mapValues(\.runID)
    tournamentReadinessByExperiment = Dictionary(grouping: summaries, by: \.experimentID)
      .map { _, group in ProductTournamentReadiness(summaries: group) }
      .sorted { lhs, rhs in
        if lhs.readinessScore == rhs.readinessScore {
          return lhs.experimentID < rhs.experimentID
        }
        return lhs.readinessScore > rhs.readinessScore
      }

    var latestPlanEvaluation: [String: ProductTournamentPlanEvaluationSummary] = [:]
    for summary in planEvaluationSummaries {
      if let current = latestPlanEvaluation[summary.contenderID] {
        if summary.endedAt > current.endedAt
          || (summary.endedAt == current.endedAt && summary.evaluationID < current.evaluationID)
        {
          latestPlanEvaluation[summary.contenderID] = summary
        }
      } else {
        latestPlanEvaluation[summary.contenderID] = summary
      }
    }
    latestPlanEvaluationByContender = latestPlanEvaluation.mapValues(\.evaluationID)
    planReadinessByContender = Dictionary(grouping: planEvaluationSummaries, by: \.contenderID)
      .map { _, group in ProductTournamentPlanReadiness(summaries: group) }
      .sorted { lhs, rhs in
        if lhs.readinessScore == rhs.readinessScore {
          return lhs.contenderID < rhs.contenderID
        }
        return lhs.readinessScore > rhs.readinessScore
      }

    var latestMarketPressure: [String: MarketPressureEvaluationSummary] = [:]
    for summary in marketPressureSummaries {
      if let current = latestMarketPressure[summary.contenderID] {
        if summary.createdAt > current.createdAt
          || (summary.createdAt == current.createdAt
            && summary.evaluationID < current.evaluationID)
        {
          latestMarketPressure[summary.contenderID] = summary
        }
      } else {
        latestMarketPressure[summary.contenderID] = summary
      }
    }
    latestMarketPressureByContender = latestMarketPressure.mapValues(\.evaluationID)
    marketPressureByContender = Dictionary(grouping: marketPressureSummaries, by: \.contenderID)
      .mapValues {
        $0.sorted { lhs, rhs in
          if lhs.createdAt == rhs.createdAt { return lhs.evaluationID < rhs.evaluationID }
          return lhs.createdAt > rhs.createdAt
        }
      }

    var latestDistributionPressure: [String: DistributionPressureSummary] = [:]
    for summary in distributionPressureSummaries {
      if let current = latestDistributionPressure[summary.contenderID] {
        if summary.createdAt > current.createdAt
          || (summary.createdAt == current.createdAt
            && summary.pressureID < current.pressureID)
        {
          latestDistributionPressure[summary.contenderID] = summary
        }
      } else {
        latestDistributionPressure[summary.contenderID] = summary
      }
    }
    latestDistributionPressureByContender = latestDistributionPressure.mapValues(\.pressureID)
    distributionChannelProofByContender = Dictionary(
      grouping: distributionPressureSummaries,
      by: \.contenderID
    )
    .map { contenderID, summaries in
      DistributionChannelProof(contenderID: contenderID, summaries: summaries)
    }
    .sorted { lhs, rhs in
      if lhs.bestScore == rhs.bestScore { return lhs.contenderID < rhs.contenderID }
      return lhs.bestScore > rhs.bestScore
    }

    let objectionCounts = Dictionary(
      grouping: (summaries.flatMap(\.objections) + planEvaluationSummaries.flatMap(\.objections)
        + marketPressureSummaries.map(\.strongestObjection)
        + distributionPressureSummaries.map(\.strongestObjection))
        .map(\.normalizedProductTournamentEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    repeatedObjections =
      objectionCounts
      .filter { !$0.key.isEmpty && $0.value > 1 }
      .map { ProductTournamentEvidenceRepeatedObjection(objection: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.objection < rhs.objection }
        return lhs.count > rhs.count
      }

    let pressureObjectionCounts = Dictionary(
      grouping: marketPressureSummaries.map(\.strongestObjection)
        .map(\.normalizedProductTournamentEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    marketPressureObjections =
      pressureObjectionCounts
      .filter { !$0.key.isEmpty }
      .map { ProductTournamentEvidenceRepeatedObjection(objection: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.objection < rhs.objection }
        return lhs.count > rhs.count
      }

    let distributionObjectionCounts = Dictionary(
      grouping: distributionPressureSummaries.map(\.strongestObjection)
        .map(\.normalizedProductTournamentEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    distributionPressureObjections =
      distributionObjectionCounts
      .filter { !$0.key.isEmpty }
      .map { ProductTournamentEvidenceRepeatedObjection(objection: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.objection < rhs.objection }
        return lhs.count > rhs.count
      }

    let missingCounts = Dictionary(
      grouping: (summaries.flatMap(\.missingCapabilities)
        + planEvaluationSummaries.flatMap(\.missingCapabilities)).map(
          \.normalizedProductTournamentEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    missingCapabilityFrequency =
      missingCounts
      .filter { !$0.key.isEmpty }
      .map {
        ProductTournamentEvidenceMissingCapabilityCount(capabilityID: $0.key, count: $0.value)
      }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.capabilityID < rhs.capabilityID }
        return lhs.count > rhs.count
      }

    verdictCounts = Dictionary(
      grouping: (summaries.map(\.verdict.rawValue) + planEvaluationSummaries.map(\.verdict.rawValue)),
      by: { $0 }
    )
    .mapValues(\.count)

    failuresByKind = Dictionary(
      grouping:
        summaries.compactMap { summary -> String? in
          guard !summary.isCompleted else { return nil }
          return summary.failureKind ?? summary.status.rawValue
        }
        + planEvaluationSummaries.compactMap { summary -> String? in
          guard !summary.isCompleted else { return nil }
          return summary.failureKind ?? summary.status.rawValue
        },
      by: { $0 }
    ).mapValues(\.count)

    let rationaleGroups = Dictionary(
      grouping: summaries.flatMap { summary in
        summary.personaActionRationales.map { rationale in
          ProductTournamentPersonaRationaleSignalSource(summary: summary, rationale: rationale)
        }
      },
      by: { Self.personaRationaleSignalText($0.rationale) }
    )
    personaRationaleSignals =
      rationaleGroups
      .filter { !$0.key.isEmpty && $0.value.count > 1 }
      .map { rationale, sources in
        ProductTournamentPersonaRationaleSignal(
          rationale: rationale,
          count: sources.count,
          runIDs: sources.map(\.summary.runID),
          experimentIDs: sources.map(\.summary.experimentID)
        )
      }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.rationale < rhs.rationale }
        return lhs.count > rhs.count
      }

    let scoreGroups = Dictionary(grouping: summaries.filter { $0.scores.hasScores }) {
      "\($0.experimentID)|\($0.personaID)"
    }
    lowScoreClusters = scoreGroups.map { _, group in
      ProductTournamentEvidenceScoreCluster(summaries: group)
    }
    .filter { $0.minimumScore > 0 && $0.minimumScore <= 2.5 }
    .sorted { lhs, rhs in
      if lhs.minimumScore == rhs.minimumScore {
        return "\(lhs.experimentID)|\(lhs.personaID)" < "\(rhs.experimentID)|\(rhs.personaID)"
      }
      return lhs.minimumScore < rhs.minimumScore
    }

    currentAlternativeComparisons = Array(
      (summaries.map {
        ProductTournamentEvidenceAlternativeComparisonSummary(
          runID: $0.runID,
          experimentID: $0.experimentID,
          comparison: $0.currentAlternativeComparison,
          verdict: $0.verdict
        )
      }
        + planEvaluationSummaries.map {
          ProductTournamentEvidenceAlternativeComparisonSummary(
            runID: $0.evaluationID,
            experimentID: $0.experimentID ?? $0.contenderID,
            comparison: $0.currentAlternativeComparison,
            verdict: $0.verdict
          )
        })
        .filter { !$0.comparison.isEmpty }
        .prefix(12)
    )

    let outcomeGroups = Dictionary(
      grouping: summaries.compactMap(ProductTournamentEvidenceDecisionIntentOutcomeSource.init),
      by: { "\($0.intent.targetDecision.rawValue)|\($0.evaluation.outcome.rawValue)" }
    )
    decisionIntentOutcomes =
      outcomeGroups
      .map { _, sources in
        let first = sources[0]
        return ProductTournamentEvidenceDecisionIntentOutcomeCount(
          targetDecision: first.intent.targetDecision,
          outcome: first.evaluation.outcome,
          count: sources.count,
          runIDs: sources.map(\.summary.runID),
          experimentIDs: sources.map(\.summary.experimentID)
        )
      }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count {
          if lhs.targetDecision == rhs.targetDecision {
            return lhs.outcome.rawValue < rhs.outcome.rawValue
          }
          return lhs.targetDecision.rawValue < rhs.targetDecision.rawValue
        }
        return lhs.count > rhs.count
      }
  }

  private static func personaRationaleSignalText(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let separator = trimmed.range(of: ": ") {
      return String(trimmed[separator.upperBound...]).normalizedProductTournamentEvidenceText
    }
    return trimmed.normalizedProductTournamentEvidenceText
  }
}

struct ProductTournamentEvidenceRepeatedObjection: Codable, Equatable, Sendable {
  var objection: String
  var count: Int
}

struct ProductTournamentEvidenceMissingCapabilityCount: Codable, Equatable, Sendable {
  var capabilityID: String
  var count: Int
}

struct ProductTournamentPersonaRationaleSignal: Codable, Equatable, Sendable {
  var rationale: String
  var count: Int
  var runIDs: [String]
  var experimentIDs: [String]

  var auditSummary: String {
    let experiments =
      experimentIDs.isEmpty
      ? "no experiments"
      : "experiments \(experimentIDs.prefix(3).joined(separator: ", "))"
    let runs =
      runIDs.isEmpty
      ? "no runs"
      : "runs \(runIDs.prefix(4).joined(separator: ", "))"
    return "\(rationale); count \(count); \(experiments); \(runs)"
  }

  init(
    rationale: String,
    count: Int,
    runIDs: [String],
    experimentIDs: [String]
  ) {
    self.rationale = StringUtils.boundedText(rationale, limit: 260)
    self.count = max(0, count)
    self.runIDs = ProductTournamentEvidenceRecord.cleanedList(runIDs, limit: 96)
    self.experimentIDs = ProductTournamentEvidenceRecord.cleanedList(experimentIDs, limit: 96)
  }
}

private struct ProductTournamentPersonaRationaleSignalSource {
  var summary: ProductTournamentEvidenceSummary
  var rationale: String
}

struct ProductTournamentEvidenceDecisionIntentOutcomeCount: Codable, Equatable, Sendable {
  var targetDecision: ProductTournamentExperimentDecision
  var outcome: ProductTournamentEvidenceDecisionIntentOutcome
  var count: Int
  var runIDs: [String]
  var experimentIDs: [String]

  var auditSummary: String {
    let runs =
      runIDs.isEmpty
      ? "no runs"
      : "runs \(runIDs.prefix(4).joined(separator: ", "))"
    let experiments =
      experimentIDs.isEmpty
      ? "no experiments"
      : "experiments \(experimentIDs.prefix(3).joined(separator: ", "))"
    return
      "target_decision \(targetDecision.rawValue); outcome \(outcome.rawValue); count \(count); \(runs); \(experiments)"
  }

  init(
    targetDecision: ProductTournamentExperimentDecision,
    outcome: ProductTournamentEvidenceDecisionIntentOutcome,
    count: Int,
    runIDs: [String],
    experimentIDs: [String]
  ) {
    self.targetDecision = targetDecision
    self.outcome = outcome
    self.count = max(0, count)
    self.runIDs = ProductTournamentEvidenceRecord.cleanedList(runIDs, limit: 96)
    self.experimentIDs = ProductTournamentEvidenceRecord.cleanedList(experimentIDs, limit: 96)
  }
}

private struct ProductTournamentEvidenceDecisionIntentOutcomeSource {
  var summary: ProductTournamentEvidenceSummary
  var intent: ProductTournamentSimulationDecisionIntent
  var evaluation: ProductTournamentEvidenceDecisionIntentEvaluation

  init?(_ summary: ProductTournamentEvidenceSummary) {
    guard let intent = summary.decisionIntent,
      let evaluation = summary.decisionIntentEvaluation
    else { return nil }
    self.summary = summary
    self.intent = intent
    self.evaluation = evaluation
  }
}

struct ProductTournamentEvidenceAlternativeComparisonSummary: Codable, Equatable, Sendable {
  var runID: String
  var experimentID: String
  var comparison: String
  var verdict: ProductTournamentEvidenceVerdict
}

struct ProductTournamentEvidenceScoreCluster: Codable, Equatable, Sendable {
  var experimentID: String
  var personaID: String
  var runCount: Int
  var painRecognition: Double
  var workflowImprovement: Double
  var alternativeAdvantage: Double
  var switchingReadiness: Double
  var continuedUsePull: Double
  var minimumScore: Double

  init(summaries: [ProductTournamentEvidenceSummary]) {
    let first = summaries.first
    experimentID = first?.experimentID ?? ""
    personaID = first?.personaID ?? ""
    runCount = summaries.count
    painRecognition = Self.average(summaries.compactMap(\.scores.painRecognition))
    workflowImprovement = Self.average(summaries.compactMap(\.scores.workflowImprovement))
    alternativeAdvantage = Self.average(summaries.compactMap(\.scores.alternativeAdvantage))
    switchingReadiness = Self.average(summaries.compactMap(\.scores.switchingReadiness))
    continuedUsePull = Self.average(summaries.compactMap(\.scores.continuedUsePull))
    minimumScore =
      [
        painRecognition,
        workflowImprovement,
        alternativeAdvantage,
        switchingReadiness,
        continuedUsePull,
      ]
      .filter { $0 > 0 }
      .min() ?? 0
  }

  private static func average(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    let raw = Double(values.reduce(0, +)) / Double(values.count)
    return (raw * 100).rounded() / 100
  }
}

struct ProductTournamentEvidenceStore {
  var productTournamentURL: URL

  init(workspace: CompassWorkspace) {
    self.productTournamentURL = workspace.productTournamentURL
  }

  var runsURL: URL { productTournamentURL.appending(path: "runs", directoryHint: .isDirectory) }
  var planEvaluationsURL: URL {
    productTournamentURL.appending(path: "plan-evaluations", directoryHint: .isDirectory)
  }
  var marketPressureURL: URL {
    productTournamentURL.appending(path: "market-pressure", directoryHint: .isDirectory)
  }
  var distributionPressureURL: URL {
    productTournamentURL.appending(path: "distribution-pressure", directoryHint: .isDirectory)
  }
  var indexURL: URL { productTournamentURL.appending(path: "evidence-index.json") }

  func readIndex() throws -> ProductTournamentEvidenceIndex {
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: indexURL)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(ProductTournamentEvidenceIndex.self, from: data)
  }

  func readRecord(id: String) throws -> ProductTournamentEvidenceRecord {
    let data = try Data(contentsOf: recordURL(id: id))
    return try JSONDecoder().decode(ProductTournamentEvidenceRecord.self, from: data)
  }

  func readPlanEvaluationRecord(id: String) throws -> ProductTournamentPlanEvaluationRecord {
    let data = try Data(contentsOf: planEvaluationRecordURL(id: id))
    return try JSONDecoder().decode(ProductTournamentPlanEvaluationRecord.self, from: data)
  }

  func readMarketPressureRecord(id: String) throws -> MarketPressureEvaluationRecord {
    let data = try Data(contentsOf: marketPressureRecordURL(id: id))
    return try JSONDecoder().decode(MarketPressureEvaluationRecord.self, from: data)
  }

  func readDistributionPressureRecord(id: String) throws -> DistributionPressureRecord {
    let data = try Data(contentsOf: distributionPressureRecordURL(id: id))
    return try JSONDecoder().decode(DistributionPressureRecord.self, from: data)
  }

  @discardableResult
  func writeRecord(
    _ record: ProductTournamentEvidenceRecord,
    traceJSON: String? = nil,
    feedbackJSON: String? = nil,
    transcriptJSONL: String? = nil,
    summaryMarkdown: String? = nil,
    now: Date = Date()
  ) throws -> ProductTournamentEvidenceRecord {
    let safeID = Self.safeRunID(record.id)
    let runURL = runsURL.appending(path: safeID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)

    var stored = record
    if let traceJSON, !traceJSON.isEmpty {
      stored.traceArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "product-tournament/runs/\(safeID)/trace.json",
        fileName: "trace.json",
        contents: traceJSON
      )
    }
    if let feedbackJSON, !feedbackJSON.isEmpty {
      stored.feedbackArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "product-tournament/runs/\(safeID)/feedback.json",
        fileName: "feedback.json",
        contents: feedbackJSON
      )
    }
    if let transcriptJSONL, !transcriptJSONL.isEmpty {
      stored.transcriptArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "product-tournament/runs/\(safeID)/transcript.jsonl",
        fileName: "transcript.jsonl",
        contents: transcriptJSONL
      )
    }
    let summary =
      summaryMarkdown ?? ProductTournamentEvidenceMarkdownExporter.markdown(record: stored)
    if !summary.isEmpty {
      stored.summaryArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "product-tournament/runs/\(safeID)/summary.md",
        fileName: "summary.md",
        contents: summary
      )
    }

    let data = try Self.encoder().encode(stored)
    try data.write(to: recordURL(id: stored.id), options: .atomic)
    _ = try rebuildIndex(now: now)
    return stored
  }

  @discardableResult
  func writePlanEvaluationRecord(
    _ record: ProductTournamentPlanEvaluationRecord,
    summaryMarkdown: String? = nil,
    now: Date = Date()
  ) throws -> ProductTournamentPlanEvaluationRecord {
    let safeID = Self.safeRunID(record.id)
    let evaluationURL = planEvaluationsURL.appending(path: safeID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: evaluationURL, withIntermediateDirectories: true)

    var stored = record
    let summary =
      summaryMarkdown ?? ProductTournamentEvidenceMarkdownExporter.markdown(planEvaluation: stored)
    if !summary.isEmpty {
      stored.summaryArtifactPath = try writeArtifact(
        runURL: evaluationURL,
        relativePath: "product-tournament/plan-evaluations/\(safeID)/summary.md",
        fileName: "summary.md",
        contents: summary
      )
    }

    let data = try Self.encoder().encode(stored)
    try data.write(to: planEvaluationRecordURL(id: stored.id), options: .atomic)
    _ = try rebuildIndex(now: now)
    return stored
  }

  @discardableResult
  func writeMarketPressureRecord(
    _ record: MarketPressureEvaluationRecord,
    summaryMarkdown: String? = nil,
    now: Date = Date()
  ) throws -> MarketPressureEvaluationRecord {
    let safeID = Self.safeRunID(record.id)
    let pressureURL = marketPressureURL.appending(path: safeID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: pressureURL, withIntermediateDirectories: true)

    let data = try Self.encoder().encode(record)
    try data.write(to: marketPressureRecordURL(id: record.id), options: .atomic)
    if let summaryMarkdown, !summaryMarkdown.isEmpty {
      _ = try writeArtifact(
        runURL: pressureURL,
        relativePath: "product-tournament/market-pressure/\(safeID)/summary.md",
        fileName: "summary.md",
        contents: summaryMarkdown
      )
    }
    _ = try rebuildIndex(now: now)
    return record
  }

  @discardableResult
  func writeDistributionPressureRecord(
    _ record: DistributionPressureRecord,
    summaryMarkdown: String? = nil,
    now: Date = Date()
  ) throws -> DistributionPressureRecord {
    let safeID = Self.safeRunID(record.id)
    let pressureURL = distributionPressureURL.appending(path: safeID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: pressureURL, withIntermediateDirectories: true)

    let data = try Self.encoder().encode(record)
    try data.write(to: distributionPressureRecordURL(id: record.id), options: .atomic)
    let summary = summaryMarkdown ?? ProductTournamentEvidenceMarkdownExporter.markdown(
      distributionPressure: record
    )
    if !summary.isEmpty {
      _ = try writeArtifact(
        runURL: pressureURL,
        relativePath: "product-tournament/distribution-pressure/\(safeID)/summary.md",
        fileName: "summary.md",
        contents: summary
      )
    }
    _ = try rebuildIndex(now: now)
    return record
  }

  @discardableResult
  func rebuildIndex(now: Date = Date()) throws -> ProductTournamentEvidenceIndex {
    try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: planEvaluationsURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: marketPressureURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: distributionPressureURL,
      withIntermediateDirectories: true
    )
    let urls = try FileManager.default.contentsOfDirectory(
      at: runsURL,
      includingPropertiesForKeys: nil
    )
    var records: [ProductTournamentEvidenceRecord] = []
    var planEvaluations: [ProductTournamentPlanEvaluationRecord] = []
    var marketPressures: [MarketPressureEvaluationRecord] = []
    var distributionPressures: [DistributionPressureRecord] = []
    var malformed = 0
    for url in urls {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        records.append(
          try JSONDecoder().decode(
            ProductTournamentEvidenceRecord.self,
            from: Data(contentsOf: url.appending(path: "record.json"))
          ))
      } catch {
        malformed += 1
      }
    }
    let planEvaluationURLs = try FileManager.default.contentsOfDirectory(
      at: planEvaluationsURL,
      includingPropertiesForKeys: nil
    )
    for url in planEvaluationURLs {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        planEvaluations.append(
          try JSONDecoder().decode(
            ProductTournamentPlanEvaluationRecord.self,
            from: Data(contentsOf: url.appending(path: "record.json"))
          ))
      } catch {
        malformed += 1
      }
    }
    let marketPressureURLs = try FileManager.default.contentsOfDirectory(
      at: marketPressureURL,
      includingPropertiesForKeys: nil
    )
    for url in marketPressureURLs {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        marketPressures.append(
          try JSONDecoder().decode(
            MarketPressureEvaluationRecord.self,
            from: Data(contentsOf: url.appending(path: "record.json"))
          ))
      } catch {
        malformed += 1
      }
    }
    let distributionPressureURLs = try FileManager.default.contentsOfDirectory(
      at: distributionPressureURL,
      includingPropertiesForKeys: nil
    )
    for url in distributionPressureURLs {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        distributionPressures.append(
          try JSONDecoder().decode(
            DistributionPressureRecord.self,
            from: Data(contentsOf: url.appending(path: "record.json"))
          ))
      } catch {
        malformed += 1
      }
    }
    let index = ProductTournamentEvidenceIndex.build(
      records: records,
      planEvaluationRecords: planEvaluations,
      marketPressureRecords: marketPressures,
      distributionPressureRecords: distributionPressures,
      malformedRecordCount: malformed,
      now: now
    )
    let data = try Self.encoder().encode(index)
    try FileManager.default.createDirectory(
      at: productTournamentURL, withIntermediateDirectories: true)
    try data.write(to: indexURL, options: .atomic)
    return index
  }

  func recordURL(id: String) -> URL {
    runsURL
      .appending(path: Self.safeRunID(id), directoryHint: .isDirectory)
      .appending(path: "record.json")
  }

  func planEvaluationRecordURL(id: String) -> URL {
    planEvaluationsURL
      .appending(path: Self.safeRunID(id), directoryHint: .isDirectory)
      .appending(path: "record.json")
  }

  func marketPressureRecordURL(id: String) -> URL {
    marketPressureURL
      .appending(path: Self.safeRunID(id), directoryHint: .isDirectory)
      .appending(path: "record.json")
  }

  func distributionPressureRecordURL(id: String) -> URL {
    distributionPressureURL
      .appending(path: Self.safeRunID(id), directoryHint: .isDirectory)
      .appending(path: "record.json")
  }

  private func writeArtifact(
    runURL: URL,
    relativePath: String,
    fileName: String,
    contents: String
  ) throws -> String {
    let url = runURL.appending(path: fileName)
    try Data(contents.utf8).write(to: url, options: .atomic)
    return relativePath
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  static func safeRunID(_ id: String) -> String {
    ProductTournamentEvidenceRecord.cleanedIdentifier(id, fallback: "product-tournament-run")
  }
}

enum ProductTournamentEvidenceMarkdownExporter {
  static func markdown(planEvaluation record: ProductTournamentPlanEvaluationRecord) -> String {
    var lines = [
      "# Product Tournament Plan Evaluation \(record.id)",
      "",
      "- Tournament: \(record.tournamentID)",
      "- Round: \(record.roundID)",
      "- Contender: \(record.contenderID)",
      "- Contender plan: \(record.contenderPlanID)",
      record.experimentID.map { "- Implementation Track: \($0)" },
      "- Pain: \(record.painID)",
      "- Persona: \(record.personaName) (`\(record.personaID)`)",
      "- Mode: \(record.mode.rawValue)",
      "- Model: \(record.model)",
      record.promptVersions.isEmpty
        ? nil : "- Prompt Versions: \(record.promptVersions.joined(separator: ", "))",
      "- Status: \(record.status.rawValue)",
      "- Verdict: \(record.verdict.rawValue)",
      record.willingnessToPayScore.map { "- Willingness To Pay: \($0)/5" },
      record.estimatedMonthlyPriceCents.map {
        "- Estimated Monthly Price: \(Self.priceLabel(cents: $0))"
      },
      record.commercialProofSummary.map { "- Commercial Proof: \($0)" },
      "",
      "## Summary",
      "",
      record.summary,
      "",
      "## Current Alternative",
      "",
      record.currentAlternativeComparison.isEmpty
        ? "No current-alternative comparison recorded."
        : record.currentAlternativeComparison,
    ].compactMap { $0 }
    if !record.planStrengths.isEmpty {
      lines += ["", "## Plan Strengths", ""]
      lines += record.planStrengths.map { "- \($0)" }
    }
    if !record.planRisks.isEmpty {
      lines += ["", "## Plan Risks", ""]
      lines += record.planRisks.map { "- \($0)" }
    }
    if !record.objections.isEmpty {
      lines += ["", "## Objections", ""]
      lines += record.objections.map { "- \($0)" }
    }
    if !record.missingCapabilities.isEmpty {
      lines += ["", "## Missing Capabilities", ""]
      lines += record.missingCapabilities.map { "- \($0)" }
    }
    if !record.rationale.isEmpty {
      lines += ["", "## Simulated-User Rationale", ""]
      lines += record.rationale.map { "- \($0)" }
    }
    if let failure = record.failure {
      lines += ["", "## Failure", "", "\(failure.status.rawValue): \(failure.message)"]
    }
    return lines.joined(separator: "\n")
  }

  static func markdown(record: ProductTournamentEvidenceRecord) -> String {
    var lines = [
      "# Product Tournament Evidence \(record.id)",
      "",
      "- Experiment: \(record.experimentID)",
      "- Contender plan: \(record.contenderPlanID)",
      "- Pain: \(record.painID)",
      record.tournamentID.map { "- Tournament: \($0)" },
      record.roundID.map { "- Tournament Round: \($0)" },
      record.contenderID.map { "- Contender: \($0)" },
      "- Branch: \(record.branchName)",
      "- Commit: \(record.commitSha)",
      "- Scenario: \(record.scenarioID)",
      "- Persona: \(record.personaID)",
      "- Mode: \(record.mode.rawValue)",
      "- Status: \(record.status.rawValue)",
      "- Verdict: \(record.verdict.rawValue)",
      "- Completed Use Proof: \(record.completedUseProof ? "yes" : "no")",
      record.decisionIntent.map { "- Decision Intent: \(decisionIntentLine($0))" },
      record.decisionIntentEvaluation.map {
        "- Decision Intent Outcome: \(decisionIntentEvaluationLine($0))"
      },
      record.willingnessToPayScore.map { "- Willingness To Pay: \($0)/5" },
      record.sponsorshipIntent.isEmpty ? nil : "- Sponsorship Intent: \(record.sponsorshipIntent)",
      "",
      "## Summary",
      "",
      record.summary,
      "",
      "## Current Alternative",
      "",
      record.currentAlternativeComparison.isEmpty
        ? "No current-alternative comparison recorded."
        : record.currentAlternativeComparison,
    ].compactMap { $0 }
    if !record.objections.isEmpty {
      lines += ["", "## Objections", ""]
      lines += record.objections.map { "- \($0)" }
    }
    if !record.missingCapabilities.isEmpty {
      lines += ["", "## Missing Capabilities", ""]
      lines += record.missingCapabilities.map { "- \($0)" }
    }
    if !record.personaActionRationales.isEmpty {
      lines += ["", "## AI-User Action Rationales", ""]
      lines += record.personaActionRationales.map { "- \($0)" }
    }
    if let failure = record.failure {
      lines += ["", "## Failure", "", "\(failure.status.rawValue): \(failure.message)"]
    }
    return lines.joined(separator: "\n")
  }

  static func markdown(distributionPressure record: DistributionPressureRecord) -> String {
    var lines = [
      "# Distribution Pressure \(record.id)",
      "",
      "- Experiment: \(record.experimentID)",
      "- Market: \(record.marketID)",
      "- Contender: \(record.contenderID)",
      "- Channel: \(record.channelID)",
      "- Audience: \(record.simulatedAudience)",
      "- Verdict: \(record.verdict.rawValue)",
      "- Scores: attention \(record.scores.attention), intent \(record.scores.intentMatch), credibility \(record.scores.credibility), differentiation \(record.scores.differentiation), buyer reach \(record.scores.buyerReachability), economics \(record.scores.channelEconomics)",
    ]
    if !record.objections.isEmpty {
      lines += ["", "## Objections", ""]
      lines += record.objections.map { "- \($0)" }
    }
    if !record.rewriteRecommendations.isEmpty {
      lines += ["", "## Rewrite Recommendations", ""]
      lines += record.rewriteRecommendations.map { "- \($0)" }
    }
    return lines.joined(separator: "\n")
  }

  private static func decisionIntentLine(
    _ intent: ProductTournamentSimulationDecisionIntent
  ) -> String {
    var parts = [
      "target_decision \(intent.targetDecision.rawValue)",
      "current_decision \(intent.currentDecision.rawValue)",
    ]
    let directive = StringUtils.boundedText(intent.directive, limit: 180)
    if !directive.isEmpty {
      parts.append("directive \(directive)")
    }
    if !intent.scorecardFocus.isEmpty {
      parts.append("focus \(intent.scorecardFocus.prefix(5).joined(separator: ", "))")
    }
    return parts.joined(separator: "; ")
  }

  private static func decisionIntentEvaluationLine(
    _ evaluation: ProductTournamentEvidenceDecisionIntentEvaluation
  ) -> String {
    let rationale = StringUtils.boundedText(evaluation.rationale, limit: 220)
    guard !rationale.isEmpty else { return evaluation.outcome.rawValue }
    return "\(evaluation.outcome.rawValue); \(rationale)"
  }

  private static func priceLabel(cents: Int) -> String {
    let dollars = Double(max(0, cents)) / 100
    return String(format: "$%.0f/month", dollars)
  }
}

extension String {
  fileprivate var normalizedProductTournamentEvidenceText: String {
    lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}

extension Array where Element == String {
  fileprivate func productTournamentEvidenceUniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self {
      guard seen.insert(value).inserted else { continue }
      out.append(value)
    }
    return out
  }
}
