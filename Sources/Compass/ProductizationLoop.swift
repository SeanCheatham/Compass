import Foundation

struct ProductizationReflectDecisionUpdate: Codable, Equatable, Sendable {
  var experimentID: String
  var decision: ProductExperimentDecision
  var summary: String
  var evidenceRunIDs: [String]
  var decidedBy: String

  enum CodingKeys: String, CodingKey {
    case experimentID
    case experimentIDSnake = "experiment_id"
    case decision
    case summary
    case evidenceRunIDs
    case evidenceRunIDsSnake = "evidence_run_ids"
    case decidedBy
    case decidedBySnake = "decided_by"
  }

  init(
    experimentID: String,
    decision: ProductExperimentDecision,
    summary: String,
    evidenceRunIDs: [String] = [],
    decidedBy: String = "Reflect"
  ) {
    self.experimentID = ProductizationModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.decision = decision
    self.summary = StringUtils.boundedText(summary, limit: 1_000)
    self.evidenceRunIDs =
      ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "evidence-run") }
    self.decidedBy = StringUtils.boundedText(decidedBy, limit: 120)
    if self.decidedBy.isEmpty {
      self.decidedBy = "Reflect"
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let experimentID = try Self.decodeString(
      from: container,
      preferredKey: .experimentID,
      aliases: [.experimentIDSnake],
      fallback: "experiment"
    )
    let decision = try container.decode(ProductExperimentDecision.self, forKey: .decision)
    let summary =
      try Self.decodeOptionalString(
        from: container,
        preferredKey: .summary,
        aliases: []
      ) ?? ""
    let evidenceRunIDs =
      try Self.decodeOptionalStringArray(
        from: container,
        preferredKey: .evidenceRunIDs,
        aliases: [.evidenceRunIDsSnake]
      ) ?? []
    let decidedBy =
      try Self.decodeOptionalString(
        from: container,
        preferredKey: .decidedBy,
        aliases: [.decidedBySnake]
      ) ?? "Reflect"
    self.init(
      experimentID: experimentID,
      decision: decision,
      summary: summary,
      evidenceRunIDs: evidenceRunIDs,
      decidedBy: decidedBy
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(experimentID, forKey: .experimentID)
    try container.encode(decision, forKey: .decision)
    try container.encode(summary, forKey: .summary)
    try container.encode(evidenceRunIDs, forKey: .evidenceRunIDs)
    try container.encode(decidedBy, forKey: .decidedBy)
  }

  private static func decodeString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fallback: String
  ) throws -> String {
    try decodeOptionalString(from: container, preferredKey: preferredKey, aliases: aliases)
      ?? fallback
  }

  private static func decodeOptionalString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> String? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try container.decodeIfPresent(String.self, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }

  private static func decodeOptionalStringArray(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> [String]? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }
}

enum ProductizationDecisionTransitionError: LocalizedError, Equatable {
  case invalidTransition(
    experimentID: String,
    from: ProductExperimentDecision,
    to: ProductExperimentDecision
  )
  case missingSummary(experimentID: String, decision: ProductExperimentDecision)
  case unknownExperiment(String)

  var errorDescription: String? {
    switch self {
    case .invalidTransition(let experimentID, let from, let to):
      return
        "Reflect tried to move product experiment \(experimentID) from \(from.rawValue) to \(to.rawValue), which is not an allowed productization transition."
    case .missingSummary(let experimentID, let decision):
      return
        "Reflect tried to mark product experiment \(experimentID) as \(decision.rawValue) without a decision summary."
    case .unknownExperiment(let id):
      return "Reflect tried to update unknown product experiment \(id)."
    }
  }
}

enum ProductizationDecisionTransitionValidator {
  static func validate(
    experimentID: String,
    from current: ProductExperimentDecision,
    to proposed: ProductExperimentDecision,
    summary: String
  ) throws {
    if requiresSummary(proposed)
      && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      throw ProductizationDecisionTransitionError.missingSummary(
        experimentID: experimentID,
        decision: proposed
      )
    }

    guard allowedNextDecisions(from: current).contains(proposed) else {
      throw ProductizationDecisionTransitionError.invalidTransition(
        experimentID: experimentID,
        from: current,
        to: proposed
      )
    }
  }

  static func allowedNextDecisions(
    from current: ProductExperimentDecision
  ) -> Set<ProductExperimentDecision> {
    switch current {
    case .notRun:
      return [.keepGoing]
    case .keepGoing:
      return [.keepGoing, .narrow, .pivot, .kill, .promote]
    case .narrow:
      return [.keepGoing, .pivot, .kill, .promote]
    case .pivot:
      return [.keepGoing, .kill]
    case .kill:
      return [.archived]
    case .promote:
      return [.promoted]
    case .archived, .promoted:
      return []
    }
  }

  private static func requiresSummary(_ decision: ProductExperimentDecision) -> Bool {
    switch decision {
    case .kill, .promote, .archived, .promoted:
      return true
    case .notRun, .keepGoing, .narrow, .pivot:
      return false
    }
  }
}

struct ProductMarketFitDecisionProposal: Equatable, Sendable {
  var experimentID: String
  var currentDecision: ProductExperimentDecision
  var update: ProductizationReflectDecisionUpdate
  var readiness: ProductMarketFitReadiness
}

enum ProductMarketFitNextActionKind: String, Equatable, Sendable {
  case applyDecision = "apply_decision"
  case runCohort = "run_cohort"
  case rerunCohort = "rerun_cohort"
  case repairFailures = "repair_failures"
  case refineBet = "refine_bet"
  case reviewDecision = "review_decision"
}

enum ProductFactoryPortfolioPressure: String, Equatable, Sendable {
  case lift
  case cut
  case reshape
  case learn
  case repair
  case wait

  var title: String {
    switch self {
    case .lift: return "Lift"
    case .cut: return "Cut"
    case .reshape: return "Reshape"
    case .learn: return "Learn"
    case .repair: return "Repair"
    case .wait: return "Wait"
    }
  }

  var priorityBoost: Int {
    switch self {
    case .repair: return 90
    case .lift, .cut: return 80
    case .reshape: return 50
    case .learn: return 30
    case .wait: return 0
    }
  }
}

struct ProductFactoryDecisionCandidate: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var currentDecision: ProductExperimentDecision
  var targetDecision: ProductExperimentDecision
  var readinessScore: Int
  var pressure: ProductFactoryPortfolioPressure
  var evidenceRunIDs: [String]
  var summary: String

  var urgencyScore: Int {
    pressure.priorityBoost + decisionConfidenceScore
  }

  var displayTitle: String {
    "\(currentDecision.rawValue) -> \(targetDecision.rawValue)"
  }

  var displaySubtitle: String {
    let evidence = evidenceRunIDs.isEmpty ? "no evidence" : "\(evidenceRunIDs.count) evidence"
    return "\(pressure.title), \(readinessScore)/100, \(evidence)"
  }

  var displayDetail: String {
    let evidence =
      evidenceRunIDs.isEmpty
      ? "Evidence: none."
      : "Evidence: \(evidenceRunIDs.prefix(4).joined(separator: ", "))."
    return "\(summary) \(evidence)"
  }

  var auditSummary: String {
    var parts = [
      "\(experimentID): \(currentDecision.rawValue) -> \(targetDecision.rawValue)",
      "pressure \(pressure.rawValue)",
      "score \(readinessScore)/100",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))")
    }
    parts.append(StringUtils.boundedText(summary, limit: 160))
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 300)
  }

  init(proposal: ProductMarketFitDecisionProposal) {
    self.experimentID = ProductizationModelText.identifier(
      proposal.experimentID,
      fallback: "experiment"
    )
    self.currentDecision = proposal.currentDecision
    self.targetDecision = proposal.update.decision
    self.readinessScore = Int(proposal.readiness.readinessScore.rounded())
    self.pressure = ProductFactoryDecisionCandidateAdvisor.pressure(
      for: proposal.update.decision
    )
    self.evidenceRunIDs = ProductizationModelText.cleanedList(
      proposal.update.evidenceRunIDs,
      limit: 160
    )
    self.summary = ProductizationModelText.cleanedText(
      proposal.update.summary,
      fallback: "PMF decision candidate is ready.",
      limit: 1_000
    )
  }

  private var decisionConfidenceScore: Int {
    switch pressure {
    case .lift:
      return readinessScore
    case .cut:
      return 100 - readinessScore
    case .reshape:
      return abs(50 - readinessScore)
    case .learn, .repair, .wait:
      return 0
    }
  }
}

enum ProductFactoryDecisionCandidateAdvisor {
  static func candidates(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductFactoryDecisionCandidate] {
    ProductMarketFitDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .map(ProductFactoryDecisionCandidate.init(proposal:))
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func pressure(
    for decision: ProductExperimentDecision
  ) -> ProductFactoryPortfolioPressure {
    switch decision {
    case .promote, .promoted:
      return .lift
    case .kill, .archived:
      return .cut
    case .pivot, .narrow:
      return .reshape
    case .keepGoing:
      return .learn
    case .notRun:
      return .wait
    }
  }
}

struct ProductFactoryEvidenceTension: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var label: String
  var readinessScore: Int
  var strongestVerdict: ProductizationEvidenceVerdict
  var weakestVerdict: ProductizationEvidenceVerdict
  var positiveEvidenceRunIDs: [String]
  var negativeEvidenceRunIDs: [String]
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetCohortID: String?
  var summary: String

  var evidenceRunIDs: [String] {
    var seen = Set<String>()
    var runIDs: [String] = []
    for runID in positiveEvidenceRunIDs + negativeEvidenceRunIDs {
      guard !seen.contains(runID) else { continue }
      seen.insert(runID)
      runIDs.append(runID)
    }
    return runIDs
  }

  var urgencyScore: Int {
    85 + min(15, max(0, abs(readinessScore - 50) / 3))
  }

  var displayTitle: String {
    label
  }

  var displaySubtitle: String {
    var parts = [
      "\(readinessScore)/100",
      "\(strongestVerdict.rawValue) vs \(weakestVerdict.rawValue)",
    ]
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    return parts.joined(separator: ", ")
  }

