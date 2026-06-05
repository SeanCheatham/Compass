import Foundation

enum ProductizationSimulationMode: String, Codable, CaseIterable, Equatable, Sendable {
  case modelFree = "model_free"
  case personaModel = "persona_model"

  var productFactoryLabel: String {
    switch self {
    case .modelFree: return "Model-free"
    case .personaModel: return "AI-user"
    }
  }
}

enum ProductizationRunStatus: String, Codable, Equatable, Sendable {
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

enum ProductizationEvidenceVerdict: String, Codable, CaseIterable, Equatable, Sendable {
  case strongPull = "strong_pull"
  case promising
  case unclear
  case weak
  case rejected
}

enum ProductMarketFitRecommendation: String, Codable, CaseIterable, Equatable, Sendable {
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

struct ProductMarketFitReadiness: Codable, Equatable, Identifiable, Sendable {
  var id: String { experimentID }

  var experimentID: String
  var runCount: Int
  var completedRunCount: Int
  var failedRunCount: Int
  var aiUserCompletedRunCount: Int
  var aiUserDistinctPersonaCount: Int
  var modelFreeCompletedRunCount: Int
  var distinctPersonaCount: Int
  var latestRunID: String?
  var readinessScore: Double
  var averageScore: Double
  var strongestVerdict: ProductizationEvidenceVerdict
  var weakestVerdict: ProductizationEvidenceVerdict
  var recommendation: ProductMarketFitRecommendation
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
    case aiUserCompletedRunCount
    case aiUserDistinctPersonaCount
    case modelFreeCompletedRunCount
    case distinctPersonaCount
    case latestRunID
    case readinessScore
    case averageScore
    case strongestVerdict
    case weakestVerdict
    case recommendation
    case rationale
    case evidenceRunIDs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let aiUserCompletedRunCount = try container.decodeIfPresent(
      Int.self,
      forKey: .aiUserCompletedRunCount
    ) ?? 0
    let distinctPersonaCount = try container.decodeIfPresent(
      Int.self,
      forKey: .distinctPersonaCount
    ) ?? 0
    let aiUserDistinctPersonaCount = try container.decodeIfPresent(
      Int.self,
      forKey: .aiUserDistinctPersonaCount
    ) ?? min(aiUserCompletedRunCount, distinctPersonaCount)