  var displayDetail: String {
    let positive =
      positiveEvidenceRunIDs.isEmpty
      ? "positive evidence unavailable"
      : "positive \(positiveEvidenceRunIDs.prefix(3).joined(separator: ", "))"
    let negative =
      negativeEvidenceRunIDs.isEmpty
      ? "negative evidence unavailable"
      : "negative \(negativeEvidenceRunIDs.prefix(3).joined(separator: ", "))"
    var parts = ["\(summary) Evidence: \(positive); \(negative)."]
    if let targetScenarioID {
      parts.append("Target scenario: \(targetScenarioID).")
    } else if let targetPersonaName {
      parts.append("Target persona: \(targetPersonaName).")
    }
    return parts.joined(separator: " ")
  }

  var auditSummary: String {
    StringUtils.boundedText(
      "\(experimentID): \(label); score \(readinessScore)/100; \(strongestVerdict.rawValue) vs \(weakestVerdict.rawValue); evidence \(evidenceRunIDs.prefix(6).joined(separator: ", ")); \(summary)",
      limit: 320
    )
  }

  init(
    experimentID: String,
    label: String = "resolve split PMF evidence",
    readinessScore: Int,
    strongestVerdict: ProductizationEvidenceVerdict,
    weakestVerdict: ProductizationEvidenceVerdict,
    positiveEvidenceRunIDs: [String],
    negativeEvidenceRunIDs: [String],
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetCohortID: String? = nil,
    summary: String
  ) {
    self.experimentID = ProductizationModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.label = ProductizationModelText.cleanedText(
      label,
      fallback: "resolve split PMF evidence",
      limit: 120
    )
    self.readinessScore = min(100, max(0, readinessScore))
    self.strongestVerdict = strongestVerdict
    self.weakestVerdict = weakestVerdict
    self.positiveEvidenceRunIDs = ProductizationModelText.cleanedList(
      positiveEvidenceRunIDs,
      limit: 96
    )
    self.negativeEvidenceRunIDs = ProductizationModelText.cleanedList(
      negativeEvidenceRunIDs,
      limit: 96
    )
    self.targetPersonaID = ProductizationModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductizationModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductizationModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetCohortID = ProductizationModelText.optionalIdentifier(
      targetCohortID,
      fallback: "cohort"
    )
    self.summary = ProductizationModelText.cleanedText(
      summary,
      fallback:
        "Current PMF evidence contains both pull and rejection; resolve the split before lift/cut decisions.",
      limit: 1_000
    )
  }
}