    self.init(
      experimentID: try container.decode(String.self, forKey: .experimentID),
      runCount: try container.decode(Int.self, forKey: .runCount),
      completedRunCount: try container.decode(Int.self, forKey: .completedRunCount),
      failedRunCount: try container.decode(Int.self, forKey: .failedRunCount),
      aiUserCompletedRunCount: aiUserCompletedRunCount,
      aiUserDistinctPersonaCount: aiUserDistinctPersonaCount,
      modelFreeCompletedRunCount: try container.decodeIfPresent(
        Int.self,
        forKey: .modelFreeCompletedRunCount
      ) ?? 0,
      distinctPersonaCount: distinctPersonaCount,
      latestRunID: try container.decodeIfPresent(String.self, forKey: .latestRunID),
      readinessScore: try container.decode(Double.self, forKey: .readinessScore),
      averageScore: try container.decode(Double.self, forKey: .averageScore),
      strongestVerdict: try container.decode(
        ProductizationEvidenceVerdict.self,
        forKey: .strongestVerdict
      ),
      weakestVerdict: try container.decode(
        ProductizationEvidenceVerdict.self,
        forKey: .weakestVerdict
      ),
      recommendation: try container.decode(
        ProductMarketFitRecommendation.self,
        forKey: .recommendation
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
    aiUserCompletedRunCount: Int,
    aiUserDistinctPersonaCount: Int,
    modelFreeCompletedRunCount: Int,
    distinctPersonaCount: Int,
    latestRunID: String?,
    readinessScore: Double,
    averageScore: Double,
    strongestVerdict: ProductizationEvidenceVerdict,
    weakestVerdict: ProductizationEvidenceVerdict,
    recommendation: ProductMarketFitRecommendation,
    rationale: [String],
    evidenceRunIDs: [String]
  ) {
    self.experimentID = ProductizationEvidenceRecord.cleanedIdentifier(
      experimentID,
      fallback: "experiment"
    )
    self.runCount = max(0, runCount)
    self.completedRunCount = max(0, completedRunCount)
    self.failedRunCount = max(0, failedRunCount)
    self.aiUserCompletedRunCount = max(0, aiUserCompletedRunCount)
    self.aiUserDistinctPersonaCount = max(0, aiUserDistinctPersonaCount)
    self.modelFreeCompletedRunCount = max(0, modelFreeCompletedRunCount)
    self.distinctPersonaCount = max(0, distinctPersonaCount)
    self.latestRunID = ProductizationEvidenceRecord.optionalBounded(latestRunID, limit: 96)
    self.readinessScore = Self.roundedScore(readinessScore, upperBound: 100)
    self.averageScore = Self.roundedScore(averageScore, upperBound: 5)
    self.strongestVerdict = strongestVerdict
    self.weakestVerdict = weakestVerdict
    self.recommendation = recommendation
    self.rationale = ProductizationEvidenceRecord.cleanedList(rationale, limit: 260)
    self.evidenceRunIDs = ProductizationEvidenceRecord.cleanedList(evidenceRunIDs, limit: 96)
  }

  init(summaries rawSummaries: [ProductizationEvidenceSummary]) {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let failedCount = summaries.count - completed.count
    let aiUserCompleted = completed.filter { $0.mode == .personaModel }
    let aiUserCompletedCount = aiUserCompleted.count
    let aiUserPersonaCount = Set(aiUserCompleted.map(\.personaID).filter { !$0.isEmpty }).count
    let modelFreeCompletedCount = completed.filter { $0.mode == .modelFree }.count
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
      aiUserDistinctPersonaCount: aiUserPersonaCount,
      failedRunCount: failedCount
    )

    self.init(
      experimentID: summaries.first?.experimentID ?? "experiment",
      runCount: summaries.count,
      completedRunCount: completed.count,
      failedRunCount: failedCount,
      aiUserCompletedRunCount: aiUserCompletedCount,
      aiUserDistinctPersonaCount: aiUserPersonaCount,
      modelFreeCompletedRunCount: modelFreeCompletedCount,
      distinctPersonaCount: personaCount,
      latestRunID: summaries.first?.runID,
      readinessScore: readinessScore,
      averageScore: averageScore,
      strongestVerdict: strongest,
      weakestVerdict: weakest,
      recommendation: recommendation,
      rationale: Self.rationale(
        summaries: summaries,
        completed: completed,
        readinessScore: readinessScore,
        averageScore: averageScore,
        distinctPersonaCount: personaCount,
        aiUserCompletedRunCount: aiUserCompletedCount,
        aiUserDistinctPersonaCount: aiUserPersonaCount,
        modelFreeCompletedRunCount: modelFreeCompletedCount,
        failedRunCount: failedCount,
        recommendation: recommendation
      ),
      evidenceRunIDs: summaries.prefix(8).map(\.runID)
    )
  }

  private static func readinessScore(
    summaries: [ProductizationEvidenceSummary],
    completed: [ProductizationEvidenceSummary],
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
    summaries: [ProductizationEvidenceSummary],
    completed: [ProductizationEvidenceSummary],
    readinessScore: Double,
    averageScore: Double,
    distinctPersonaCount: Int,
    aiUserDistinctPersonaCount: Int,
    failedRunCount: Int
  ) -> ProductMarketFitRecommendation {
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
    let productPull =
      [workflowImprovement, alternativeAdvantage, switchingReadiness, continuedUsePull]
      .filter { $0 > 0 }
      .max() ?? 0

    if completed.count >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.1
        || rejectedOrWeakCount >= 2)
    {
      return aiUserDistinctPersonaCount >= 2 ? .kill : .gatherEvidence
    }
    if completed.count >= 2 && painRecognition >= 4 && productPull > 0 && productPull <= 2.8 {
      return .pivot
    }
    if completed.count >= 3
      && distinctPersonaCount >= 2
      && aiUserDistinctPersonaCount >= 2
      && readinessScore >= 76
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
    summaries: [ProductizationEvidenceSummary],
    completed: [ProductizationEvidenceSummary],
    readinessScore: Double,
    averageScore: Double,
    distinctPersonaCount: Int,
    aiUserCompletedRunCount: Int,
    aiUserDistinctPersonaCount: Int,
    modelFreeCompletedRunCount: Int,
    failedRunCount: Int,
    recommendation: ProductMarketFitRecommendation
  ) -> [String] {
    var lines = [
      "\(completed.count) completed of \(summaries.count) run(s) across \(distinctPersonaCount) persona(s)."
    ]
    if averageScore > 0 {
      lines.append(
        "Average PMF score \(format(averageScore))/5; readiness \(format(readinessScore))/100.")
    } else {
      lines.append(
        "No persona scorecard is available yet; readiness depends on run status and verdicts.")
    }
    let missing = completed.flatMap(\.missingCapabilities)
      .map(\.normalizedProductizationEvidenceText)
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
    lines.append(
      "\(aiUserCompletedRunCount) AI-user run(s) across \(aiUserDistinctPersonaCount) persona(s), \(modelFreeCompletedRunCount) model-free run(s)."
    )
    if aiUserCompletedRunCount == 0 && !completed.isEmpty {
      lines.append("No AI-user evidence has tested this bet yet; promotion requires simulated-user pull.")
    } else if aiUserDistinctPersonaCount < 2 && !completed.isEmpty {
      lines.append("Decisive PMF decisions require AI-user evidence across at least 2 personas.")
    }
    switch recommendation {
    case .promote:
      lines.append("Evidence breadth and pull are high enough to consider promotion.")
    case .kill:
      lines.append("Evidence is consistently weak enough to stop this bet.")
    case .pivot:
      lines.append("The pain is recognized, but this product shape is not creating enough pull.")
    case .narrow:
      lines.append("Evidence points to a smaller next proof before broader investment.")
    case .keepGoing:
      lines.append("Signals are positive but need more proof before promotion.")
    case .gatherEvidence:
      lines.append("Run more scenarios before changing the product decision.")
    }
    return lines
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
    in summaries: [ProductizationEvidenceSummary]
  ) -> Int {
    repeatedObjections(in: summaries).count
  }