enum ProductFactoryEvidenceTensionAdvisor {
  static func tensions(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductFactoryEvidenceTension] {
    config.experiments.compactMap { experiment in
      tension(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func tension(
    for experiment: ProductExperiment,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryEvidenceTension? {
    tension(for: experiment, config: nil, evidenceIndex: evidenceIndex)
  }

  static func tension(
    for experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryEvidenceTension? {
    tension(for: experiment, config: Optional(config), evidenceIndex: evidenceIndex)
  }

  private static func tension(
    for experiment: ProductExperiment,
    config: ProductizationConfig?,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryEvidenceTension? {
    guard let readiness = evidenceIndex.currentPMFReadiness(for: experiment) else {
      return nil
    }
    let completed = evidenceIndex.summaries(for: experiment).filter(\.isCompleted)
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
        return lhs.endedAt > rhs.endedAt
      }
    let positive = completed.filter { isPositive($0.verdict) }
    let negative = completed.filter { isNegative($0.verdict) }
    guard !positive.isEmpty, !negative.isEmpty else { return nil }

    let summary =
      "Current PMF evidence is split: \(positive.count) pull signal(s) and \(negative.count) rejection signal(s) on the current commit. Run a targeted AI-user comparison or narrow the scenario before applying lift/cut decisions."
    let target = config.flatMap {
      tensionTarget(for: negative, experiment: experiment, config: $0)
    }
    return ProductFactoryEvidenceTension(
      experimentID: experiment.id,
      readinessScore: Int(readiness.readinessScore.rounded()),
      strongestVerdict: readiness.strongestVerdict,
      weakestVerdict: readiness.weakestVerdict,
      positiveEvidenceRunIDs: positive.prefix(4).map(\.runID),
      negativeEvidenceRunIDs: negative.prefix(4).map(\.runID),
      targetPersonaID: target?.personaID,
      targetPersonaName: target?.personaName,
      targetScenarioID: target?.scenarioID,
      targetCohortID: target?.cohortID,
      summary: summary
    )
  }

  static func blocksAutomaticDecision(
    targetDecision: ProductExperimentDecision,
    experiment: ProductExperiment,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> Bool {
    guard targetDecision == .promote || targetDecision == .kill else { return false }
    return tension(for: experiment, evidenceIndex: evidenceIndex) != nil
  }

  private static func isPositive(_ verdict: ProductizationEvidenceVerdict) -> Bool {
    verdict == .strongPull || verdict == .promising
  }

  private static func isNegative(_ verdict: ProductizationEvidenceVerdict) -> Bool {
    verdict == .weak || verdict == .rejected
  }

  private struct EvidenceTensionTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
  }

  private static func tensionTarget(
    for negative: [ProductizationEvidenceSummary],
    experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> EvidenceTensionTarget? {
    for summary in negative {
      let scenarioID = summary.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !scenarioID.isEmpty,
        let scenario = config.scenarios.first(where: {
          $0.id == scenarioID && $0.experimentID == experiment.id
        })
      else { continue }
      let personaID = summary.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? scenario.segmentID
        : summary.personaID
      return EvidenceTensionTarget(
        personaID: personaID,
        personaName: segmentName(for: personaID, config: config),
        scenarioID: scenario.id,
        cohortID: scenario.enabled
          ? executableCohortID(
            forScenarioID: scenario.id,
            experiment: experiment,
            config: config
          )
          : nil
      )
    }

    guard let summary = negative.first(where: {
      !$0.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) else { return nil }
    return EvidenceTensionTarget(
      personaID: summary.personaID,
      personaName: segmentName(for: summary.personaID, config: config),
      scenarioID: nil,
      cohortID: nil
    )
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String,
    experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> String? {
    config.scenarioCohorts
      .filter {
        $0.experimentID == experiment.id
          && $0.enabled
          && $0.scenarioIDs.contains(scenarioID)
      }
      .sorted {
        if $0.scenarioIDs.count == $1.scenarioIDs.count { return $0.title < $1.title }
        return $0.scenarioIDs.count < $1.scenarioIDs.count
      }
      .first?.id
  }

  private static func segmentName(for segmentID: String, config: ProductizationConfig) -> String {
    let trimmed = segmentID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return segmentID }
    let name = config.userSegments.first { $0.id == trimmed }?.name ?? trimmed
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? trimmed : cleaned
  }
}

struct ProductMarketFitNextAction: Equatable, Sendable {
  var experimentID: String
  var kind: ProductMarketFitNextActionKind
  var title: String
  var detail: String
  var priority: Int
  var cohortID: String?
  var requiredSimulationMode: ProductizationSimulationMode?
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetDecision: ProductExperimentDecision?

  init(
    experimentID: String,
    kind: ProductMarketFitNextActionKind,
    title: String,
    detail: String,
    priority: Int,
    cohortID: String? = nil,
    requiredSimulationMode: ProductizationSimulationMode? = nil,
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetDecision: ProductExperimentDecision? = nil
  ) {
    self.experimentID = ProductizationModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.kind = kind
    self.title = StringUtils.boundedText(title, limit: 160)
    self.detail = StringUtils.boundedText(detail, limit: 500)
    self.priority = max(0, priority)
    self.cohortID = ProductizationModelText.optionalIdentifier(cohortID, fallback: "cohort")
    self.requiredSimulationMode = requiredSimulationMode
    self.targetPersonaID = ProductizationModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductizationModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductizationModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetDecision = targetDecision
  }
}

struct ProductMarketFitCohortRunReadiness: Equatable, Sendable {
  var cohortID: String
  var cohortTitle: String
  var cohortEnabled: Bool
  var enabledScenarioCount: Int
  var missingTargetCommitCount: Int
  var targetScenarioID: String?

  var canRun: Bool {
    cohortEnabled && enabledScenarioCount > 0 && missingTargetCommitCount == 0
  }

  var blockedReason: String? {
    if !cohortEnabled {
      return "Suggested cohort is disabled."
    }
    if enabledScenarioCount == 0 {
      if let targetScenarioID {
        return "Suggested target scenario `\(targetScenarioID)` is disabled or missing."
      }
      return "Suggested cohort has no enabled scenarios."
    }
    if missingTargetCommitCount > 0 {
      if targetScenarioID != nil {
        return "Suggested target scenario needs a target commit."
      }
      return "\(missingTargetCommitCount) enabled scenario(s) need a target commit."
    }
    return nil
  }

  init(
    cohortID: String,
    cohortTitle: String,
    cohortEnabled: Bool,
    enabledScenarioCount: Int,
    missingTargetCommitCount: Int,
    targetScenarioID: String? = nil
  ) {
    self.cohortID = ProductizationModelText.identifier(cohortID, fallback: "cohort")
    self.cohortTitle = ProductizationModelText.cleanedText(
      cohortTitle,
      fallback: "Product scenario cohort",
      limit: 180
    )
    self.cohortEnabled = cohortEnabled
    self.enabledScenarioCount = max(0, enabledScenarioCount)
    self.missingTargetCommitCount = max(0, missingTargetCommitCount)
    self.targetScenarioID = ProductizationModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
  }
}

struct ProductFactoryExperimentSignal: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var readinessScore: Int?
  var readinessRecommendation: ProductMarketFitRecommendation?
  var nextActionKind: ProductMarketFitNextActionKind?
  var nextActionTitle: String?
  var nextActionPriority: Int
  var pressure: ProductFactoryPortfolioPressure
  var staleEvidenceCount: Int
  var proofDebtCount: Int
  var proofDebtSummary: String?

  var urgencyScore: Int {
    (nextActionPriority * 1_000)
      + (readinessScore ?? 0)
      + pressure.priorityBoost
      + min(50, staleEvidenceCount * 5)
      + min(40, proofDebtCount * 4)
  }

  var pmfLabel: String {
    guard let readinessScore else { return "No current PMF evidence" }
    let recommendation = readinessRecommendation?.title ?? "Review"
    return "\(readinessScore)/100, \(recommendation)"
  }

  var nextActionLabel: String {
    guard let nextActionTitle else { return "No action queued" }
    return "\(nextActionTitle) (priority \(nextActionPriority))"
  }

  var pressureLabel: String {
    "\(pressure.title) pressure"
  }

  init(
    experimentID: String,
    readinessScore: Int?,
    readinessRecommendation: ProductMarketFitRecommendation?,
    nextActionKind: ProductMarketFitNextActionKind?,
    nextActionTitle: String?,
    nextActionPriority: Int,
    pressure: ProductFactoryPortfolioPressure,
    staleEvidenceCount: Int,
    proofDebtCount: Int = 0,
    proofDebtSummary: String? = nil
  ) {
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.readinessScore = readinessScore.map { min(100, max(0, $0)) }
    self.readinessRecommendation = readinessRecommendation
    self.nextActionKind = nextActionKind
    self.nextActionTitle = nextActionTitle.map { StringUtils.boundedText($0, limit: 160) }
    self.nextActionPriority = max(0, nextActionPriority)
    self.pressure = pressure
    self.staleEvidenceCount = max(0, staleEvidenceCount)
    self.proofDebtCount = max(0, proofDebtCount)
    self.proofDebtSummary = proofDebtSummary.map { StringUtils.boundedText($0, limit: 240) }
  }
}

struct ProductFactoryProofTarget: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var label: String
  var readinessScore: Int
  var debtSummary: String
  var nextActionTitle: String?
  var nextActionKind: ProductMarketFitNextActionKind?
  var nextActionPriority: Int
  var cohortID: String?
  var targetScenarioID: String?
  var targetPersonaID: String?
  var targetPersonaName: String?
  var requiredSimulationMode: ProductizationSimulationMode?

  var urgencyScore: Int {
    (nextActionPriority * 1_000) + readinessScore
  }

  var displayTitle: String {
    label
  }

  var displaySubtitle: String {
    var parts = ["score \(readinessScore)/100"]
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    } else if let requiredSimulationMode {
      parts.append("mode \(requiredSimulationMode.rawValue)")
    }
    return parts.joined(separator: ", ")
  }

  var displayDetail: String {
    var parts = ["Debt: \(debtSummary)"]
    if let nextActionTitle {
      parts.append("Next: \(nextActionTitle)")
    }
    if let targetScenarioID {
      parts.append("Scenario: \(targetScenarioID)")
    } else if let cohortID {
      parts.append("Cohort: \(cohortID)")
    }
    if targetScenarioID == nil, let targetPersonaName {
      parts.append("Persona: \(targetPersonaName)")
    }
    return parts.joined(separator: " ")
  }

  var auditSummary: String {
    var parts = ["\(experimentID): \(label)"]
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    } else if let cohortID {
      parts.append("cohort \(cohortID)")
    }
    parts.append("debt \(debtSummary)")
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 240)
  }

  init(
    experimentID: String,
    label: String,
    readinessScore: Int,
    debtSummary: String,
    nextAction: ProductMarketFitNextAction?
  ) {
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.label = ProductizationModelText.cleanedText(
      label,
      fallback: "close PMF proof debt",
      limit: 160
    )
    self.readinessScore = min(100, max(0, readinessScore))
    self.debtSummary = ProductizationModelText.cleanedText(
      debtSummary,
      fallback: "proof incomplete",
      limit: 240
    )
    self.nextActionTitle = nextAction?.title
    self.nextActionKind = nextAction?.kind
    self.nextActionPriority = nextAction?.priority ?? 0
    self.cohortID = nextAction?.cohortID
    self.targetScenarioID = nextAction?.targetScenarioID
    self.targetPersonaID = nextAction?.targetPersonaID
    self.targetPersonaName = nextAction?.targetPersonaName
    self.requiredSimulationMode = nextAction?.requiredSimulationMode
  }
}

enum ProductFactoryProofTargetAdvisor {
  static func targets(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductFactoryProofTarget] {
    ProductFactoryExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { experiment in
      target(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func target(
    for experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryProofTarget? {
    guard let readiness = evidenceIndex.currentPMFReadiness(for: experiment),
      !readiness.proofDebt.isClear
    else { return nil }
    let action = ProductMarketFitNextActionAdvisor.nextAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return ProductFactoryProofTarget(
      experimentID: experiment.id,
      label: label(readiness: readiness, action: action),
      readinessScore: Int(readiness.readinessScore.rounded()),
      debtSummary: readiness.proofDebt.summary,
      nextAction: action
    )
  }

  private static func label(
    readiness: ProductMarketFitReadiness,
    action: ProductMarketFitNextAction?
  ) -> String {
    if readiness.proofDebt.failedRunCount > 0 {
      return "repair failed evidence"
    }
    if action?.targetScenarioID != nil {
      if readiness.proofDebt.aiUserCurrentAlternativeDeficit > 0
        && action?.title.localizedCaseInsensitiveContains("alternative") == true
      {
        return "run targeted AI-user alternative proof"
      }
      return "run targeted AI-user persona proof"
    }
    if action?.requiredSimulationMode == .personaModel {
      return "add or enable runnable AI-user proof"
    }
    if readiness.proofDebt.completedRunDeficit > 0 || readiness.proofDebt.personaDeficit > 0 {
      return "broaden completed persona coverage"
    }
    if readiness.proofDebt.aiUserCurrentAlternativeDeficit > 0 {
      return "add AI-user current-alternative proof"
    }
    return "close remaining PMF proof debt"
  }
}

enum ProductFactoryExperimentRanker {
  static func rankedExperiments(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductExperiment] {
    let signals = Dictionary(
      uniqueKeysWithValues: experimentSignals(
        config: config,
        evidenceIndex: evidenceIndex
      ).map { ($0.experimentID, $0) }
    )
    return config.experiments.sorted { lhs, rhs in
      let lhsSignal = signals[lhs.id]
      let rhsSignal = signals[rhs.id]
      let lhsUrgency = lhsSignal?.urgencyScore ?? 0
      let rhsUrgency = rhsSignal?.urgencyScore ?? 0
      if lhsUrgency == rhsUrgency {
        if lhs.updatedAt == rhs.updatedAt { return lhs.title < rhs.title }
        return lhs.updatedAt > rhs.updatedAt
      }
      return lhsUrgency > rhsUrgency
    }
  }

  static func experimentSignals(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductFactoryExperimentSignal] {
    config.experiments.map {
      signal(for: $0, config: config, evidenceIndex: evidenceIndex)
    }
  }

  static func signal(
    for experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryExperimentSignal {
    let readiness = evidenceIndex.currentPMFReadiness(for: experiment)
    let nextAction = ProductMarketFitNextActionAdvisor.nextAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return ProductFactoryExperimentSignal(
      experimentID: experiment.id,
      readinessScore: readiness.map { Int($0.readinessScore.rounded()) },
      readinessRecommendation: readiness?.recommendation,
      nextActionKind: nextAction?.kind,
      nextActionTitle: nextAction?.title,
      nextActionPriority: nextAction?.priority ?? 0,
      pressure: pressure(for: experiment, readiness: readiness, nextAction: nextAction),
      staleEvidenceCount: evidenceIndex.staleSummaryCount(for: experiment),
      proofDebtCount: readiness?.proofDebt.blockingDebtCount ?? 0,
      proofDebtSummary: readiness?.proofDebt.isClear == false ? readiness?.proofDebt.summary : nil
    )
  }

  private static func pressure(
    for experiment: ProductExperiment,
    readiness: ProductMarketFitReadiness?,
    nextAction: ProductMarketFitNextAction?
  ) -> ProductFactoryPortfolioPressure {
    if nextAction?.kind == .repairFailures {
      return .repair
    }
    if let readiness {
      switch readiness.recommendation {
      case .promote: return .lift
      case .kill: return .cut
      case .pivot, .narrow: return .reshape
      case .gatherEvidence, .keepGoing: break
      }
    }
    switch nextAction?.kind {
    case .applyDecision:
      switch readiness?.recommendation {
      case .promote: return .lift
      case .kill: return .cut
      case .pivot, .narrow: return .reshape
      case .gatherEvidence, .keepGoing, nil: return .learn
      }
    case .runCohort, .rerunCohort:
      return .learn
    case .refineBet, .reviewDecision:
      return .reshape
    case .repairFailures:
      return .repair
    case nil:
      switch experiment.decision {
      case .promoted, .archived:
        return .wait
      case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
        return readiness == nil ? .learn : .wait
      }
    }
  }
}

enum ProductFactoryAutopilotStepKind: String, Equatable, Sendable {
  case applyDecision = "apply_decision"
  case runCohort = "run_cohort"
  case blocked = "blocked"
}

struct ProductFactoryAutopilotStep: Equatable, Sendable, Identifiable {
  var id: String {
    "\(experimentID):\(action.kind.rawValue):\(targetScenarioID ?? cohortID ?? "none")"
  }

  var experimentID: String
  var experimentTitle: String
  var kind: ProductFactoryAutopilotStepKind
  var action: ProductMarketFitNextAction
  var cohortReadiness: ProductMarketFitCohortRunReadiness?
  var canExecute: Bool
  var blockedReason: String?

  var cohortID: String? { action.cohortID }
  var targetScenarioID: String? { action.targetScenarioID }

  var title: String {
    switch kind {
    case .applyDecision:
      return "Apply PMF decision"
    case .runCohort:
      return action.kind == .rerunCohort ? "Rerun evidence cohort" : "Run evidence cohort"
    case .blocked:
      return action.title
    }
  }

  var detail: String {
    if let blockedReason {
      return "\(experimentTitle): \(blockedReason)"
    }
    if let cohortReadiness {
      let target = action.targetPersonaName.map { " targeting \($0)" } ?? ""
      return
        "\(experimentTitle): \(action.title)\(target) with \(cohortReadiness.enabledScenarioCount) enabled scenario(s)."
    }
    return "\(experimentTitle): \(action.detail)"
  }

  init(
    experiment: ProductExperiment,
    action: ProductMarketFitNextAction,
    cohortReadiness: ProductMarketFitCohortRunReadiness?,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) {
    self.experimentID = experiment.id
    self.experimentTitle = experiment.title
    self.action = action
    self.cohortReadiness = cohortReadiness
    switch action.kind {
    case .applyDecision:
      self.kind = .applyDecision
      self.canExecute = true
      self.blockedReason = nil
    case .runCohort, .rerunCohort:
      self.kind = .runCohort
      let modeBlockedReason = Self.simulationModeBlockedReason(
        for: action,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
      self.canExecute = cohortReadiness?.canRun == true && modeBlockedReason == nil
      self.blockedReason =
        cohortReadiness?.blockedReason
        ?? (cohortReadiness == nil ? "Suggested cohort is missing." : modeBlockedReason)
    case .repairFailures:
      self.kind = .blocked
      self.canExecute = false
      self.blockedReason = action.detail.isEmpty
        ? "Repair failed evidence runs before autopilot can continue."
        : action.detail
    case .refineBet:
      self.kind = .blocked
      self.canExecute = false
      self.blockedReason = "Refine the product bet before autopilot can run more evidence."
    case .reviewDecision:
      self.kind = .blocked
      self.canExecute = false
      self.blockedReason = "Review the decision path before autopilot changes state."
    }
  }

  private static func simulationModeBlockedReason(
    for action: ProductMarketFitNextAction,
    isPersonaModelAvailable: Bool
  ) -> String? {
    guard action.requiredSimulationMode == .personaModel, !isPersonaModelAvailable else {
      return nil
    }
    return "AI-user validation requires Foundation Models before this cohort can run."
  }
}

struct ProductFactoryAutopilotCyclePlan: Equatable, Sendable {
  var executableSteps: [ProductFactoryAutopilotStep]
  var blockedSteps: [ProductFactoryAutopilotStep]
  var maxSteps: Int
  var capped: Bool

  var canRun: Bool { !executableSteps.isEmpty }

  var nextBlockedStep: ProductFactoryAutopilotStep? {
    blockedSteps.first
  }

  var summary: String {
    if executableSteps.isEmpty {
      if let nextBlockedStep {
        return "No executable factory steps; next blocked action is \(nextBlockedStep.title)."
      }
      return "No product-factory action queued."
    }
    let cappedText = capped ? ", capped at \(maxSteps)" : ""
    return "\(executableSteps.count) executable factory step(s)\(cappedText)."
  }

  var queueSummary: String {
    if executableSteps.isEmpty {
      if let nextBlockedStep {
        return
          "Blocked: \(nextBlockedStep.experimentTitle): \(nextBlockedStep.title) - \(nextBlockedStep.detail)"
      }
      return "No product-factory action queued."
    }
    let queued = executableSteps
      .map { "\($0.experimentTitle): \($0.title)" }
      .joined(separator: " -> ")
    return capped ? "\(queued) -> plus more queued" : queued
  }

  init(
    executableSteps: [ProductFactoryAutopilotStep],
    blockedSteps: [ProductFactoryAutopilotStep],
    maxSteps: Int,
    capped: Bool
  ) {
    self.executableSteps = executableSteps
    self.blockedSteps = blockedSteps
    self.maxSteps = max(1, maxSteps)
    self.capped = capped
  }
}

enum ProductFactoryAutopilotCycleStopReason: Equatable, Sendable {
  case reachedStepLimit
  case noExecutableStep
  case repeatedStep(stepID: String, title: String)
  case executionFailed(stepID: String, title: String, message: String?)
}

struct ProductFactoryAutopilotStepResult: Equatable, Sendable {
  var message: String
  var evidenceRunIDs: [String]
  var completedEvidenceRunCount: Int
  var failedEvidenceRunCount: Int
  var skippedScenarioCount: Int

  init(
    message: String,
    evidenceRunIDs: [String] = [],
    completedEvidenceRunCount: Int = 0,
    failedEvidenceRunCount: Int = 0,
    skippedScenarioCount: Int = 0
  ) {
    self.message = ProductizationModelText.cleanedText(
      message,
      fallback: "Factory step completed.",
      limit: 1_200
    )
    self.evidenceRunIDs = ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
  }
}

struct ProductFactoryAutopilotCycleOutcome: Equatable, Sendable {
  var executedSteps: [ProductFactoryAutopilotStep]
  var messages: [String]
  var maxSteps: Int
  var stopReason: ProductFactoryAutopilotCycleStopReason
  var evidenceRunIDs: [String]
  var completedEvidenceRunCount: Int
  var failedEvidenceRunCount: Int
  var skippedScenarioCount: Int
  var startingProofDebtCount: Int?
  var endingProofDebtCount: Int?
  var startingProofDebtSummary: String?
  var endingProofDebtSummary: String?
  var decisionCandidateSummaries: [String]
  var evidenceTensionSummaries: [String]
  var proofTargetSummaries: [String]

  init(
    executedSteps: [ProductFactoryAutopilotStep],
    messages: [String],
    maxSteps: Int,
    stopReason: ProductFactoryAutopilotCycleStopReason,
    evidenceRunIDs: [String] = [],
    completedEvidenceRunCount: Int = 0,
    failedEvidenceRunCount: Int = 0,
    skippedScenarioCount: Int = 0,
    startingProofDebtCount: Int? = nil,
    endingProofDebtCount: Int? = nil,
    startingProofDebtSummary: String? = nil,
    endingProofDebtSummary: String? = nil,
    decisionCandidateSummaries: [String] = [],
    evidenceTensionSummaries: [String] = [],
    proofTargetSummaries: [String] = []
  ) {
    self.executedSteps = executedSteps
    self.messages = ProductizationModelText.cleanedList(messages, limit: 500)
    self.maxSteps = max(1, maxSteps)
    self.stopReason = stopReason
    self.evidenceRunIDs = ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
    self.startingProofDebtCount = startingProofDebtCount.map { max(0, $0) }
    self.endingProofDebtCount = endingProofDebtCount.map { max(0, $0) }
    self.startingProofDebtSummary = ProductizationModelText.optionalCleanedText(
      startingProofDebtSummary,
      limit: 500
    )
    self.endingProofDebtSummary = ProductizationModelText.optionalCleanedText(
      endingProofDebtSummary,
      limit: 500
    )
    self.decisionCandidateSummaries = ProductizationModelText.cleanedList(
      decisionCandidateSummaries,
      limit: 300
    )
    self.evidenceTensionSummaries = ProductizationModelText.cleanedList(
      evidenceTensionSummaries,
      limit: 300
    )
    self.proofTargetSummaries = ProductizationModelText.cleanedList(
      proofTargetSummaries,
      limit: 240
    )
  }

  var appliedDecisionCount: Int {
    executedSteps.filter { $0.action.kind == .applyDecision }.count
  }

  var promotedDecisionCount: Int {
    executedSteps.filter { $0.action.targetDecision == .promote }.count
  }

  var killedDecisionCount: Int {
    executedSteps.filter { $0.action.targetDecision == .kill }.count
  }

  var evidenceRunStepCount: Int {
    executedSteps.filter { $0.action.kind == .runCohort || $0.action.kind == .rerunCohort }.count
  }

  var proofDebtDelta: Int? {
    guard let startingProofDebtCount, let endingProofDebtCount else { return nil }
    return endingProofDebtCount - startingProofDebtCount
  }

  var userMessage: String {
    var parts = [
      executedSteps.isEmpty
        ? "Factory cycle ran no steps."
        : "Factory cycle ran \(executedSteps.count) step(s).",
    ]
    if let outcomeMessage {
      parts.append(outcomeMessage)
    }
    if !messages.isEmpty {
      parts.append(messages.joined(separator: " "))
    }
    if let decisionCandidateMessage {
      parts.append(decisionCandidateMessage)
    }
    if let evidenceTensionMessage {
      parts.append(evidenceTensionMessage)
    }
    if let proofTargetMessage {
      parts.append(proofTargetMessage)
    }
    if let proofDebtMessage {
      parts.append(proofDebtMessage)
    }
    parts.append(stopReasonMessage)
    return parts.joined(separator: " ")
  }

  var auditStopReason: ProductFactoryCycleAuditStopReason {
    switch stopReason {
    case .reachedStepLimit:
      return .reachedStepLimit
    case .noExecutableStep:
      return .noExecutableStep
    case .repeatedStep:
      return .repeatedStep
    case .executionFailed:
      return .executionFailed
    }
  }

  var stopDetail: String {
    stopReasonMessage
  }

  var stopStepID: String? {
    switch stopReason {
    case .repeatedStep(let stepID, _), .executionFailed(let stepID, _, _):
      return stepID
    case .reachedStepLimit, .noExecutableStep:
      return nil
    }
  }

  var stopStepTitle: String? {
    switch stopReason {
    case .repeatedStep(_, let title), .executionFailed(_, let title, _):
      return title
    case .reachedStepLimit, .noExecutableStep:
      return nil
    }
  }

  func audit(
    startedAt: Date,
    endedAt: Date = Date()
  ) -> ProductFactoryCycleAudit {
    let started = startedAt.timeIntervalSince1970
    let ended = endedAt.timeIntervalSince1970
    var experimentIDs: [String] = []
    for step in executedSteps where !experimentIDs.contains(step.experimentID) {
      experimentIDs.append(step.experimentID)
    }
    return ProductFactoryCycleAudit(
      id: "factory-cycle-\(Int(started))-\(Int(ended))-\(executedSteps.count)",
      startedAt: started,
      endedAt: ended,
      executedStepIDs: executedSteps.map(\.id),
      experimentIDs: experimentIDs,
      messages: messages,
      maxSteps: maxSteps,
      appliedDecisionCount: appliedDecisionCount,
      promotedDecisionCount: promotedDecisionCount,
      killedDecisionCount: killedDecisionCount,
      evidenceRunStepCount: evidenceRunStepCount,
      evidenceRunIDs: evidenceRunIDs,
      completedEvidenceRunCount: completedEvidenceRunCount,
      failedEvidenceRunCount: failedEvidenceRunCount,
      skippedScenarioCount: skippedScenarioCount,
      startingProofDebtCount: startingProofDebtCount,
      endingProofDebtCount: endingProofDebtCount,
      startingProofDebtSummary: startingProofDebtSummary,
      endingProofDebtSummary: endingProofDebtSummary,
      decisionCandidateSummaries: decisionCandidateSummaries,
      evidenceTensionSummaries: evidenceTensionSummaries,
      proofTargetSummaries: proofTargetSummaries,
      stopReason: auditStopReason,
      stopStepID: stopStepID,
      stopStepTitle: stopStepTitle,
      stopDetail: stopDetail,
      userMessage: userMessage
    )
  }

  private var outcomeMessage: String? {
    guard
      appliedDecisionCount > 0 || evidenceRunStepCount > 0 || hasEvidenceRunOutcomes
    else { return nil }
    let evidenceOutcome =
      hasEvidenceRunOutcomes
      ? ", evidence runs \(completedEvidenceRunCount) completed, \(failedEvidenceRunCount) needing review, \(skippedScenarioCount) skipped"
      : ""
    return
      "Cycle outcomes: \(appliedDecisionCount) PMF decision(s) applied (\(promotedDecisionCount) promote, \(killedDecisionCount) kill), \(evidenceRunStepCount) evidence step(s)\(evidenceOutcome)."
  }

  private var hasEvidenceRunOutcomes: Bool {
    !evidenceRunIDs.isEmpty || completedEvidenceRunCount > 0 || failedEvidenceRunCount > 0
      || skippedScenarioCount > 0
  }

  private var decisionCandidateMessage: String? {
    guard !decisionCandidateSummaries.isEmpty else { return nil }
    let candidates = decisionCandidateSummaries.prefix(3).joined(separator: " | ")
    return "Decision candidates: \(StringUtils.boundedText(candidates, limit: 420))."
  }

  private var evidenceTensionMessage: String? {
    guard !evidenceTensionSummaries.isEmpty else { return nil }
    let tensions = evidenceTensionSummaries.prefix(3).joined(separator: " | ")
    return "Evidence tensions: \(StringUtils.boundedText(tensions, limit: 420))."
  }

  private var proofTargetMessage: String? {
    guard !proofTargetSummaries.isEmpty else { return nil }
    let targets = proofTargetSummaries.prefix(3).joined(separator: " | ")
    return "Proof targets: \(StringUtils.boundedText(targets, limit: 360))."
  }

  private var proofDebtMessage: String? {
    guard let startingProofDebtCount, let endingProofDebtCount, let proofDebtDelta else {
      return nil
    }
    let direction: String
    if proofDebtDelta < 0 {
      direction = "improved by \(abs(proofDebtDelta))"
    } else if proofDebtDelta > 0 {
      direction = "worsened by \(proofDebtDelta)"
    } else {
      direction = "held steady"
    }
    return
      "Proof debt \(direction) (\(startingProofDebtCount) -> \(endingProofDebtCount))."
  }

  private var stopReasonMessage: String {
    switch stopReason {
    case .reachedStepLimit:
      return "Stopped after reaching the \(max(1, maxSteps))-step cycle limit."
    case .noExecutableStep:
      return "Stopped because no executable product-factory step remains."
    case .repeatedStep(_, let title):
      return "Stopped before repeating \(bounded(title, limit: 120))."
    case .executionFailed(_, let title, let message):
      if let message {
        let boundedMessage = bounded(message, limit: 240)
        if !boundedMessage.isEmpty {
          return "Stopped because \(bounded(title, limit: 120)) failed: \(boundedMessage)"
        }
      }
      return "Stopped because \(bounded(title, limit: 120)) did not report a result."
    }
  }

  private func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

enum ProductFactoryCycleFailureAdvisor {
  static func stepID(for action: ProductMarketFitNextAction) -> String {
    "\(action.experimentID):\(action.kind.rawValue):\(action.targetScenarioID ?? action.cohortID ?? "none")"
  }

  static func blockingAudit(
    forStepID stepID: String,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryCycleAudit? {
    guard let audit = recentExecutionFailureAudit(forStepID: stepID, config: config),
      !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
    else { return nil }
    return audit
  }

  private static func recentExecutionFailureAudit(
    forStepID stepID: String,
    config: ProductizationConfig
  ) -> ProductFactoryCycleAudit? {
    config.factoryCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first {
        $0.stopReason == .executionFailed
          && $0.stopStepID == stepID
      }
  }

  private static func hasCompletedEvidence(
    after audit: ProductFactoryCycleAudit,
    for experiment: ProductExperiment,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> Bool {
    evidenceIndex.summaries(for: experiment).contains {
      $0.isCompleted && $0.endedAt > audit.endedAt
    }
  }
}

enum ProductFactoryCycleLearningAdvisor {
  static func stalledProofDebtAudit(
    for action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryCycleAudit? {
    guard isBroadCohortAction(action) else { return nil }
    let broadStepIDs = broadCohortStepIDs(for: action)
    return config.factoryCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first { audit in
        guard audit.stopReason != .executionFailed,
          audit.experimentIDs.contains(experiment.id),
          audit.evidenceRunStepCount > 0,
          audit.completedEvidenceRunCount > 0,
          (audit.endingProofDebtCount ?? 0) > 0,
          audit.proofDebtDelta.map({ $0 >= 0 }) == true,
          !Set(audit.executedStepIDs).isDisjoint(with: broadStepIDs),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func stalledProofTargetAudit(
    for action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryCycleAudit? {
    guard isTargetedProofAction(action) else { return nil }
    let stepID = ProductFactoryCycleFailureAdvisor.stepID(for: action)
    let currentTarget = ProductFactoryProofTargetAdvisor.target(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return config.factoryCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first { audit in
        guard audit.stopReason != .executionFailed,
          audit.experimentIDs.contains(experiment.id),
          audit.evidenceRunStepCount > 0,
          audit.completedEvidenceRunCount > 0,
          (audit.endingProofDebtCount ?? 0) > 0,
          audit.proofDebtDelta.map({ $0 >= 0 }) == true,
          matchesExecutedStepID(stepID, audit: audit),
          !audit.proofTargetSummaries.isEmpty,
          matchesCurrentProofTarget(
            audit: audit,
            action: action,
            target: currentTarget
          ),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  private static func isBroadCohortAction(_ action: ProductMarketFitNextAction) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.targetScenarioID == nil
      && action.cohortID != nil
  }

  private static func isTargetedProofAction(_ action: ProductMarketFitNextAction) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.targetScenarioID != nil
      && action.requiredSimulationMode == .personaModel
  }

  private static func matchesExecutedStepID(
    _ stepID: String,
    audit: ProductFactoryCycleAudit
  ) -> Bool {
    audit.executedStepIDs.contains { executedStepID in
      executedStepID == stepID
        || stepID.hasPrefix(executedStepID)
        || executedStepID.hasPrefix(stepID)
    }
  }

  private static func matchesCurrentProofTarget(
    audit: ProductFactoryCycleAudit,
    action: ProductMarketFitNextAction,
    target: ProductFactoryProofTarget?
  ) -> Bool {
    audit.proofTargetSummaries.contains { summary in
      if let target {
        let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
        let personaMatches =
          action.targetPersonaName.map {
            summary.localizedCaseInsensitiveContains($0)
          } ?? true
        return summary.localizedCaseInsensitiveContains(target.label)
          && scenarioMatches
          && personaMatches
      }
      return action.targetScenarioID.map { summary.contains($0) } ?? false
    }
  }

  private static func broadCohortStepIDs(for action: ProductMarketFitNextAction) -> Set<String> {
    guard let cohortID = action.cohortID else { return [] }
    return [
      "\(action.experimentID):\(ProductMarketFitNextActionKind.runCohort.rawValue):\(cohortID)",
      "\(action.experimentID):\(ProductMarketFitNextActionKind.rerunCohort.rawValue):\(cohortID)",
    ]
  }

  private static func hasCompletedEvidence(
    after audit: ProductFactoryCycleAudit,
    for experiment: ProductExperiment,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> Bool {
    evidenceIndex.summaries(for: experiment).contains {
      $0.isCompleted && $0.endedAt > audit.endedAt
    }
  }
}

enum ProductFactoryAutopilotPlanner {
  static func cohortSimulationMode(
    isPersonaModelAvailable: Bool
  ) -> ProductizationSimulationMode {
    isPersonaModelAvailable ? .personaModel : .modelFree
  }

  static func steps(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [ProductFactoryAutopilotStep] {
    ProductFactoryExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: evidenceIndex
    ).compactMap { experiment in
      guard
        let action = ProductMarketFitNextActionAdvisor.nextAction(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex
        )
      else { return nil }
      let step = ProductFactoryAutopilotStep(
        experiment: experiment,
        action: action,
        cohortReadiness: ProductMarketFitNextActionAdvisor.cohortRunReadiness(
          for: action,
          experiment: experiment,
          config: config
        ),
        isPersonaModelAvailable: isPersonaModelAvailable
      )
      let failureGuarded = applyingRecentCycleFailureBlock(
        to: step,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
      return applyingRecentCycleLearningBlock(
        to: failureGuarded,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
  }

  static func nextExecutableStep(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> ProductFactoryAutopilotStep? {
    steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
      .first { $0.canExecute }
  }

  static func nextStep(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> ProductFactoryAutopilotStep? {
    nextExecutableStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
      ?? steps(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ).first
  }

  static func cyclePlan(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    maxSteps: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> ProductFactoryAutopilotCyclePlan {
    let limit = max(1, maxSteps)
    let allSteps = steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    let executableSteps = allSteps.filter(\.canExecute)
    let selectedExecutableSteps = Array(executableSteps.prefix(limit))
    return ProductFactoryAutopilotCyclePlan(
      executableSteps: selectedExecutableSteps,
      blockedSteps: allSteps.filter { !$0.canExecute },
      maxSteps: limit,
      capped: executableSteps.count > selectedExecutableSteps.count
    )
  }

  private static func applyingRecentCycleFailureBlock(
    to step: ProductFactoryAutopilotStep,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryAutopilotStep {
    guard step.canExecute,
      let audit = ProductFactoryCycleFailureAdvisor.blockingAudit(
        forStepID: step.id,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return step }
    var blocked = step
    blocked.canExecute = false
    blocked.blockedReason =
      "Recent factory cycle \(audit.id) failed while running this step; repair the generated app contract, runner, scenario, or cohort before retrying. \(audit.stopDetail)"
    return blocked
  }

  private static func applyingRecentCycleLearningBlock(
    to step: ProductFactoryAutopilotStep,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductFactoryAutopilotStep {
    guard step.canExecute,
      let audit = ProductFactoryCycleLearningAdvisor.stalledProofTargetAudit(
        for: step.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return step }
    var blocked = step
    blocked.canExecute = false
    blocked.blockedReason =
      "Recent factory cycle \(audit.id) already attempted this proof target without reducing proof debt; inspect the run evidence, change the scenario or current-alternative proof, or choose a different AI-user target before retrying."
    return blocked
  }
}

enum ProductMarketFitDecisionAdvisorError: LocalizedError, Equatable {
  case noProposal(String)

  var errorDescription: String? {
    switch self {
    case .noProposal(let experimentID):
      return "No PMF decision recommendation is available for product experiment \(experimentID)."
    }
  }
}

enum ProductMarketFitNextActionAdvisor {
  static func actions(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductMarketFitNextAction] {
    config.experiments.compactMap { experiment in
      nextAction(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.priority == rhs.priority { return lhs.experimentID < rhs.experimentID }
      return lhs.priority > rhs.priority
    }
  }

  static func nextAction(
    for experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitNextAction? {
    switch experiment.decision {
    case .archived, .promoted:
      return nil
    case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
      break
    }

    if let proposal = ProductMarketFitDecisionAdvisor.proposal(
      experimentID: experiment.id,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .applyDecision,
        title: "Apply PMF decision",
        detail:
          "Current evidence supports \(proposal.currentDecision.rawValue) -> \(proposal.update.decision.rawValue) using \(proposal.update.evidenceRunIDs.count) current run(s).",
        priority: 100,
        targetDecision: proposal.update.decision
      )
    }

    let currentSummaries = evidenceIndex.summaries(for: experiment)
    let staleCount = evidenceIndex.staleSummaryCount(for: experiment)
    let cohort = runnableCohort(for: experiment, config: config)
    if currentSummaries.isEmpty {
      guard let cohort else {
        return ProductMarketFitNextAction(
          experimentID: experiment.id,
          kind: .refineBet,
          title: "Define evidence cohort",
          detail:
            "No enabled scenario cohort is ready for this experiment; define an enabled cohort before the factory can gather PMF evidence.",
          priority: staleCount > 0 ? 96 : 91
        )
      }
      return applyingRecentCycleGuards(
        to: ProductMarketFitNextAction(
          experimentID: experiment.id,
          kind: staleCount > 0 ? .rerunCohort : .runCohort,
          title: staleCount > 0 ? "Rerun current evidence" : "Run productization cohort",
          detail: staleCount > 0
            ? "\(staleCount) stale run(s) exist for older commits; rerun cohort `\(cohort.id)` against the current experiment commit before deciding."
            : "No current-commit evidence exists yet; run cohort `\(cohort.id)` before changing the product decision.",
          priority: staleCount > 0 ? 95 : 90,
          cohortID: cohort.id
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    guard let readiness = evidenceIndex.currentPMFReadiness(for: experiment) else {
      return nil
    }
    if readiness.failedRunCount > readiness.completedRunCount {
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .repairFailures,
        title: "Repair evidence run failures",
        detail:
          "\(readiness.failedRunCount) of \(readiness.runCount) current run(s) failed; fix the generated app contract or runner before trusting PMF signals.",
        priority: 85
      )
    }
    if readiness.completedRunCount < 2 || readiness.distinctPersonaCount < 2 {
      return applyingRecentCycleGuards(
        to: ProductMarketFitNextAction(
          experimentID: experiment.id,
          kind: cohort == nil ? .refineBet : .runCohort,
          title: "Gather broader persona evidence",
          detail: cohort.map {
            "Current evidence has \(readiness.completedRunCount) completed run(s) across \(readiness.distinctPersonaCount) persona(s); run cohort `\($0.id)` to broaden evidence before deciding."
          }
            ?? "Current evidence has \(readiness.completedRunCount) completed run(s) across \(readiness.distinctPersonaCount) persona(s); define another enabled scenario or persona before deciding.",
          priority: 80,
          cohortID: cohort?.id
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    let missingAIUserTarget = missingAIUserPersonaTarget(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex,
      cohort: cohort
    )
    if readiness.aiUserDistinctPersonaCount < 2 && readiness.readinessScore >= 70 {
      return applyingRecentCycleGuards(
        to: aiUserBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingAIUserTarget,
          title: "Run AI-user validation cohort",
          decisionGate: "promotion",
          gateReason: "promotion requires at least 2",
          priority: 78,
          observedCount: readiness.aiUserDistinctPersonaCount,
          observedEvidenceLabel: "AI-user persona(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if readiness.aiUserDistinctPersonaCount < 2 && shouldRunAIUserRejectionCheck(readiness) {
      return applyingRecentCycleGuards(
        to: aiUserBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingAIUserTarget,
          title: "Run AI-user rejection check",
          decisionGate: "stopping the experiment",
          gateReason: "stopping a bet requires at least 2",
          priority: 82,
          observedCount: readiness.aiUserDistinctPersonaCount,
          observedEvidenceLabel: "AI-user persona(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    let currentAlternativePersonaIDs = aiUserCurrentAlternativePersonaIDs(
      for: experiment,
      evidenceIndex: evidenceIndex
    )
    let missingCurrentAlternativeTarget = missingAIUserPersonaTarget(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex,
      cohort: cohort,
      testedPersonaIDs: currentAlternativePersonaIDs
    )
    if readiness.aiUserCurrentAlternativePersonaCount < 2 && readiness.readinessScore >= 70 {
      return applyingRecentCycleGuards(
        to: aiUserBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingCurrentAlternativeTarget,
          title: "Run AI-user alternative challenge",
          decisionGate: "promotion",
          gateReason:
            "decisive PMF decisions require current-alternative proof from at least 2 AI-user personas",
          priority: 77,
          observedCount: readiness.aiUserCurrentAlternativePersonaCount,
          observedEvidenceLabel: "AI-user current-alternative persona(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if readiness.aiUserCurrentAlternativePersonaCount < 2
      && shouldRunAIUserRejectionCheck(readiness)
    {
      return applyingRecentCycleGuards(
        to: aiUserBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingCurrentAlternativeTarget,
          title: "Run AI-user alternative rejection check",
          decisionGate: "stopping the experiment",
          gateReason:
            "decisive PMF decisions require current-alternative proof from at least 2 AI-user personas",
          priority: 81,
          observedCount: readiness.aiUserCurrentAlternativePersonaCount,
          observedEvidenceLabel: "AI-user current-alternative persona(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let tension = ProductFactoryEvidenceTensionAdvisor.tension(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      let actionCohortID = tension.targetScenarioID == nil ? cohort?.id : tension.targetCohortID
      let canRunTarget = actionCohortID != nil
      let detail: String
      if let targetScenarioID = tension.targetScenarioID,
        let targetPersonaName = tension.targetPersonaName,
        let targetCohortID = tension.targetCohortID
      {
        detail =
          "\(tension.summary) Rerun rejecting AI-user scenario `\(targetScenarioID)` for \(targetPersonaName) in cohort `\(targetCohortID)` before lift/cut."
      } else if let targetPersonaName = tension.targetPersonaName {
        detail =
          "\(tension.summary) Add or enable a cohort scenario for \(targetPersonaName), then rerun it in AI-user mode before lift/cut."
      } else if let actionCohortID {
        detail =
          "\(tension.summary) Run cohort `\(actionCohortID)` in AI-user mode to compare the disagreeing personas before lift/cut."
      } else {
        detail =
          "\(tension.summary) Add an enabled AI-user scenario that directly compares the disagreeing evidence before lift/cut."
      }
      return applyingRecentCycleGuards(
        to: ProductMarketFitNextAction(
          experimentID: experiment.id,
          kind: canRunTarget ? .runCohort : .refineBet,
          title: "Resolve split PMF evidence",
          detail: detail,
          priority: tension.urgencyScore,
          cohortID: actionCohortID,
          requiredSimulationMode: .personaModel,
          targetPersonaID: tension.targetPersonaID,
          targetPersonaName: tension.targetPersonaName,
          targetScenarioID: tension.targetScenarioID
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    switch readiness.recommendation {
    case .narrow:
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .refineBet,
        title: "Narrow the product bet",
        detail:
          "Current PMF evidence points to missing capabilities or repeated objections; narrow the next prototype before more rollout work.",
        priority: 75
      )
    case .pivot:
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .refineBet,
        title: "Prepare a pivot",
        detail:
          "Users recognize the pain, but current product pull is weak; reshape the solution before more cohort runs.",
        priority: 74
      )
    case .kill:
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .reviewDecision,
        title: "Review kill decision",
        detail:
          "Current evidence is weak, but the existing experiment state blocks an automatic kill recommendation; inspect the decision path.",
        priority: 73
      )
    case .promote:
      return ProductMarketFitNextAction(
        experimentID: experiment.id,
        kind: .reviewDecision,
        title: "Review promotion path",
        detail:
          "Current evidence has promotion strength, but the existing experiment state blocks an automatic promote recommendation.",
        priority: 73
      )
    case .gatherEvidence, .keepGoing:
      return applyingRecentCycleGuards(
        to: ProductMarketFitNextAction(
          experimentID: experiment.id,
          kind: cohort == nil ? .refineBet : .runCohort,
          title: "Run another evidence cohort",
          detail: cohort.map {
            "Current PMF readiness is \(readiness.scoreLabel)/100; run cohort `\($0.id)` or add a scenario variant before changing the product decision."
          }
            ?? "Current PMF readiness is \(readiness.scoreLabel)/100; define another enabled scenario cohort before changing the product decision.",
          priority: 70,
          cohortID: cohort?.id
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
  }

  private static func shouldRunAIUserRejectionCheck(
    _ readiness: ProductMarketFitReadiness
  ) -> Bool {
    readiness.completedRunCount >= 2
      && (readiness.readinessScore <= 40
        || readiness.averageScore > 0 && readiness.averageScore <= 2.5
        || readiness.weakestVerdict == .rejected)
  }

  private static func aiUserBreadthAction(
    experiment: ProductExperiment,
    selectedCohort: ProductScenarioCohort?,
    target: AIUserPersonaTarget?,
    title: String,
    decisionGate: String,
    gateReason: String,
    priority: Int,
    observedCount: Int,
    observedEvidenceLabel: String
  ) -> ProductMarketFitNextAction {
    let executableCohortID = target?.executableCohortID
    let executableScenarioID = target?.executableScenarioID
    let canRunTarget = executableCohortID != nil && executableScenarioID != nil
    let guidance =
      target?.guidance(selectedCohort: selectedCohort, executableCohortID: executableCohortID)
      ?? " Target AI-user segment: add an enabled scenario for an untested segment."
    let detail: String
    if let executableCohortID, executableScenarioID != nil {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); run the targeted persona-model scenario in cohort `\(executableCohortID)` before \(decisionGate).\(guidance)"
    } else if let selectedCohort {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); cohort `\(selectedCohort.id)` does not cover a runnable AI-user target before \(decisionGate).\(guidance)"
    } else {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); define an enabled AI-user scenario cohort before \(decisionGate).\(guidance)"
    }
    return ProductMarketFitNextAction(
      experimentID: experiment.id,
      kind: canRunTarget ? .runCohort : .refineBet,
      title: title,
      detail: detail,
      priority: priority,
      cohortID: executableCohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target?.id,
      targetPersonaName: target?.name,
      targetScenarioID: executableScenarioID
    )
  }

  private struct AIUserPersonaTarget: Equatable, Sendable {
    var id: String
    var name: String
    var scenarioID: String?
    var executableCohortID: String?

    var executableScenarioID: String? {
      executableCohortID == nil ? nil : scenarioID
    }

    func guidance(
      selectedCohort: ProductScenarioCohort?,
      executableCohortID: String?
    ) -> String {
      if let scenarioID, let executableCohortID {
        return
          " Target AI-user segment: \(name) via scenario `\(scenarioID)` in cohort `\(executableCohortID)`."
      }
      if let scenarioID, let selectedCohort {
        return
          " Target AI-user segment: \(name); add scenario `\(scenarioID)` to cohort `\(selectedCohort.id)` or enable a cohort that includes it."
      }
      if let scenarioID {
        return " Target AI-user segment: \(name); enable a cohort that includes scenario `\(scenarioID)`."
      }
      return " Target AI-user segment: \(name); add an enabled scenario for this segment."
    }
  }

  private static func missingAIUserPersonaTarget(
    for experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    cohort: ProductScenarioCohort?,
    testedPersonaIDs explicitTestedPersonaIDs: Set<String>? = nil
  ) -> AIUserPersonaTarget? {
    let testedPersonaIDs = explicitTestedPersonaIDs ?? Set(
      evidenceIndex.summaries(for: experiment)
        .filter { $0.isCompleted && $0.mode == .personaModel }
        .map(\.personaID)
        .filter { !$0.isEmpty }
    )
    guard testedPersonaIDs.count < 2 else { return nil }
    let enabledScenarios = config.scenarios
      .filter { $0.experimentID == experiment.id && $0.enabled }
    let cohortScenarioIDs = Set(cohort?.scenarioIDs ?? [])
    let untestedCohortScenarios = enabledScenarios.filter { scenario in
      cohortScenarioIDs.contains(scenario.id) && !testedPersonaIDs.contains(scenario.segmentID)
    }
    if let scenario = untestedCohortScenarios.sorted(by: scenarioSort(config: config)).first {
      return AIUserPersonaTarget(
        id: scenario.segmentID,
        name: segmentName(for: scenario.segmentID, config: config),
        scenarioID: scenario.id,
        executableCohortID: cohort?.id
      )
    }

    let candidateSegmentIDs = targetSegmentIDs(for: experiment, config: config)
    guard let segmentID = candidateSegmentIDs.first(where: { segmentID in
      !testedPersonaIDs.contains(segmentID)
    }) else { return nil }
    let scenario = enabledScenarios.filter { scenario in
      scenario.segmentID == segmentID
    }
    .sorted(by: scenarioSort(config: config))
    .first
    return AIUserPersonaTarget(
      id: segmentID,
      name: segmentName(for: segmentID, config: config),
      scenarioID: scenario?.id,
      executableCohortID: executableCohortID(
        forScenarioID: scenario?.id,
        experiment: experiment,
        config: config
      )
    )
  }

  private static func aiUserCurrentAlternativePersonaIDs(
    for experiment: ProductExperiment,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> Set<String> {
    Set(
      evidenceIndex.summaries(for: experiment)
        .filter {
          $0.isCompleted
            && $0.mode == .personaModel
            && hasCurrentAlternativeProof($0)
        }
        .map(\.personaID)
        .filter { !$0.isEmpty }
    )
  }

  private static func hasCurrentAlternativeProof(
    _ summary: ProductizationEvidenceSummary
  ) -> Bool {
    let comparison = summary.currentAlternativeComparison
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !comparison.isEmpty else { return false }
    return !comparison.contains("did not address")
      && !comparison.contains("no current-alternative comparison")
      && !comparison.contains("no current alternative")
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String?,
    experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> String? {
    guard let scenarioID else { return nil }
    return config.scenarioCohorts
      .filter {
        $0.experimentID == experiment.id
          && $0.enabled
          && $0.scenarioIDs.contains(scenarioID)
      }
      .sorted {
        if $0.scenarioIDs.count == $1.scenarioIDs.count { return $0.title < $1.title }
        return $0.scenarioIDs.count < $1.scenarioIDs.count
      }
      .first?.id
  }

  private static func targetSegmentIDs(
    for experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> [String] {
    let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
    let painID = solution?.painID
    var segmentIDs: [String] = []
    if let solution {
      segmentIDs.append(contentsOf: solution.targetSegmentIDs)
    }
    segmentIDs.append(contentsOf: config.userSegments
      .filter { painID == nil || $0.painID == painID }
      .map(\.id))
    segmentIDs.append(contentsOf: config.scenarios
      .filter { $0.experimentID == experiment.id }
      .map(\.segmentID))
    return orderedUnique(segmentIDs)
  }

  private static func segmentName(for segmentID: String, config: ProductizationConfig) -> String {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }

  private static func scenarioSort(
    config: ProductizationConfig
  ) -> (ProductScenario, ProductScenario) -> Bool {
    { lhs, rhs in
      let lhsName = segmentName(for: lhs.segmentID, config: config)
      let rhsName = segmentName(for: rhs.segmentID, config: config)
      if lhsName == rhsName { return lhs.id < rhs.id }
      return lhsName < rhsName
    }
  }

  private static func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where !value.isEmpty && !seen.contains(value) {
      seen.insert(value)
      result.append(value)
    }
    return result
  }

  private static func applyingRecentCycleGuards(
    to action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitNextAction {
    let failureGuarded = applyingRecentCycleFailureGuard(
      to: action,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    guard failureGuarded.kind != .repairFailures else { return failureGuarded }
    return applyingRecentCycleLearningGuard(
      to: failureGuarded,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private static func applyingRecentCycleLearningGuard(
    to action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitNextAction {
    guard
      let audit = ProductFactoryCycleLearningAdvisor.stalledProofDebtAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return action }
    if let retargetedAction = stalledProofDebtRetargetAction(
      audit: audit,
      replacing: action,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return applyingRecentCycleFailureGuard(
        to: retargetedAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    return ProductMarketFitNextAction(
      experimentID: experiment.id,
      kind: .refineBet,
      title: "Retarget stalled proof debt",
      detail:
        "Recent factory cycle \(audit.id) ran broad evidence without reducing proof debt (\(audit.summary)); retarget the scenario cohort, persona, or current-alternative proof before rerunning broad evidence.",
      priority: min(98, max(action.priority + 1, 84))
    )
  }

  private static func stalledProofDebtRetargetAction(
    audit: ProductFactoryCycleAudit,
    replacing action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitNextAction? {
    guard let readiness = evidenceIndex.currentPMFReadiness(for: experiment),
      !readiness.proofDebt.isClear
    else { return nil }
    let selectedCohort = action.cohortID.flatMap { cohortID in
      config.scenarioCohorts.first {
        $0.id == cohortID && $0.experimentID == experiment.id
      }
    } ?? runnableCohort(for: experiment, config: config)
    if readiness.proofDebt.aiUserPersonaDeficit > 0 {
      return retargetedAIUserProofDebtAction(
        audit: audit,
        replacing: action,
        experiment: experiment,
        readiness: readiness,
        selectedCohort: selectedCohort,
        target: missingAIUserPersonaTarget(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex,
          cohort: selectedCohort
        ),
        title: "Retarget AI-user proof debt",
        proofNeed: "\(readiness.proofDebt.aiUserPersonaDeficit) AI-user persona(s)"
      )
    }
    if readiness.proofDebt.aiUserCurrentAlternativeDeficit > 0 {
      return retargetedAIUserProofDebtAction(
        audit: audit,
        replacing: action,
        experiment: experiment,
        readiness: readiness,
        selectedCohort: selectedCohort,
        target: missingAIUserPersonaTarget(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex,
          cohort: selectedCohort,
          testedPersonaIDs: aiUserCurrentAlternativePersonaIDs(
            for: experiment,
            evidenceIndex: evidenceIndex
          )
        ),
        title: "Retarget AI-user alternative proof",
        proofNeed:
          "\(readiness.proofDebt.aiUserCurrentAlternativeDeficit) AI-user current-alternative proof(s)"
      )
    }
    return nil
  }

  private static func retargetedAIUserProofDebtAction(
    audit: ProductFactoryCycleAudit,
    replacing action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    readiness: ProductMarketFitReadiness,
    selectedCohort: ProductScenarioCohort?,
    target: AIUserPersonaTarget?,
    title: String,
    proofNeed: String
  ) -> ProductMarketFitNextAction {
    let executableCohortID = target?.executableCohortID
    let executableScenarioID = target?.executableScenarioID
    let canRunTarget = executableCohortID != nil && executableScenarioID != nil
    let guidance =
      target?.guidance(selectedCohort: selectedCohort, executableCohortID: executableCohortID)
      ?? " Target AI-user segment: add an enabled scenario for an untested segment."
    let debtSummary = StringUtils.boundedText(readiness.proofDebt.summary, limit: 140)
    let targetName = target?.name ?? "the missing AI-user segment"
    let detail: String
    if canRunTarget {
      detail =
        "Recent factory cycle \(audit.id) ran broad evidence without reducing proof debt; run a targeted persona-model scenario for \(targetName) to pay down \(proofNeed). Remaining proof debt: \(debtSummary)."
    } else if let selectedCohort {
      let cohortTitle = StringUtils.boundedText(selectedCohort.title, limit: 80)
      detail =
        "Recent factory cycle \(audit.id) ran broad evidence without reducing proof debt; cohort \(cohortTitle) does not cover a runnable AI-user target for \(proofNeed). \(guidance) Remaining proof debt: \(debtSummary)."
    } else {
      detail =
        "Recent factory cycle \(audit.id) ran broad evidence without reducing proof debt; define an enabled AI-user scenario cohort for \(proofNeed).\(guidance) Remaining proof debt: \(debtSummary)."
    }
    return ProductMarketFitNextAction(
      experimentID: experiment.id,
      kind: canRunTarget ? .runCohort : .refineBet,
      title: title,
      detail: detail,
      priority: min(98, max(action.priority + 2, 86)),
      cohortID: executableCohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target?.id,
      targetPersonaName: target?.name,
      targetScenarioID: executableScenarioID
    )
  }

  private static func applyingRecentCycleFailureGuard(
    to action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitNextAction {
    guard action.kind == .runCohort || action.kind == .rerunCohort,
      let audit = ProductFactoryCycleFailureAdvisor.blockingAudit(
        forStepID: ProductFactoryCycleFailureAdvisor.stepID(for: action),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return action }
    return ProductMarketFitNextAction(
      experimentID: experiment.id,
      kind: .repairFailures,
      title: "Repair factory cycle failure",
      detail:
        "Recent factory cycle \(audit.id) failed while running the suggested cohort; repair the generated app contract, runner, scenario, or cohort before retrying. \(audit.stopDetail)",
      priority: min(99, max(action.priority + 1, 86))
    )
  }

  static func cohortRunReadiness(
    for action: ProductMarketFitNextAction,
    experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> ProductMarketFitCohortRunReadiness? {
    guard action.experimentID == experiment.id,
      let cohortID = action.cohortID,
      let cohort = config.scenarioCohorts.first(where: {
        $0.id == cohortID && $0.experimentID == experiment.id
      })
    else { return nil }
    let cohortScenarioIDs = Set(cohort.scenarioIDs)
    let enabledScenarios = config.scenarios.filter {
      $0.experimentID == experiment.id
        && $0.enabled
        && cohortScenarioIDs.contains($0.id)
    }
    let runnableScenarios = action.targetScenarioID.map { targetScenarioID in
      enabledScenarios.filter { $0.id == targetScenarioID }
    } ?? enabledScenarios
    let missingTargetCommitCount = runnableScenarios.filter {
      targetCommit(for: $0, experiment: experiment) == nil
    }.count
    return ProductMarketFitCohortRunReadiness(
      cohortID: cohort.id,
      cohortTitle: cohort.title,
      cohortEnabled: cohort.enabled,
      enabledScenarioCount: cohort.enabled ? runnableScenarios.count : 0,
      missingTargetCommitCount: cohort.enabled ? missingTargetCommitCount : 0,
      targetScenarioID: action.targetScenarioID
    )
  }

  private static func runnableCohort(
    for experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> ProductScenarioCohort? {
    let enabledScenarioIDs = Set(
      config.scenarios
        .filter { $0.experimentID == experiment.id && $0.enabled }
        .map(\.id)
    )
    guard !enabledScenarioIDs.isEmpty else { return nil }
    return config.scenarioCohorts
      .filter { cohort in
        cohort.experimentID == experiment.id
          && cohort.enabled
          && cohort.scenarioIDs.contains { enabledScenarioIDs.contains($0) }
      }
      .sorted { lhs, rhs in
        let lhsCoverage = lhs.scenarioIDs.filter { enabledScenarioIDs.contains($0) }.count
        let rhsCoverage = rhs.scenarioIDs.filter { enabledScenarioIDs.contains($0) }.count
        if lhsCoverage == rhsCoverage { return lhs.title < rhs.title }
        return lhsCoverage > rhsCoverage
      }
      .first
  }

  private static func targetCommit(
    for scenario: ProductScenario,
    experiment: ProductExperiment
  ) -> String? {
    let commit = scenario.targetCommitSha ?? experiment.currentSha ?? experiment.baseSha
    let trimmed = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}

enum ProductMarketFitDecisionAdvisor {
  static func proposals(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [ProductMarketFitDecisionProposal] {
    return config.experiments.compactMap { experiment in
      guard let readiness = evidenceIndex.currentPMFReadiness(for: experiment),
        let target = targetDecision(for: readiness, current: experiment.decision),
        target != experiment.decision,
        !ProductFactoryEvidenceTensionAdvisor.blocksAutomaticDecision(
          targetDecision: target,
          experiment: experiment,
          evidenceIndex: evidenceIndex
        )
      else { return nil }
      let summary = summary(for: readiness, target: target, experiment: experiment)
      do {
        try ProductizationDecisionTransitionValidator.validate(
          experimentID: experiment.id,
          from: experiment.decision,
          to: target,
          summary: summary
        )
      } catch {
        return nil
      }
      let update = ProductizationReflectDecisionUpdate(
        experimentID: experiment.id,
        decision: target,
        summary: summary,
        evidenceRunIDs: readiness.evidenceRunIDs,
        decidedBy: "PMF Decision Advisor"
      )
      return ProductMarketFitDecisionProposal(
        experimentID: experiment.id,
        currentDecision: experiment.decision,
        update: update,
        readiness: readiness
      )
    }
  }

  static func proposal(
    experimentID: String,
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> ProductMarketFitDecisionProposal? {
    proposals(config: config, evidenceIndex: evidenceIndex)
      .first { $0.experimentID == experimentID }
  }

  static func applyingRecommendedDecision(
    experimentID: String,
    to config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    now: Date = Date()
  ) throws -> ProductizationConfig {
    guard
      let proposal = proposal(
        experimentID: experimentID,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else {
      throw ProductMarketFitDecisionAdvisorError.noProposal(experimentID)
    }
    return try ProductizationReflectDecisionApplier.applying(
      [proposal.update],
      to: config,
      now: now
    )
  }

  private static func targetDecision(
    for readiness: ProductMarketFitReadiness,
    current: ProductExperimentDecision
  ) -> ProductExperimentDecision? {
    switch readiness.recommendation {
    case .promote:
      switch current {
      case .keepGoing, .narrow:
        return .promote
      case .notRun, .pivot, .kill, .promote, .archived, .promoted:
        return nil
      }
    case .kill:
      switch current {
      case .keepGoing, .narrow, .pivot:
        return .kill
      case .notRun, .kill, .promote, .archived, .promoted:
        return nil
      }
    case .pivot:
      switch current {
      case .keepGoing, .narrow:
        return .pivot
      case .notRun, .pivot, .kill, .promote, .archived, .promoted:
        return nil
      }
    case .narrow:
      switch current {
      case .keepGoing:
        return .narrow
      case .notRun, .narrow, .pivot, .kill, .promote, .archived, .promoted:
        return nil
      }
    case .keepGoing:
      switch current {
      case .notRun, .narrow, .pivot:
        return .keepGoing
      case .keepGoing, .kill, .promote, .archived, .promoted:
        return nil
      }
    case .gatherEvidence:
      return nil
    }
  }

  private static func summary(
    for readiness: ProductMarketFitReadiness,
    target: ProductExperimentDecision,
    experiment: ProductExperiment
  ) -> String {
    let evidence =
      readiness.evidenceRunIDs.isEmpty
      ? "no evidence runs"
      : "evidence \(readiness.evidenceRunIDs.prefix(4).joined(separator: ", "))"
    let rationale = readiness.rationale.prefix(3).joined(separator: " ")
    let proof =
      "\(readiness.aiUserCompletedRunCount) AI-user run(s) across \(readiness.aiUserDistinctPersonaCount) persona(s); current-alternative proof from \(readiness.aiUserCurrentAlternativePersonaCount) AI-user persona(s)."
    return StringUtils.boundedText(
      """
      PMF readiness \(readiness.scoreLabel)/100 recommends \(target.rawValue) for \(experiment.title): \(rationale) \(proof) Supporting \(evidence).
      """,
      limit: 1_000
    )
  }
}

enum ProductizationReflectDecisionApplier {
  static func applying(
    _ updates: [ProductizationReflectDecisionUpdate],
    to config: ProductizationConfig,
    now: Date = Date()
  ) throws -> ProductizationConfig {
    guard !updates.isEmpty else { return config }

    var next = config
    let timestamp = now.timeIntervalSince1970
    var decisionSequence = next.decisions.count

    for update in updates {
      guard
        let experimentIndex = next.experiments.firstIndex(where: { $0.id == update.experimentID })
      else {
        throw ProductizationDecisionTransitionError.unknownExperiment(update.experimentID)
      }

      let currentDecision = next.experiments[experimentIndex].decision
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: update.experimentID,
        from: currentDecision,
        to: update.decision,
        summary: update.summary
      )

      next.experiments[experimentIndex].decision = update.decision
      next.experiments[experimentIndex].evidenceSummary =
        update.summary.isEmpty
        ? next.experiments[experimentIndex].evidenceSummary
        : update.summary
      next.experiments[experimentIndex].updatedAt = timestamp

      decisionSequence += 1
      next.decisions.append(
        ProductDecision(
          id:
            "\(update.experimentID)-\(update.decision.rawValue)-\(Int(timestamp))-\(decisionSequence)",
          experimentID: update.experimentID,
          decision: update.decision,
          summary: update.summary,
          evidenceRunIDs: update.evidenceRunIDs,
          branchName: next.experiments[experimentIndex].branchName,
          beforeSha: next.experiments[experimentIndex].currentSha
            ?? next.experiments[experimentIndex].baseSha,
          afterSha: next.experiments[experimentIndex].currentSha
            ?? next.experiments[experimentIndex].baseSha,
          decidedAt: timestamp,
          decidedBy: update.decidedBy
        )
      )
    }

    return next
  }
}