  private static func repeatedObjections(
    in summaries: [ProductizationEvidenceSummary]
  ) -> [String] {
    let counts = Dictionary(
      grouping: summaries.flatMap(\.objections).map(\.normalizedProductizationEvidenceText),
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

  private static func verdictRank(_ verdict: ProductizationEvidenceVerdict) -> Int {
    switch verdict {
    case .rejected: return 0
    case .weak: return 1
    case .unclear: return 2
    case .promising: return 3
    case .strongPull: return 4
    }
  }

  private static func verdictContribution(_ verdict: ProductizationEvidenceVerdict) -> Double {
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

struct ProductizationRunFailure: Codable, Equatable, Sendable {
  var status: ProductizationRunStatus
  var message: String
  var stdout: String
  var stderr: String

  init(
    status: ProductizationRunStatus,
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

struct ProductizationEvidenceScores: Codable, Equatable, Sendable {
  var painRecognition: Int?
  var workflowImprovement: Int?
  var alternativeAdvantage: Int?
  var switchingReadiness: Int?
  var continuedUsePull: Int?

  init(
    painRecognition: Int? = nil,
    workflowImprovement: Int? = nil,
    alternativeAdvantage: Int? = nil,
    switchingReadiness: Int? = nil,
    continuedUsePull: Int? = nil
  ) {
    self.painRecognition = Self.clamped(painRecognition)
    self.workflowImprovement = Self.clamped(workflowImprovement)
    self.alternativeAdvantage = Self.clamped(alternativeAdvantage)
    self.switchingReadiness = Self.clamped(switchingReadiness)
    self.continuedUsePull = Self.clamped(continuedUsePull)
  }

  var hasScores: Bool {
    painRecognition != nil
      || workflowImprovement != nil
      || alternativeAdvantage != nil
      || switchingReadiness != nil
      || continuedUsePull != nil
  }

  private static func clamped(_ value: Int?) -> Int? {
    value.map { min(5, max(1, $0)) }
  }
}

struct ProductizationEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
  static let supportedSchemaVersion = 1

  var id: String
  var schemaVersion: Int
  var projectID: String?
  var experimentID: String
  var solutionID: String
  var painID: String
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductizationSimulationMode
  var status: ProductizationRunStatus
  var startedAt: Double
  var endedAt: Double
  var traceHash: String?
  var traceArtifactPath: String?
  var feedbackArtifactPath: String?
  var transcriptArtifactPath: String?
  var summaryArtifactPath: String?
  var promptVersions: [String]
  var model: String
  var scores: ProductizationEvidenceScores
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var verdict: ProductizationEvidenceVerdict
  var summary: String
  var failure: ProductizationRunFailure?

  init(
    id: String,
    schemaVersion: Int = Self.supportedSchemaVersion,
    projectID: String? = nil,
    experimentID: String,
    solutionID: String,
    painID: String,
    branchName: String,
    commitSha: String,
    scenarioID: String,
    personaID: String,
    mode: ProductizationSimulationMode,
    status: ProductizationRunStatus,
    startedAt: Double,
    endedAt: Double,
    traceHash: String? = nil,
    traceArtifactPath: String? = nil,
    feedbackArtifactPath: String? = nil,
    transcriptArtifactPath: String? = nil,
    summaryArtifactPath: String? = nil,
    promptVersions: [String] = [],
    model: String = "",
    scores: ProductizationEvidenceScores = ProductizationEvidenceScores(),
    objections: [String] = [],
    missingCapabilities: [String] = [],
    currentAlternativeComparison: String = "",
    verdict: ProductizationEvidenceVerdict = .unclear,
    summary: String,
    failure: ProductizationRunFailure? = nil
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "productization-run")
    self.schemaVersion = schemaVersion
    self.projectID = Self.optionalBounded(projectID, limit: 80)
    self.experimentID = Self.cleanedIdentifier(experimentID, fallback: "experiment")
    self.solutionID = Self.cleanedIdentifier(solutionID, fallback: "solution")
    self.painID = Self.cleanedIdentifier(painID, fallback: "pain")
    self.branchName = StringUtils.boundedText(branchName, limit: 200)
    let boundedCommit = StringUtils.boundedText(commitSha, limit: 80)
    self.commitSha = boundedCommit.isEmpty ? "unknown" : boundedCommit
    self.scenarioID = Self.cleanedIdentifier(scenarioID, fallback: "scenario")
    self.personaID = Self.cleanedIdentifier(personaID, fallback: "persona")
    self.mode = mode
    self.status = status
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.traceHash = Self.optionalBounded(traceHash, limit: 128)
    self.traceArtifactPath = Self.optionalBounded(traceArtifactPath, limit: 500)
    self.feedbackArtifactPath = Self.optionalBounded(feedbackArtifactPath, limit: 500)
    self.transcriptArtifactPath = Self.optionalBounded(transcriptArtifactPath, limit: 500)
    self.summaryArtifactPath = Self.optionalBounded(summaryArtifactPath, limit: 500)
    self.promptVersions = Self.cleanedList(promptVersions, limit: 160)
    self.model = StringUtils.boundedText(model, limit: 160)
    self.scores = scores
    self.objections = Self.cleanedList(objections, limit: 500)
    self.missingCapabilities = Self.cleanedList(missingCapabilities, limit: 160)
    self.currentAlternativeComparison = StringUtils.boundedText(
      currentAlternativeComparison, limit: 1_000)
    self.verdict = verdict
    self.summary = StringUtils.boundedText(summary, limit: 1_500)
    self.failure = failure
  }

  init(
    runResult: ProductizationRunResult,
    id: String = UUID().uuidString,
    startedAt: Double,
    endedAt: Double
  ) {
    let traceSignals = runResult.productizationTrace?.painReliefSignals
    let missing = traceSignals?.missingCapabilityIDs ?? []
    let comparison =
      traceSignals?.currentAlternativeAddressed == true
      ? "The deterministic trace addressed the current alternative."
      : "The deterministic trace did not address the current alternative."
    self.init(
      id: id,
      projectID: runResult.projectID?.uuidString,
      experimentID: runResult.experimentID,
      solutionID: runResult.solutionID,
      painID: runResult.painID,
      branchName: runResult.branchName,
      commitSha: runResult.commitSha,
      scenarioID: runResult.scenarioID,
      personaID: runResult.personaID,
      mode: runResult.mode,
      status: runResult.status,
      startedAt: startedAt,
      endedAt: endedAt,
      traceHash: runResult.experienceTraceHash,
      promptVersions: runResult.rawPersonaActionTranscript.map(\.promptVersionID)
        .productizationEvidenceUniquedPreservingOrder(),
      model: runResult.model,
      scores: Self.derivedScores(status: runResult.status, signals: traceSignals),
      objections: [],
      missingCapabilities: missing,
      currentAlternativeComparison: comparison,
      verdict: Self.derivedVerdict(status: runResult.status, signals: traceSignals),
      summary: traceSignals?.evidenceSummary ?? runResult.failure?.message ?? "No summary.",
      failure: runResult.failure
    )
  }

  var summaryRecord: ProductizationEvidenceSummary {
    ProductizationEvidenceSummary(record: self)
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
      .productizationEvidenceUniquedPreservingOrder()
  }

  static func optionalBounded(_ value: String?, limit: Int) -> String? {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }

  private static func derivedScores(
    status: ProductizationRunStatus,
    signals: ProductizationPainReliefSignals?
  ) -> ProductizationEvidenceScores {
    guard status == .completed, let signals else {
      return ProductizationEvidenceScores()
    }
    let missingPenalty = signals.missingCapabilityIDs.isEmpty ? 0 : 1
    let positiveWithPenalty = max(2, 4 - missingPenalty)
    return ProductizationEvidenceScores(
      painRecognition: signals.painRecognized ? 4 : 1,
      workflowImprovement: signals.workflowAdvanced ? positiveWithPenalty : 2,
      alternativeAdvantage: signals.currentAlternativeAddressed ? positiveWithPenalty : 2,
      switchingReadiness: signals.switchingObjectionReduced ? positiveWithPenalty : 2,
      continuedUsePull: continuedUsePullScore(signals: signals)
    )
  }

  private static func continuedUsePullScore(signals: ProductizationPainReliefSignals) -> Int {
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

  private static func derivedVerdict(
    status: ProductizationRunStatus,
    signals: ProductizationPainReliefSignals?
  ) -> ProductizationEvidenceVerdict {
    guard status == .completed, let signals else { return .unclear }
    guard signals.painRecognized, signals.workflowAdvanced else { return .weak }
    guard signals.missingCapabilityIDs.isEmpty else { return .unclear }
    return signals.currentAlternativeAddressed ? .promising : .unclear
  }
}

struct ProductizationEvidenceSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var runID: String
  var experimentID: String
  var solutionID: String
  var painID: String
  var branchName: String
  var commitSha: String
  var scenarioID: String
  var personaID: String
  var mode: ProductizationSimulationMode
  var status: ProductizationRunStatus
  var startedAt: Double
  var endedAt: Double
  var model: String
  var verdict: ProductizationEvidenceVerdict
  var scores: ProductizationEvidenceScores
  var objections: [String]
  var missingCapabilities: [String]
  var currentAlternativeComparison: String
  var traceHash: String?
  var summary: String
  var failureKind: String?

  init(record: ProductizationEvidenceRecord) {
    id = record.id
    runID = record.id
    experimentID = record.experimentID
    solutionID = record.solutionID
    painID = record.painID
    branchName = record.branchName
    commitSha = record.commitSha
    scenarioID = record.scenarioID
    personaID = record.personaID
    mode = record.mode
    status = record.status
    startedAt = record.startedAt
    endedAt = record.endedAt
    model = record.model
    verdict = record.verdict
    scores = record.scores
    objections = record.objections
    missingCapabilities = record.missingCapabilities
    currentAlternativeComparison = record.currentAlternativeComparison
    traceHash = record.traceHash
    summary = record.summary
    failureKind = record.failure?.status.rawValue
  }

  var isCompleted: Bool {
    status == .completed
  }
}

struct ProductizationEvidenceIndex: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1
  static let empty = ProductizationEvidenceIndex()

  var schemaVersion: Int
  var updatedAt: Double
  var summaries: [ProductizationEvidenceSummary]
  var aggregate: ProductizationEvidenceAggregateSummary
  var malformedRecordCount: Int

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    updatedAt: Double = 0,
    summaries: [ProductizationEvidenceSummary] = [],
    aggregate: ProductizationEvidenceAggregateSummary = .empty,
    malformedRecordCount: Int = 0
  ) {
    self.schemaVersion = schemaVersion
    self.updatedAt = updatedAt
    self.summaries = summaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    self.aggregate = aggregate
    self.malformedRecordCount = malformedRecordCount
  }

  static func build(
    records: [ProductizationEvidenceRecord],
    malformedRecordCount: Int = 0,
    now: Date = Date()
  ) -> ProductizationEvidenceIndex {
    let summaries = records.map(\.summaryRecord)
    return ProductizationEvidenceIndex(
      updatedAt: now.timeIntervalSince1970,
      summaries: summaries,
      aggregate: ProductizationEvidenceAggregateSummary(summaries: summaries),
      malformedRecordCount: malformedRecordCount
    )
  }

  func targetCommit(for experiment: ProductExperiment) -> String? {
    let commit = experiment.currentSha ?? experiment.baseSha ?? ""
    let trimmed = commit.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func summaries(
    for experiment: ProductExperiment,
    currentCommitOnly: Bool = true
  ) -> [ProductizationEvidenceSummary] {
    let experimentSummaries = summaries.filter { $0.experimentID == experiment.id }
    guard currentCommitOnly, let targetCommit = targetCommit(for: experiment) else {
      return experimentSummaries
    }
    return experimentSummaries.filter {
      ProductExperimentGit.commitMatches(expected: targetCommit, actual: $0.commitSha)
    }
  }

  func staleSummaryCount(for experiment: ProductExperiment) -> Int {
    let all = summaries(for: experiment, currentCommitOnly: false)
    return max(0, all.count - summaries(for: experiment).count)
  }

  func currentPMFReadiness(for experiment: ProductExperiment) -> ProductMarketFitReadiness? {
    let currentSummaries = summaries(for: experiment)
    guard !currentSummaries.isEmpty else { return nil }
    return ProductMarketFitReadiness(summaries: currentSummaries)
  }
}

struct ProductizationEvidenceAggregateSummary: Codable, Equatable, Sendable {
  static let empty = ProductizationEvidenceAggregateSummary(
    latestRunByExperiment: [:],
    pmfReadinessByExperiment: [],
    repeatedObjections: [],
    lowScoreClusters: [],
    missingCapabilityFrequency: [],
    verdictCounts: [:],
    failuresByKind: [:],
    currentAlternativeComparisons: []
  )

  var latestRunByExperiment: [String: String]
  var pmfReadinessByExperiment: [ProductMarketFitReadiness]
  var repeatedObjections: [ProductizationRepeatedObjection]
  var lowScoreClusters: [ProductizationScoreCluster]
  var missingCapabilityFrequency: [ProductizationMissingCapabilityCount]
  var verdictCounts: [String: Int]
  var failuresByKind: [String: Int]
  var currentAlternativeComparisons: [ProductizationAlternativeComparisonSummary]

  enum CodingKeys: String, CodingKey {
    case latestRunByExperiment
    case pmfReadinessByExperiment
    case repeatedObjections
    case lowScoreClusters
    case missingCapabilityFrequency
    case verdictCounts
    case failuresByKind
    case currentAlternativeComparisons
  }

  init(
    latestRunByExperiment: [String: String],
    pmfReadinessByExperiment: [ProductMarketFitReadiness] = [],
    repeatedObjections: [ProductizationRepeatedObjection],
    lowScoreClusters: [ProductizationScoreCluster],
    missingCapabilityFrequency: [ProductizationMissingCapabilityCount],
    verdictCounts: [String: Int],
    failuresByKind: [String: Int],
    currentAlternativeComparisons: [ProductizationAlternativeComparisonSummary]
  ) {
    self.latestRunByExperiment = latestRunByExperiment
    self.pmfReadinessByExperiment = pmfReadinessByExperiment
    self.repeatedObjections = repeatedObjections
    self.lowScoreClusters = lowScoreClusters
    self.missingCapabilityFrequency = missingCapabilityFrequency
    self.verdictCounts = verdictCounts
    self.failuresByKind = failuresByKind
    self.currentAlternativeComparisons = currentAlternativeComparisons
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      latestRunByExperiment: try container.decodeIfPresent(
        [String: String].self,
        forKey: .latestRunByExperiment
      ) ?? [:],
      pmfReadinessByExperiment: try container.decodeIfPresent(
        [ProductMarketFitReadiness].self,
        forKey: .pmfReadinessByExperiment
      ) ?? [],
      repeatedObjections: try container.decodeIfPresent(
        [ProductizationRepeatedObjection].self,
        forKey: .repeatedObjections
      ) ?? [],
      lowScoreClusters: try container.decodeIfPresent(
        [ProductizationScoreCluster].self,
        forKey: .lowScoreClusters
      ) ?? [],
      missingCapabilityFrequency: try container.decodeIfPresent(
        [ProductizationMissingCapabilityCount].self,
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
      currentAlternativeComparisons: try container.decodeIfPresent(
        [ProductizationAlternativeComparisonSummary].self,
        forKey: .currentAlternativeComparisons
      ) ?? []
    )
  }

  init(summaries: [ProductizationEvidenceSummary]) {
    var latest: [String: ProductizationEvidenceSummary] = [:]
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
    pmfReadinessByExperiment = Dictionary(grouping: summaries, by: \.experimentID)
      .map { _, group in ProductMarketFitReadiness(summaries: group) }
      .sorted { lhs, rhs in
        if lhs.readinessScore == rhs.readinessScore {
          return lhs.experimentID < rhs.experimentID
        }
        return lhs.readinessScore > rhs.readinessScore
      }

    let objectionCounts = Dictionary(
      grouping: summaries.flatMap(\.objections).map(\.normalizedProductizationEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    repeatedObjections =
      objectionCounts
      .filter { !$0.key.isEmpty && $0.value > 1 }
      .map { ProductizationRepeatedObjection(objection: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.objection < rhs.objection }
        return lhs.count > rhs.count
      }

    let missingCounts = Dictionary(
      grouping: summaries.flatMap(\.missingCapabilities).map(
        \.normalizedProductizationEvidenceText),
      by: { $0 }
    ).mapValues(\.count)
    missingCapabilityFrequency =
      missingCounts
      .filter { !$0.key.isEmpty }
      .map { ProductizationMissingCapabilityCount(capabilityID: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.capabilityID < rhs.capabilityID }
        return lhs.count > rhs.count
      }

    verdictCounts = Dictionary(grouping: summaries.map { $0.verdict.rawValue }, by: { $0 })
      .mapValues(\.count)

    failuresByKind = Dictionary(
      grouping: summaries.compactMap { summary -> String? in
        guard !summary.isCompleted else { return nil }
        return summary.failureKind ?? summary.status.rawValue
      },
      by: { $0 }
    ).mapValues(\.count)

    let scoreGroups = Dictionary(grouping: summaries.filter { $0.scores.hasScores }) {
      "\($0.experimentID)|\($0.personaID)"
    }
    lowScoreClusters = scoreGroups.map { _, group in
      ProductizationScoreCluster(summaries: group)
    }
    .filter { $0.minimumScore > 0 && $0.minimumScore <= 2.5 }
    .sorted { lhs, rhs in
      if lhs.minimumScore == rhs.minimumScore {
        return "\(lhs.experimentID)|\(lhs.personaID)" < "\(rhs.experimentID)|\(rhs.personaID)"
      }
      return lhs.minimumScore < rhs.minimumScore
    }

    currentAlternativeComparisons =
      summaries
      .filter { !$0.currentAlternativeComparison.isEmpty }
      .prefix(12)
      .map {
        ProductizationAlternativeComparisonSummary(
          runID: $0.runID,
          experimentID: $0.experimentID,
          comparison: $0.currentAlternativeComparison,
          verdict: $0.verdict
        )
      }
  }
}

struct ProductizationRepeatedObjection: Codable, Equatable, Sendable {
  var objection: String
  var count: Int
}

struct ProductizationMissingCapabilityCount: Codable, Equatable, Sendable {
  var capabilityID: String
  var count: Int
}

struct ProductizationAlternativeComparisonSummary: Codable, Equatable, Sendable {
  var runID: String
  var experimentID: String
  var comparison: String
  var verdict: ProductizationEvidenceVerdict
}

struct ProductizationScoreCluster: Codable, Equatable, Sendable {
  var experimentID: String
  var personaID: String
  var runCount: Int
  var painRecognition: Double
  var workflowImprovement: Double
  var alternativeAdvantage: Double
  var switchingReadiness: Double
  var continuedUsePull: Double
  var minimumScore: Double

  init(summaries: [ProductizationEvidenceSummary]) {
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

struct ProductizationEvidenceStore {
  var productizationURL: URL

  init(workspace: CompassWorkspace) {
    self.productizationURL = workspace.productizationURL
  }

  var runsURL: URL { productizationURL.appending(path: "runs", directoryHint: .isDirectory) }
  var indexURL: URL { productizationURL.appending(path: "evidence-index.json") }

  func readIndex() throws -> ProductizationEvidenceIndex {
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: indexURL)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(ProductizationEvidenceIndex.self, from: data)
  }

  func readRecord(id: String) throws -> ProductizationEvidenceRecord {
    let data = try Data(contentsOf: recordURL(id: id))
    return try JSONDecoder().decode(ProductizationEvidenceRecord.self, from: data)
  }

  @discardableResult
  func writeRecord(
    _ record: ProductizationEvidenceRecord,
    traceJSON: String? = nil,
    feedbackJSON: String? = nil,
    transcriptJSONL: String? = nil,
    summaryMarkdown: String? = nil,
    now: Date = Date()
  ) throws -> ProductizationEvidenceRecord {
    let safeID = Self.safeRunID(record.id)
    let runURL = runsURL.appending(path: safeID, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)

    var stored = record
    if let traceJSON, !traceJSON.isEmpty {
      stored.traceArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "productization/runs/\(safeID)/trace.json",
        fileName: "trace.json",
        contents: traceJSON
      )
    }
    if let feedbackJSON, !feedbackJSON.isEmpty {
      stored.feedbackArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "productization/runs/\(safeID)/feedback.json",
        fileName: "feedback.json",
        contents: feedbackJSON
      )
    }
    if let transcriptJSONL, !transcriptJSONL.isEmpty {
      stored.transcriptArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "productization/runs/\(safeID)/transcript.jsonl",
        fileName: "transcript.jsonl",
        contents: transcriptJSONL
      )
    }
    let summary = summaryMarkdown ?? ProductizationEvidenceMarkdownExporter.markdown(record: stored)
    if !summary.isEmpty {
      stored.summaryArtifactPath = try writeArtifact(
        runURL: runURL,
        relativePath: "productization/runs/\(safeID)/summary.md",
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
  func rebuildIndex(now: Date = Date()) throws -> ProductizationEvidenceIndex {
    try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true)
    let urls = try FileManager.default.contentsOfDirectory(
      at: runsURL,
      includingPropertiesForKeys: nil
    )
    var records: [ProductizationEvidenceRecord] = []
    var malformed = 0
    for url in urls {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        records.append(
          try JSONDecoder().decode(
            ProductizationEvidenceRecord.self,
            from: Data(contentsOf: url.appending(path: "record.json"))
          ))
      } catch {
        malformed += 1
      }
    }
    let index = ProductizationEvidenceIndex.build(
      records: records,
      malformedRecordCount: malformed,
      now: now
    )
    let data = try Self.encoder().encode(index)
    try FileManager.default.createDirectory(
      at: productizationURL, withIntermediateDirectories: true)
    try data.write(to: indexURL, options: .atomic)
    return index
  }

  func recordURL(id: String) -> URL {
    runsURL
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
    ProductizationEvidenceRecord.cleanedIdentifier(id, fallback: "productization-run")
  }
}

enum ProductizationEvidenceMarkdownExporter {
  static func markdown(record: ProductizationEvidenceRecord) -> String {
    var lines = [
      "# Productization Evidence \(record.id)",
      "",
      "- Experiment: \(record.experimentID)",
      "- Solution: \(record.solutionID)",
      "- Pain: \(record.painID)",
      "- Branch: \(record.branchName)",
      "- Commit: \(record.commitSha)",
      "- Scenario: \(record.scenarioID)",
      "- Persona: \(record.personaID)",
      "- Mode: \(record.mode.rawValue)",
      "- Status: \(record.status.rawValue)",
      "- Verdict: \(record.verdict.rawValue)",
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
    ]
    if !record.objections.isEmpty {
      lines += ["", "## Objections", ""]
      lines += record.objections.map { "- \($0)" }
    }
    if !record.missingCapabilities.isEmpty {
      lines += ["", "## Missing Capabilities", ""]
      lines += record.missingCapabilities.map { "- \($0)" }
    }
    if let failure = record.failure {
      lines += ["", "## Failure", "", "\(failure.status.rawValue): \(failure.message)"]
    }
    return lines.joined(separator: "\n")
  }
}

extension String {
  fileprivate var normalizedProductizationEvidenceText: String {
    lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}

extension Array where Element == String {
  fileprivate func productizationEvidenceUniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self {
      guard seen.insert(value).inserted else { continue }
      out.append(value)
    }
    return out
  }
}
