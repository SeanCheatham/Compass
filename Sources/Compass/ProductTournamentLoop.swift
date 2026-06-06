import Foundation

struct ProductTournamentReflectDecisionUpdate: Codable, Equatable, Sendable {
  var experimentID: String
  var decision: ProductTournamentExperimentDecision
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
    decision: ProductTournamentExperimentDecision,
    summary: String,
    evidenceRunIDs: [String] = [],
    decidedBy: String = "Reflect"
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.decision = decision
    self.summary = StringUtils.boundedText(summary, limit: 1_000)
    self.evidenceRunIDs =
      ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "evidence-run") }
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
    let decision = try container.decode(ProductTournamentExperimentDecision.self, forKey: .decision)
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

enum ProductTournamentDecisionTransitionError: LocalizedError, Equatable {
  case invalidTransition(
    experimentID: String,
    from: ProductTournamentExperimentDecision,
    to: ProductTournamentExperimentDecision
  )
  case missingSummary(experimentID: String, decision: ProductTournamentExperimentDecision)
  case unknownExperiment(String)

  var errorDescription: String? {
    switch self {
    case .invalidTransition(let experimentID, let from, let to):
      return
        "Reflect tried to move tournament experiment \(experimentID) from \(from.rawValue) to \(to.rawValue), which is not an allowed product tournament transition."
    case .missingSummary(let experimentID, let decision):
      return
        "Reflect tried to mark tournament experiment \(experimentID) as \(decision.rawValue) without a decision summary."
    case .unknownExperiment(let id):
      return "Reflect tried to update unknown tournament experiment \(id)."
    }
  }
}

enum ProductTournamentDecisionTransitionValidator {
  static func validate(
    experimentID: String,
    from current: ProductTournamentExperimentDecision,
    to proposed: ProductTournamentExperimentDecision,
    summary: String
  ) throws {
    if requiresSummary(proposed)
      && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      throw ProductTournamentDecisionTransitionError.missingSummary(
        experimentID: experimentID,
        decision: proposed
      )
    }

    guard allowedNextDecisions(from: current).contains(proposed) else {
      throw ProductTournamentDecisionTransitionError.invalidTransition(
        experimentID: experimentID,
        from: current,
        to: proposed
      )
    }
  }

  static func allowedNextDecisions(
    from current: ProductTournamentExperimentDecision
  ) -> Set<ProductTournamentExperimentDecision> {
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

  private static func requiresSummary(_ decision: ProductTournamentExperimentDecision) -> Bool {
    switch decision {
    case .kill, .promote, .archived, .promoted:
      return true
    case .notRun, .keepGoing, .narrow, .pivot:
      return false
    }
  }
}

struct ProductTournamentDecisionProposal: Equatable, Sendable {
  var experimentID: String
  var currentDecision: ProductTournamentExperimentDecision
  var update: ProductTournamentReflectDecisionUpdate
  var readiness: ProductTournamentReadiness
}

enum ProductTournamentNextActionKind: String, Equatable, Sendable {
  case applyDecision = "apply_decision"
  case applyRoundTransition = "apply_round_transition"
  case prepareWorktree = "prepare_worktree"
  case runPlanProof = "run_plan_proof"
  case runCohort = "run_cohort"
  case rerunCohort = "rerun_cohort"
  case repairFailures = "repair_failures"
  case refineContender = "refine_contender"
  case reviewDecision = "review_decision"
}

enum TournamentAutomationPortfolioPressure: String, Equatable, Sendable {
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

struct TournamentAutomationDecisionCandidate: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var currentDecision: ProductTournamentExperimentDecision
  var targetDecision: ProductTournamentExperimentDecision
  var readinessScore: Int
  var pressure: TournamentAutomationPortfolioPressure
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

  init(proposal: ProductTournamentDecisionProposal) {
    self.experimentID = ProductTournamentModelText.identifier(
      proposal.experimentID,
      fallback: "experiment"
    )
    self.currentDecision = proposal.currentDecision
    self.targetDecision = proposal.update.decision
    self.readinessScore = Int(proposal.readiness.readinessScore.rounded())
    self.pressure = TournamentAutomationDecisionCandidateAdvisor.pressure(
      for: proposal.update.decision
    )
    self.evidenceRunIDs = ProductTournamentModelText.cleanedList(
      proposal.update.evidenceRunIDs,
      limit: 160
    )
    self.summary = ProductTournamentModelText.cleanedText(
      proposal.update.summary,
      fallback: "Tournament decision candidate is ready.",
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

enum TournamentAutomationDecisionCandidateAdvisor {
  static func candidates(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationDecisionCandidate] {
    ProductTournamentDecisionAdvisor.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .map(TournamentAutomationDecisionCandidate.init(proposal:))
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func pressure(
    for decision: ProductTournamentExperimentDecision
  ) -> TournamentAutomationPortfolioPressure {
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

struct TournamentAutomationEvidenceTension: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var label: String
  var readinessScore: Int
  var strongestVerdict: ProductTournamentEvidenceVerdict
  var weakestVerdict: ProductTournamentEvidenceVerdict
  var positiveEvidenceRunIDs: [String]
  var negativeEvidenceRunIDs: [String]
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetCohortID: String?
  var targetDecision: ProductTournamentExperimentDecision?
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
    if let targetDecision {
      parts.append("decision \(targetDecision.rawValue)")
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
    var parts = [
      "\(experimentID): \(label)",
      "score \(readinessScore)/100",
      "\(strongestVerdict.rawValue) vs \(weakestVerdict.rawValue)",
    ]
    if let targetDecision {
      parts.append("target_decision \(targetDecision.rawValue)")
    }
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    }
    if let targetCohortID {
      parts.append("cohort \(targetCohortID)")
    }
    parts.append("evidence \(evidenceRunIDs.prefix(6).joined(separator: ", "))")
    parts.append(summary)
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 360)
  }

  init(
    experimentID: String,
    label: String = "resolve split tournament evidence",
    readinessScore: Int,
    strongestVerdict: ProductTournamentEvidenceVerdict,
    weakestVerdict: ProductTournamentEvidenceVerdict,
    positiveEvidenceRunIDs: [String],
    negativeEvidenceRunIDs: [String],
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetCohortID: String? = nil,
    targetDecision: ProductTournamentExperimentDecision? = nil,
    summary: String
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.label = ProductTournamentModelText.cleanedText(
      label,
      fallback: "resolve split tournament evidence",
      limit: 120
    )
    self.readinessScore = min(100, max(0, readinessScore))
    self.strongestVerdict = strongestVerdict
    self.weakestVerdict = weakestVerdict
    self.positiveEvidenceRunIDs = ProductTournamentModelText.cleanedList(
      positiveEvidenceRunIDs,
      limit: 96
    )
    self.negativeEvidenceRunIDs = ProductTournamentModelText.cleanedList(
      negativeEvidenceRunIDs,
      limit: 96
    )
    self.targetPersonaID = ProductTournamentModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductTournamentModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetCohortID = ProductTournamentModelText.optionalIdentifier(
      targetCohortID,
      fallback: "cohort"
    )
    self.targetDecision = targetDecision
    self.summary = ProductTournamentModelText.cleanedText(
      summary,
      fallback:
        "Current tournament evidence contains both pull and rejection; resolve the split before lift/cut decisions.",
      limit: 1_000
    )
  }
}

enum TournamentAutomationEvidenceTensionAdvisor {
  static func tensions(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationEvidenceTension] {
    config.tournamentExperiments.compactMap { experiment in
      tension(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func tension(
    for experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationEvidenceTension? {
    tension(for: experiment, config: nil, evidenceIndex: evidenceIndex)
  }

  static func tension(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationEvidenceTension? {
    tension(for: experiment, config: Optional(config), evidenceIndex: evidenceIndex)
  }

  private static func tension(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig?,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationEvidenceTension? {
    guard let readiness = evidenceIndex.currentTournamentReadiness(for: experiment) else {
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
      "Current tournament evidence is split: \(positive.count) pull signal(s) and \(negative.count) rejection signal(s) on the current commit. Run a targeted persona-model comparison or narrow the scenario before applying lift/cut decisions."
    let target = config.flatMap {
      tensionTarget(for: negative, experiment: experiment, config: $0)
    }
    return TournamentAutomationEvidenceTension(
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
      targetDecision: targetDecision(for: readiness.recommendation),
      summary: summary
    )
  }

  static func blocksAutomaticDecision(
    targetDecision: ProductTournamentExperimentDecision,
    experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> Bool {
    guard targetDecision == .promote || targetDecision == .kill else { return false }
    return tension(for: experiment, evidenceIndex: evidenceIndex) != nil
  }

  private static func isPositive(_ verdict: ProductTournamentEvidenceVerdict) -> Bool {
    verdict == .strongPull || verdict == .promising
  }

  private static func isNegative(_ verdict: ProductTournamentEvidenceVerdict) -> Bool {
    verdict == .weak || verdict == .rejected
  }

  private static func targetDecision(
    for recommendation: ProductTournamentReadinessRecommendation
  ) -> ProductTournamentExperimentDecision? {
    switch recommendation {
    case .promote:
      return .promote
    case .kill:
      return .kill
    case .gatherEvidence, .keepGoing, .narrow, .pivot:
      return nil
    }
  }

  private struct EvidenceTensionTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
  }

  private static func tensionTarget(
    for negative: [ProductTournamentEvidenceSummary],
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> EvidenceTensionTarget? {
    for summary in negative {
      let scenarioID = summary.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !scenarioID.isEmpty,
        let scenario = config.scenarios.first(where: {
          $0.id == scenarioID && $0.experimentID == experiment.id
        })
      else { continue }
      let personaID =
        summary.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    guard
      let summary = negative.first(where: {
        !$0.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else { return nil }
    return EvidenceTensionTarget(
      personaID: summary.personaID,
      personaName: segmentName(for: summary.personaID, config: config),
      scenarioID: nil,
      cohortID: nil
    )
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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

  private static func segmentName(for segmentID: String, config: ProductTournamentConfig) -> String
  {
    let trimmed = segmentID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return segmentID }
    let name = config.userSegments.first { $0.id == trimmed }?.name ?? trimmed
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? trimmed : cleaned
  }
}

struct ProductTournamentNextAction: Equatable, Sendable {
  var experimentID: String
  var kind: ProductTournamentNextActionKind
  var title: String
  var detail: String
  var priority: Int
  var tournamentID: String?
  var roundID: String?
  var contenderID: String?
  var cohortID: String?
  var requiredSimulationMode: ProductTournamentSimulationMode?
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetDecision: ProductTournamentExperimentDecision?

  init(
    experimentID: String,
    kind: ProductTournamentNextActionKind,
    title: String,
    detail: String,
    priority: Int,
    tournamentID: String? = nil,
    roundID: String? = nil,
    contenderID: String? = nil,
    cohortID: String? = nil,
    requiredSimulationMode: ProductTournamentSimulationMode? = nil,
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.kind = kind
    self.title = StringUtils.boundedText(title, limit: 160)
    self.detail = StringUtils.boundedText(detail, limit: 500)
    self.priority = max(0, priority)
    self.tournamentID = ProductTournamentModelText.optionalIdentifier(
      tournamentID,
      fallback: "tournament"
    )
    self.roundID = ProductTournamentModelText.optionalIdentifier(roundID, fallback: "round")
    self.contenderID = ProductTournamentModelText.optionalIdentifier(
      contenderID,
      fallback: "contender"
    )
    self.cohortID = ProductTournamentModelText.optionalIdentifier(cohortID, fallback: "cohort")
    self.requiredSimulationMode = requiredSimulationMode
    self.targetPersonaID = ProductTournamentModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductTournamentModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetDecision = targetDecision
  }
}

struct ProductTournamentCohortRunReadiness: Equatable, Sendable {
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
    self.cohortID = ProductTournamentModelText.identifier(cohortID, fallback: "cohort")
    self.cohortTitle = ProductTournamentModelText.cleanedText(
      cohortTitle,
      fallback: "Product scenario cohort",
      limit: 180
    )
    self.cohortEnabled = cohortEnabled
    self.enabledScenarioCount = max(0, enabledScenarioCount)
    self.missingTargetCommitCount = max(0, missingTargetCommitCount)
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
  }
}

struct TournamentAutomationExperimentSignal: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var readinessScore: Int?
  var readinessRecommendation: ProductTournamentReadinessRecommendation?
  var nextActionKind: ProductTournamentNextActionKind?
  var nextActionTitle: String?
  var nextActionPriority: Int
  var targetDecision: ProductTournamentExperimentDecision?
  var pressure: TournamentAutomationPortfolioPressure
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

  var readinessLabel: String {
    guard let readinessScore else { return "No current tournament evidence" }
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
    readinessRecommendation: ProductTournamentReadinessRecommendation?,
    nextActionKind: ProductTournamentNextActionKind?,
    nextActionTitle: String?,
    nextActionPriority: Int,
    targetDecision: ProductTournamentExperimentDecision? = nil,
    pressure: TournamentAutomationPortfolioPressure,
    staleEvidenceCount: Int,
    proofDebtCount: Int = 0,
    proofDebtSummary: String? = nil
  ) {
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.readinessScore = readinessScore.map { min(100, max(0, $0)) }
    self.readinessRecommendation = readinessRecommendation
    self.nextActionKind = nextActionKind
    self.nextActionTitle = nextActionTitle.map { StringUtils.boundedText($0, limit: 160) }
    self.nextActionPriority = max(0, nextActionPriority)
    self.targetDecision = targetDecision
    self.pressure = pressure
    self.staleEvidenceCount = max(0, staleEvidenceCount)
    self.proofDebtCount = max(0, proofDebtCount)
    self.proofDebtSummary = proofDebtSummary.map { StringUtils.boundedText($0, limit: 240) }
  }
}

struct TournamentAutomationRationaleSignal: Equatable, Sendable, Identifiable {
  var id: String {
    "\(experimentID):\(targetDecision?.rawValue ?? "none"):\(rationale)"
  }

  var experimentID: String
  var rationale: String
  var count: Int
  var runIDs: [String]
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetCohortID: String?
  var targetDecision: ProductTournamentExperimentDecision?
  var summary: String

  var urgencyScore: Int {
    76 + min(12, max(0, count - 2) * 3)
  }

  var auditSummary: String {
    var parts = [
      "\(experimentID): resolve simulated-user rationale signal",
      "count \(count)",
    ]
    if !runIDs.isEmpty {
      parts.append("runs \(runIDs.prefix(4).joined(separator: ", "))")
    }
    if let targetDecision {
      parts.append("target_decision \(targetDecision.rawValue)")
    }
    parts.append(rationale)
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    }
    if let targetCohortID {
      parts.append("cohort \(targetCohortID)")
    }
    parts.append(summary)
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 360)
  }

  init(
    experimentID: String,
    rationale: String,
    count: Int,
    runIDs: [String],
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetCohortID: String? = nil,
    targetDecision: ProductTournamentExperimentDecision? = nil,
    summary: String
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.rationale = ProductTournamentModelText.cleanedText(
      rationale,
      fallback: "Repeated simulated-user rationale needs tournament experience proof.",
      limit: 260
    )
    self.count = max(0, count)
    self.runIDs = ProductTournamentModelText.cleanedList(runIDs, limit: 96)
    self.targetPersonaID = ProductTournamentModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductTournamentModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetCohortID = ProductTournamentModelText.optionalIdentifier(
      targetCohortID,
      fallback: "cohort"
    )
    self.targetDecision = targetDecision
    self.summary = ProductTournamentModelText.cleanedText(
      summary,
      fallback:
        "Repeated simulated-user rationale points to a tournament proof gap; resolve it before lift/cut decisions.",
      limit: 1_000
    )
  }
}

struct TournamentAutomationTargetedProofOutcomeSignal: Equatable, Sendable, Identifiable {
  var id: String {
    [
      experimentID,
      targetDecision.rawValue,
      outcome.rawValue,
      recommendedDecision?.rawValue ?? "none",
      runIDs.joined(separator: "-"),
    ].joined(separator: ":")
  }

  var experimentID: String
  var targetDecision: ProductTournamentExperimentDecision
  var outcome: ProductTournamentEvidenceDecisionIntentOutcome
  var recommendedDecision: ProductTournamentExperimentDecision?
  var actionKind: ProductTournamentNextActionKind
  var title: String
  var priority: Int
  var count: Int
  var runIDs: [String]
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetCohortID: String?
  var requiredSimulationMode: ProductTournamentSimulationMode?
  var summary: String

  var urgencyScore: Int {
    priority * 1_000 + count
  }

  var displaySubtitle: String {
    var parts = [
      "target \(targetDecision.rawValue)",
      outcome.rawValue,
      "\(count)x",
    ]
    if let recommendedDecision {
      parts.append("next \(recommendedDecision.rawValue)")
    }
    if let targetPersonaName {
      parts.append("persona \(targetPersonaName)")
    }
    return parts.joined(separator: ", ")
  }

  var displayDetail: String {
    var parts = [summary]
    if !runIDs.isEmpty {
      parts.append("Runs: \(runIDs.prefix(4).joined(separator: ", ")).")
    }
    if let targetScenarioID {
      parts.append("Scenario: \(targetScenarioID).")
    } else if let targetPersonaName {
      parts.append("Persona: \(targetPersonaName).")
    }
    return parts.joined(separator: " ")
  }

  var auditSummary: String {
    var parts = [
      "\(experimentID): targeted tournament proof outcome",
      "target_decision \(targetDecision.rawValue)",
      "outcome \(outcome.rawValue)",
      "count \(count)",
      "action \(actionKind.rawValue)",
    ]
    if let recommendedDecision {
      parts.append("recommended_decision \(recommendedDecision.rawValue)")
    }
    if !runIDs.isEmpty {
      parts.append("runs \(runIDs.prefix(4).joined(separator: ", "))")
    }
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    }
    if let targetCohortID {
      parts.append("cohort \(targetCohortID)")
    }
    parts.append(summary)
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 420)
  }

  init(
    experimentID: String,
    targetDecision: ProductTournamentExperimentDecision,
    outcome: ProductTournamentEvidenceDecisionIntentOutcome,
    recommendedDecision: ProductTournamentExperimentDecision?,
    actionKind: ProductTournamentNextActionKind,
    title: String,
    priority: Int,
    count: Int,
    runIDs: [String],
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetCohortID: String? = nil,
    requiredSimulationMode: ProductTournamentSimulationMode? = nil,
    summary: String
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.targetDecision = targetDecision
    self.outcome = outcome
    self.recommendedDecision = recommendedDecision
    self.actionKind = actionKind
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Resolve targeted tournament proof outcome",
      limit: 160
    )
    self.priority = max(0, priority)
    self.count = max(0, count)
    self.runIDs = ProductTournamentModelText.cleanedList(runIDs, limit: 96)
    self.targetPersonaID = ProductTournamentModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductTournamentModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetCohortID = ProductTournamentModelText.optionalIdentifier(
      targetCohortID,
      fallback: "cohort"
    )
    self.requiredSimulationMode = requiredSimulationMode
    self.summary = ProductTournamentModelText.cleanedText(
      summary,
      fallback:
        "A targeted tournament proof answered the requested decision; update the tournament automation queue before rerunning the same proof.",
      limit: 1_000
    )
  }
}

enum TournamentAutomationTargetedProofOutcomeAdvisor {
  static func signals(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationTargetedProofOutcomeSignal] {
    config.tournamentExperiments.compactMap { experiment in
      signal(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func signal(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationTargetedProofOutcomeSignal? {
    let summaries = evidenceIndex.summaries(for: experiment).filter(\.isCompleted)
    guard !summaries.isEmpty else { return nil }
    let readiness = evidenceIndex.currentTournamentReadiness(for: experiment)
    let grouped = Dictionary(
      grouping: summaries.compactMap(OutcomeSource.init),
      by: { "\($0.intent.targetDecision.rawValue)|\($0.evaluation.outcome.rawValue)" }
    )
    return grouped.compactMap { _, sources in
      signal(
        for: sources,
        experiment: experiment,
        config: config,
        readiness: readiness
      )
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.id < rhs.id }
      return lhs.urgencyScore > rhs.urgencyScore
    }
    .first
  }

  private struct OutcomeSource: Equatable, Sendable {
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

  private struct OutcomeTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
  }

  private static func signal(
    for sources: [OutcomeSource],
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    readiness: ProductTournamentReadiness?
  ) -> TournamentAutomationTargetedProofOutcomeSignal? {
    guard let first = sources.first else { return nil }
    let sortedSources = sources.sorted { lhs, rhs in
      if lhs.summary.endedAt == rhs.summary.endedAt {
        return lhs.summary.runID < rhs.summary.runID
      }
      return lhs.summary.endedAt > rhs.summary.endedAt
    }
    let targetDecision = first.intent.targetDecision
    let outcome = first.evaluation.outcome
    let target = target(for: sortedSources.map(\.summary), experiment: experiment, config: config)
    let runIDs = sortedSources.map(\.summary.runID)
    let count = sources.count

    switch outcome {
    case .contradictsTarget:
      return contradictedSignal(
        experiment: experiment,
        targetDecision: targetDecision,
        target: target,
        count: count,
        runIDs: runIDs
      )
    case .supportsTarget:
      return supportedSignal(
        experiment: experiment,
        targetDecision: targetDecision,
        readiness: readiness,
        target: target,
        count: count,
        runIDs: runIDs
      )
    case .inconclusive:
      guard count >= 2 else { return nil }
      return inconclusiveSignal(
        experiment: experiment,
        targetDecision: targetDecision,
        target: target,
        count: count,
        runIDs: runIDs
      )
    }
  }

  private static func contradictedSignal(
    experiment: ProductTournamentExperiment,
    targetDecision: ProductTournamentExperimentDecision,
    target: OutcomeTarget?,
    count: Int,
    runIDs: [String]
  ) -> TournamentAutomationTargetedProofOutcomeSignal {
    switch targetDecision {
    case .promote, .promoted:
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .contradictsTarget,
        recommendedDecision: allowedDecision(.narrow, current: experiment.decision),
        actionKind: .refineContender,
        title: "Revise contradicted promotion proof",
        priority: 89,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        requiredSimulationMode: .personaModel,
        summary:
          "Targeted promotion proof contradicted promotion in \(count) run(s); narrow the contender or revise the product implementation before asking for another lift proof."
      )
    case .kill, .archived:
      let canRun = target?.scenarioID != nil && target?.cohortID != nil
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .contradictsTarget,
        recommendedDecision: allowedDecision(.promote, current: experiment.decision),
        actionKind: canRun ? .runCohort : .refineContender,
        title: "Recheck contradicted stop proof",
        priority: 88,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        requiredSimulationMode: .personaModel,
        summary:
          "Targeted stop proof contradicted killing the contender in \(count) run(s); run a lift-oriented persona-model proof or revise the scenario before cutting."
      )
    case .narrow, .pivot:
      let canRun = target?.scenarioID != nil && target?.cohortID != nil
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .contradictsTarget,
        recommendedDecision: allowedDecision(.promote, current: experiment.decision),
        actionKind: canRun ? .runCohort : .refineContender,
        title: "Recheck contradicted reshape proof",
        priority: 84,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        requiredSimulationMode: .personaModel,
        summary:
          "Targeted reshape proof was contradicted in \(count) run(s); validate whether the current product shape deserves lift instead of another reshape."
      )
    case .keepGoing, .notRun:
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .contradictsTarget,
        recommendedDecision: allowedDecision(.narrow, current: experiment.decision),
        actionKind: .refineContender,
        title: "Resolve contradicted learning proof",
        priority: 82,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        requiredSimulationMode: .personaModel,
        summary:
          "The targeted learning proof contradicted continuing as-is; revise the contender before spending another cohort on the same uncertainty."
      )
    }
  }

  private static func supportedSignal(
    experiment: ProductTournamentExperiment,
    targetDecision: ProductTournamentExperimentDecision,
    readiness: ProductTournamentReadiness?,
    target: OutcomeTarget?,
    count: Int,
    runIDs: [String]
  ) -> TournamentAutomationTargetedProofOutcomeSignal? {
    switch targetDecision {
    case .promote, .promoted:
      guard readiness?.proofDebt.isClear == true else { return nil }
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .supportsTarget,
        recommendedDecision: allowedDecision(.promote, current: experiment.decision),
        actionKind: .reviewDecision,
        title: "Review supported promotion proof",
        priority: 84,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        summary:
          "Targeted promotion proof supported lift in \(count) run(s), but the formal tournament decision advisor did not apply it automatically; review transition state and evidence."
      )
    case .kill, .archived:
      guard readiness?.proofDebt.isClear == true else { return nil }
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .supportsTarget,
        recommendedDecision: allowedDecision(.kill, current: experiment.decision),
        actionKind: .reviewDecision,
        title: "Review supported kill proof",
        priority: 86,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        summary:
          "Targeted stop proof supported killing the contender in \(count) run(s), but the formal tournament decision advisor did not apply it automatically; review transition state and evidence."
      )
    case .narrow, .pivot:
      return TournamentAutomationTargetedProofOutcomeSignal(
        experimentID: experiment.id,
        targetDecision: targetDecision,
        outcome: .supportsTarget,
        recommendedDecision: allowedDecision(targetDecision, current: experiment.decision),
        actionKind: .refineContender,
        title: targetDecision == .pivot
          ? "Apply supported pivot proof" : "Apply supported narrow proof",
        priority: 83,
        count: count,
        runIDs: runIDs,
        targetPersonaID: target?.personaID,
        targetPersonaName: target?.personaName,
        targetScenarioID: target?.scenarioID,
        targetCohortID: target?.cohortID,
        summary:
          "Targeted \(targetDecision.rawValue) proof supported reshaping this contender in \(count) run(s); revise the product implementation and scenario before more lift/cut evidence."
      )
    case .keepGoing, .notRun:
      return nil
    }
  }

  private static func inconclusiveSignal(
    experiment: ProductTournamentExperiment,
    targetDecision: ProductTournamentExperimentDecision,
    target: OutcomeTarget?,
    count: Int,
    runIDs: [String]
  ) -> TournamentAutomationTargetedProofOutcomeSignal {
    let canRun = target?.scenarioID != nil && target?.cohortID != nil
    return TournamentAutomationTargetedProofOutcomeSignal(
      experimentID: experiment.id,
      targetDecision: targetDecision,
      outcome: .inconclusive,
      recommendedDecision: targetDecision,
      actionKind: canRun ? .rerunCohort : .refineContender,
      title: "Retarget inconclusive tournament proof",
      priority: 76,
      count: count,
      runIDs: runIDs,
      targetPersonaID: target?.personaID,
      targetPersonaName: target?.personaName,
      targetScenarioID: target?.scenarioID,
      targetCohortID: target?.cohortID,
      requiredSimulationMode: .personaModel,
      summary:
        "\(count) targeted \(targetDecision.rawValue) proof run(s) were inconclusive; retarget the scenario or rerun a sharper persona-model proof before deciding."
    )
  }

  private static func target(
    for summaries: [ProductTournamentEvidenceSummary],
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> OutcomeTarget? {
    for summary in summaries {
      let scenarioID = summary.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !scenarioID.isEmpty,
        let scenario = config.scenarios.first(where: {
          $0.id == scenarioID && $0.experimentID == experiment.id
        })
      else { continue }
      return OutcomeTarget(
        personaID: scenario.segmentID,
        personaName: segmentName(for: scenario.segmentID, config: config),
        scenarioID: scenario.id,
        cohortID: executableCohortID(
          forScenarioID: scenario.id,
          experiment: experiment,
          config: config
        )
      )
    }
    guard let summary = summaries.first else { return nil }
    return OutcomeTarget(
      personaID: summary.personaID,
      personaName: segmentName(for: summary.personaID, config: config),
      scenarioID: nil,
      cohortID: nil
    )
  }

  private static func allowedDecision(
    _ decision: ProductTournamentExperimentDecision,
    current: ProductTournamentExperimentDecision
  ) -> ProductTournamentExperimentDecision? {
    if decision == current { return decision }
    return ProductTournamentDecisionTransitionValidator.allowedNextDecisions(from: current)
      .contains(decision)
      ? decision
      : nil
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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

  private static func segmentName(for segmentID: String, config: ProductTournamentConfig) -> String
  {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }
}

enum TournamentAutomationRationaleSignalAdvisor {
  static func signals(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationRationaleSignal] {
    config.tournamentExperiments.compactMap { experiment in
      signal(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func signal(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationRationaleSignal? {
    let summaries = evidenceIndex.summaries(for: experiment)
    guard !summaries.isEmpty else { return nil }
    let aggregate = ProductTournamentEvidenceAggregateSummary(summaries: summaries)
    guard
      let aggregateSignal = aggregate.personaRationaleSignals.first(where: {
        isActionable($0.rationale)
      })
    else { return nil }
    let sourceRunIDs = Set(aggregateSignal.runIDs)
    let sourceSummaries = summaries.filter { sourceRunIDs.contains($0.runID) }
    let target = target(for: sourceSummaries, experiment: experiment, config: config)
    let targetDecision = targetDecision(
      for: evidenceIndex.currentTournamentReadiness(for: experiment),
      currentDecision: experiment.decision
    )
    let targetLabel =
      target?.personaName.map { " Target \(StringUtils.boundedText($0, limit: 80))" } ?? ""
    let rationaleText = aggregateSignal.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
    let rationalePunctuation = rationaleText.hasSuffix(".") ? "" : "."
    let summary =
      "Repeated simulated-user rationale appeared in \(aggregateSignal.count) current run(s): \(rationaleText)\(rationalePunctuation)\(targetLabel) Resolve this reason with product implementation, scenario, or current-alternative proof before lift/cut."
    return TournamentAutomationRationaleSignal(
      experimentID: experiment.id,
      rationale: aggregateSignal.rationale,
      count: aggregateSignal.count,
      runIDs: aggregateSignal.runIDs,
      targetPersonaID: target?.personaID,
      targetPersonaName: target?.personaName,
      targetScenarioID: target?.scenarioID,
      targetCohortID: target?.cohortID,
      targetDecision: targetDecision,
      summary: summary
    )
  }

  private static func targetDecision(
    for readiness: ProductTournamentReadiness?,
    currentDecision: ProductTournamentExperimentDecision
  ) -> ProductTournamentExperimentDecision? {
    guard let readiness else { return nil }
    let target: ProductTournamentExperimentDecision?
    switch readiness.recommendation {
    case .promote:
      target = .promote
    case .kill:
      target = .kill
    case .narrow:
      target = .narrow
    case .pivot:
      target = .pivot
    case .gatherEvidence, .keepGoing:
      target = nil
    }
    guard let target,
      target == currentDecision
        || ProductTournamentDecisionTransitionValidator.allowedNextDecisions(
          from: currentDecision
        ).contains(target)
    else { return nil }
    return target
  }

  private struct SignalTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
  }

  private static func target(
    for summaries: [ProductTournamentEvidenceSummary],
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> SignalTarget? {
    let preferred = summaries.sorted { lhs, rhs in
      let lhsRank = sourceRank(lhs)
      let rhsRank = sourceRank(rhs)
      if lhsRank == rhsRank {
        if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
        return lhs.endedAt > rhs.endedAt
      }
      return lhsRank > rhsRank
    }
    for summary in preferred {
      let scenarioID = summary.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !scenarioID.isEmpty,
        let scenario = config.scenarios.first(where: {
          $0.id == scenarioID && $0.experimentID == experiment.id
        })
      else { continue }
      return SignalTarget(
        personaID: scenario.segmentID,
        personaName: segmentName(for: scenario.segmentID, config: config),
        scenarioID: scenario.id,
        cohortID: executableCohortID(
          forScenarioID: scenario.id,
          experiment: experiment,
          config: config
        )
      )
    }
    guard let summary = preferred.first else { return nil }
    return SignalTarget(
      personaID: summary.personaID,
      personaName: segmentName(for: summary.personaID, config: config),
      scenarioID: nil,
      cohortID: nil
    )
  }

  private static func sourceRank(_ summary: ProductTournamentEvidenceSummary) -> Int {
    var rank = summary.mode == .personaModel ? 10 : 0
    switch summary.verdict {
    case .rejected: rank += 5
    case .weak: rank += 4
    case .unclear: rank += 3
    case .promising: rank += 2
    case .strongPull: rank += 1
    }
    return rank
  }

  private static func isActionable(_ rationale: String) -> Bool {
    let normalized = normalizedRationale(rationale)
    guard !normalized.isEmpty else { return false }
    let actionableTerms = [
      "need",
      "needed",
      "needs",
      "before",
      "switch",
      "trust",
      "proof",
      "evidence",
      "alternative",
      "spreadsheet",
      "manual",
      "missing",
      "import",
      "risk",
      "roi",
      "objection",
      "concern",
      "unclear",
      "cannot",
      "can't",
      "reject",
      "hesitat",
    ]
    return actionableTerms.contains { normalized.contains($0) }
  }

  private static func normalizedRationale(_ value: String) -> String {
    value
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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

  private static func segmentName(for segmentID: String, config: ProductTournamentConfig) -> String
  {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }
}

enum TournamentAutomationRevisionBriefSource: String, Equatable, Sendable {
  case personaModelRationale = "persona_model_rationale"
  case targetedProofOutcome = "targeted_proof_outcome"
  case roundTwoProofGap = "round_2_proof_gap"
  case roundThreeImplementationRevision = "round_3_implementation_revision"
}

struct TournamentAutomationRevisionBrief: Equatable, Sendable, Identifiable {
  var id: String {
    [
      experimentID,
      source.rawValue,
      targetDecision?.rawValue ?? "none",
      targetScenarioID ?? targetPersonaID ?? triggerSummary,
    ].joined(separator: ":")
  }

  var experimentID: String
  var source: TournamentAutomationRevisionBriefSource
  var title: String
  var priority: Int
  var triggerSummary: String
  var implementationChange: String
  var scenarioChange: String
  var proofPlan: String
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetScenarioID: String?
  var targetCohortID: String?
  var targetDecision: ProductTournamentExperimentDecision?

  var displaySubtitle: String {
    let target = targetPersonaName.map { "target \($0)" } ?? "no target persona"
    let decision = targetDecision.map { "; decision \($0.rawValue)" } ?? ""
    return "\(source.rawValue); \(target)\(decision); priority \(priority)"
  }

  var displayDetail: String {
    var parts = [
      "Trigger: \(triggerSummary)",
      "Product implementation: \(implementationChange)",
      "Scenario: \(scenarioChange)",
      "Proof: \(proofPlan)",
    ]
    if let targetDecision {
      parts.append("Decision: \(targetDecision.rawValue)")
    }
    return parts.joined(separator: " ")
  }

  var auditSummary: String {
    var parts = [
      "\(experimentID): \(title)",
      "source \(source.rawValue)",
      "priority \(priority)",
    ]
    if let targetDecision {
      parts.append("target_decision \(targetDecision.rawValue)")
    }
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    }
    if let targetCohortID {
      parts.append("cohort \(targetCohortID)")
    }
    parts.append("implementation \(implementationChange)")
    parts.append("proof \(proofPlan)")
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 700)
  }

  init(
    experimentID: String,
    source: TournamentAutomationRevisionBriefSource,
    title: String,
    priority: Int,
    triggerSummary: String,
    implementationChange: String,
    scenarioChange: String,
    proofPlan: String,
    targetPersonaID: String? = nil,
    targetPersonaName: String? = nil,
    targetScenarioID: String? = nil,
    targetCohortID: String? = nil,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.source = source
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Revise product contender",
      limit: 160
    )
    self.priority = max(0, priority)
    self.triggerSummary = ProductTournamentModelText.cleanedText(
      triggerSummary,
      fallback: "persona-model evidence found a contender revision trigger.",
      limit: 320
    )
    self.implementationChange = ProductTournamentModelText.cleanedText(
      implementationChange,
      fallback: "Update the product implementation to address the evidence trigger.",
      limit: 360
    )
    self.scenarioChange = ProductTournamentModelText.cleanedText(
      scenarioChange,
      fallback: "Retarget the scenario so the next persona-model run can test the change.",
      limit: 360
    )
    self.proofPlan = ProductTournamentModelText.cleanedText(
      proofPlan,
      fallback: "Rerun targeted persona-model proof against the current alternative.",
      limit: 360
    )
    self.targetPersonaID = ProductTournamentModelText.optionalIdentifier(
      targetPersonaID,
      fallback: "persona"
    )
    self.targetPersonaName = ProductTournamentModelText.optionalCleanedText(
      targetPersonaName,
      limit: 160
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.targetCohortID = ProductTournamentModelText.optionalIdentifier(
      targetCohortID,
      fallback: "cohort"
    )
    self.targetDecision = targetDecision
  }
}

enum TournamentAutomationRevisionBriefAdvisor {
  static func briefs(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationRevisionBrief] {
    config.tournamentExperiments.compactMap {
      brief(for: $0, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.priority == rhs.priority { return lhs.experimentID < rhs.experimentID }
      return lhs.priority > rhs.priority
    }
  }

  static func brief(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationRevisionBrief? {
    if let proofOutcomeBrief = targetedProofOutcomeBrief(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return proofOutcomeBrief
    }
    if let proofGapBrief = roundTwoProofGapBrief(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return proofGapBrief
    }
    if let implementationRevisionBrief = roundThreeImplementationRevisionBrief(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return implementationRevisionBrief
    }
    guard
      let signal = TournamentAutomationRationaleSignalAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return nil }
    let action = ProductTournamentNextActionAdvisor.nextAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let isRetargeted = action?.title == "Retarget simulated-user rationale signal"
    guard isRetargeted || action?.title == "Resolve simulated-user rationale signal" else {
      return nil
    }
    let revision = revisionPlan(
      for: signal,
      isRetargeted: isRetargeted
    )
    return TournamentAutomationRevisionBrief(
      experimentID: experiment.id,
      source: .personaModelRationale,
      title: revision.title,
      priority: action?.priority ?? signal.urgencyScore,
      triggerSummary: signal.summary,
      implementationChange: revision.implementationChange,
      scenarioChange: revision.scenarioChange,
      proofPlan: revision.proofPlan,
      targetPersonaID: signal.targetPersonaID,
      targetPersonaName: signal.targetPersonaName,
      targetScenarioID: signal.targetScenarioID,
      targetCohortID: signal.targetCohortID,
      targetDecision: action?.targetDecision ?? signal.targetDecision
    )
  }

  private static func targetedProofOutcomeBrief(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationRevisionBrief? {
    guard
      let signal = TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return nil }
    let action = ProductTournamentNextActionAdvisor.nextAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let isRetargeted = action?.title == "Retarget tournament proof outcome"
    guard signal.actionKind == .refineContender || isRetargeted else { return nil }
    guard action?.title == signal.title || isRetargeted else {
      return nil
    }
    let revision = revisionPlan(for: signal)
    return TournamentAutomationRevisionBrief(
      experimentID: experiment.id,
      source: .targetedProofOutcome,
      title: revision.title,
      priority: action?.priority ?? signal.priority,
      triggerSummary: signal.summary,
      implementationChange: revision.implementationChange,
      scenarioChange: revision.scenarioChange,
      proofPlan: revision.proofPlan,
      targetPersonaID: signal.targetPersonaID,
      targetPersonaName: signal.targetPersonaName,
      targetScenarioID: signal.targetScenarioID,
      targetCohortID: signal.targetCohortID,
      targetDecision: action?.targetDecision ?? signal.recommendedDecision
        ?? signal.targetDecision
    )
  }

  static func roundTwoProofGapBrief(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationRevisionBrief? {
    guard
      let proposal = ProductTournamentRoundEvidenceTransitioner.proposals(
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: {
        $0.recommendation == .reviseCoreTechnology
          && contender($0.contenderID, matches: experiment, in: config)
      })
    else { return nil }

    let target = roundTwoProofGapTarget(
      for: proposal,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let gaps = proofGapSummary(for: proposal)
    return TournamentAutomationRevisionBrief(
      experimentID: experiment.id,
      source: .roundTwoProofGap,
      title: "Revise Round 2 core technology proof gaps",
      priority: max(proposal.priority, 86),
      triggerSummary:
        "Round 2 feasibility evidence recommends revising contender `\(proposal.contenderID)`: \(gaps).",
      implementationChange:
        "Address \(gaps) in the core technology proof before adding Round 3 product implementation fidelity.",
      scenarioChange:
        target.scenarioChange
          ?? "Retarget scoped Round 2 scenarios so simulated users must exercise the revised core technology and compare it against the current workaround.",
      proofPlan: proposal.nextValidationTarget,
      targetPersonaID: target.personaID,
      targetPersonaName: target.personaName,
      targetScenarioID: target.scenarioID,
      targetCohortID: target.cohortID,
      targetDecision: .narrow
    )
  }

  static func roundThreeImplementationRevisionBrief(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationRevisionBrief? {
    guard
      let proposal = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: {
        $0.recommendation == .reviseImplementation
          && contender($0.contenderID, matches: experiment, in: config)
      })
    else { return nil }

    let target = roundThreeImplementationRevisionTarget(
      for: proposal,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let gaps = proofGapSummary(for: proposal)
    return TournamentAutomationRevisionBrief(
      experimentID: experiment.id,
      source: .roundThreeImplementationRevision,
      title: "Revise Round 3 product implementation proof gaps",
      priority: max(proposal.priority, 88),
      triggerSummary:
        "Round 3 product implementation evidence recommends revising contender `\(proposal.contenderID)`: \(gaps).",
      implementationChange:
        "Revise the low-medium fidelity product implementation against \(gaps) before selecting a tournament winner.",
      scenarioChange:
        target.scenarioChange
          ?? "Retarget scoped Round 3 scenarios so simulated users must exercise the revised product implementation, compare against the current alternative, and make an explicit willingness-to-pay or sponsorship judgment.",
      proofPlan: proposal.nextValidationTarget,
      targetPersonaID: target.personaID,
      targetPersonaName: target.personaName,
      targetScenarioID: target.scenarioID,
      targetCohortID: target.cohortID,
      targetDecision: .narrow
    )
  }

  private struct RevisionPlan: Equatable, Sendable {
    var title: String
    var implementationChange: String
    var scenarioChange: String
    var proofPlan: String
  }

  private struct RoundTwoProofGapTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
    var scenarioChange: String?
  }

  private struct RoundThreeImplementationRevisionTarget: Equatable, Sendable {
    var personaID: String?
    var personaName: String?
    var scenarioID: String?
    var cohortID: String?
    var scenarioChange: String?
  }

  private static func roundTwoProofGapTarget(
    for proposal: ProductTournamentRoundEvidenceTransitionProposal,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> RoundTwoProofGapTarget {
    let scopedSummaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == proposal.tournamentID
          && $0.roundID == proposal.roundID
          && $0.contenderID == proposal.contenderID
          && $0.isCompleted
      }
      .sorted(by: roundTwoProofGapSummarySort)
    guard let summary = scopedSummaries.first else {
      return RoundTwoProofGapTarget()
    }
    let scenario = config.scenarios.first {
      $0.id == summary.scenarioID && $0.experimentID == experiment.id
    }
    let rawPersonaID =
      summary.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? scenario?.segmentID
      : summary.personaID
    let personaID = rawPersonaID.flatMap { candidateID in
      config.userSegments.contains { $0.id == candidateID } ? candidateID : nil
    }
    let personaName = personaID.map { segmentName(for: $0, config: config) }
    let cohortID = scenario.flatMap {
      executableCohortID(
        forScenarioID: $0.id,
        experiment: experiment,
        config: config
      )
    }
    let targetName = personaName ?? "the target simulated user"
    let scenarioChange =
      "Retarget scoped Round 2 validation for \(targetName) so the persona must exercise the revised core technology, inspect the corrected proof gaps, and compare against the current workaround."
    return RoundTwoProofGapTarget(
      personaID: personaID,
      personaName: personaName,
      scenarioID: scenario?.id,
      cohortID: cohortID,
      scenarioChange: scenarioChange
    )
  }

  private static func roundTwoProofGapSummarySort(
    lhs: ProductTournamentEvidenceSummary,
    rhs: ProductTournamentEvidenceSummary
  ) -> Bool {
    let lhsScore = roundTwoProofGapSummaryPriority(lhs)
    let rhsScore = roundTwoProofGapSummaryPriority(rhs)
    if lhsScore == rhsScore {
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    return lhsScore > rhsScore
  }

  private static func roundTwoProofGapSummaryPriority(
    _ summary: ProductTournamentEvidenceSummary
  ) -> Int {
    var score = 0
    if !summary.missingCapabilities.isEmpty { score += 8 }
    if !summary.objections.isEmpty { score += 6 }
    switch summary.verdict {
    case .rejected: score += 5
    case .weak: score += 4
    case .unclear: score += 3
    case .promising: score += 1
    case .strongPull: break
    }
    return score
  }

  private static func roundThreeImplementationRevisionTarget(
    for proposal: ProductTournamentProductImplementationEvidenceTransitionProposal,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> RoundThreeImplementationRevisionTarget {
    let scopedSummaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == proposal.tournamentID
          && $0.roundID == proposal.roundID
          && $0.contenderID == proposal.contenderID
          && $0.isCompleted
      }
      .sorted(by: roundThreeImplementationRevisionSummarySort)
    guard let summary = scopedSummaries.first else {
      return RoundThreeImplementationRevisionTarget()
    }
    let scenarioByID = config.scenarios.first {
      $0.id == summary.scenarioID && $0.experimentID == experiment.id
    }
    let scenario =
      scenarioByID
      ?? config.scenarios.first {
        $0.experimentID == experiment.id && $0.segmentID == summary.personaID
      }
    let rawPersonaID =
      summary.personaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? scenario?.segmentID
      : summary.personaID
    let personaID = rawPersonaID.flatMap { candidateID in
      config.userSegments.contains { $0.id == candidateID } ? candidateID : nil
    }
    let personaName = personaID.map { segmentName(for: $0, config: config) }
    let cohortID = scenario.flatMap {
      executableCohortID(
        forScenarioID: $0.id,
        experiment: experiment,
        config: config
      )
    }
    let targetName = personaName ?? "the target simulated user"
    let scenarioChange =
      "Retarget scoped Round 3 validation for \(targetName) so the persona must exercise the revised low-medium fidelity implementation, compare it against the current alternative, and give explicit willingness-to-pay or sponsorship intent."
    return RoundThreeImplementationRevisionTarget(
      personaID: personaID,
      personaName: personaName,
      scenarioID: scenario?.id,
      cohortID: cohortID,
      scenarioChange: scenarioChange
    )
  }

  private static func roundThreeImplementationRevisionSummarySort(
    lhs: ProductTournamentEvidenceSummary,
    rhs: ProductTournamentEvidenceSummary
  ) -> Bool {
    let lhsScore = roundThreeImplementationRevisionSummaryPriority(lhs)
    let rhsScore = roundThreeImplementationRevisionSummaryPriority(rhs)
    if lhsScore == rhsScore {
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    return lhsScore > rhsScore
  }

  private static func roundThreeImplementationRevisionSummaryPriority(
    _ summary: ProductTournamentEvidenceSummary
  ) -> Int {
    var score = 0
    if !summary.missingCapabilities.isEmpty { score += 8 }
    if hasRoundThreePayConcern(summary) { score += 7 }
    if !summary.objections.isEmpty { score += 6 }
    if !summary.completedUseProof { score += 5 }
    switch summary.verdict {
    case .rejected: score += 5
    case .weak: score += 4
    case .unclear: score += 3
    case .promising: score += 1
    case .strongPull: break
    }
    return score
  }

  private static func hasRoundThreePayConcern(
    _ summary: ProductTournamentEvidenceSummary
  ) -> Bool {
    let willingnessToPay = summary.scores.willingnessToPay ?? summary.willingnessToPayScore
    return willingnessToPay.map { $0 < 4 } ?? false
  }

  private static func proofGapSummary(
    for proposal: ProductTournamentRoundEvidenceTransitionProposal
  ) -> String {
    let gaps =
      proposal.proofGaps.isEmpty
      ? [proposal.detail]
      : Array(proposal.proofGaps.prefix(4))
    return StringUtils.boundedText(gaps.joined(separator: "; "), limit: 260)
  }

  private static func proofGapSummary(
    for proposal: ProductTournamentProductImplementationEvidenceTransitionProposal
  ) -> String {
    let gaps =
      proposal.proofGaps.isEmpty
      ? [proposal.detail]
      : Array(proposal.proofGaps.prefix(4))
    return StringUtils.boundedText(gaps.joined(separator: "; "), limit: 260)
  }

  private static func contender(
    _ contenderID: String,
    matches experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> Bool {
    config.tournamentContenders.contains {
      $0.id == contenderID && $0.experimentID == experiment.id
    }
  }

  private static func segmentName(for segmentID: String, config: ProductTournamentConfig) -> String
  {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }

  private static func executableCohortID(
    forScenarioID scenarioID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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

  private static func revisionPlan(
    for signal: TournamentAutomationRationaleSignal,
    isRetargeted: Bool
  ) -> RevisionPlan {
    let rationale = signal.rationale.lowercased()
    let targetName = signal.targetPersonaName ?? "the target simulated user"
    let retargetPrefix =
      isRetargeted
      ? "The same rationale survived a tournament automation cycle; "
      : ""
    if containsAny(rationale, ["csv", "import", "spreadsheet"]) {
      return RevisionPlan(
        title: isRetargeted
          ? "Retarget contender revision for simulated-user rationale"
          : "Revise product implementation for simulated-user rationale",
        implementationChange:
          "\(retargetPrefix)add a visible import or spreadsheet handoff path that proves the product implementation can absorb real current-workflow data.",
        scenarioChange:
          "Ask \(targetName) to bring a realistic spreadsheet, CSV, or manual artifact into the scenario and judge whether the product implementation preserves context.",
        proofPlan:
          "Rerun the targeted persona-model scenario and compare import effort, missing fields, and confidence against the manual spreadsheet alternative."
      )
    }
    if containsAny(rationale, ["roi", "cost", "risk", "budget", "sponsor"]) {
      return RevisionPlan(
        title: isRetargeted
          ? "Retarget contender revision for simulated-user rationale"
          : "Revise product implementation for simulated-user rationale",
        implementationChange:
          "\(retargetPrefix)add sponsor-facing proof of cost, risk reduction, or decision confidence directly in the product implementation flow.",
        scenarioChange:
          "Frame the next scenario around \(targetName)'s investment decision and require an explicit continue, narrow, kill, or promote rationale.",
        proofPlan:
          "Rerun persona-model sponsor proof and require a current-alternative comparison that names the ROI or risk threshold."
      )
    }
    if containsAny(rationale, ["trust", "proof", "evidence", "confidence"]) {
      return RevisionPlan(
        title: isRetargeted
          ? "Retarget contender revision for simulated-user rationale"
          : "Revise product implementation for simulated-user rationale",
        implementationChange:
          "\(retargetPrefix)make the proof artifact inspectable: show source context, decision criteria, and why the product implementation beats the current workflow.",
        scenarioChange:
          "Make \(targetName) inspect the evidence trail before choosing whether to switch or keep the current alternative.",
        proofPlan:
          "Rerun the targeted persona-model scenario and require explicit evidence-quality scoring against the current alternative."
      )
    }
    if containsAny(rationale, ["switch", "switching", "manual", "alternative"]) {
      return RevisionPlan(
        title: isRetargeted
          ? "Retarget contender revision for simulated-user rationale"
          : "Revise product implementation for simulated-user rationale",
        implementationChange:
          "\(retargetPrefix)reduce switching friction by making the first successful workflow moment obvious and reversible.",
        scenarioChange:
          "Put \(targetName) at the exact switching decision between the product implementation and the current manual workflow.",
        proofPlan:
          "Rerun persona-model proof and compare setup effort, risk, and first-use value against the current alternative."
      )
    }
    if containsAny(rationale, ["unclear", "confusing", "missing", "cannot", "can't"]) {
      return RevisionPlan(
        title: isRetargeted
          ? "Retarget contender revision for simulated-user rationale"
          : "Revise product implementation for simulated-user rationale",
        implementationChange:
          "\(retargetPrefix)remove ambiguity in the next action and expose the missing capability where the simulated user got stuck.",
        scenarioChange:
          "Rewrite the scenario around the moment \(targetName) could not complete, trust, or interpret the workflow.",
        proofPlan:
          "Rerun the targeted persona-model scenario and require the user to name the next action without external explanation."
      )
    }
    return RevisionPlan(
      title: isRetargeted
        ? "Retarget contender revision for simulated-user rationale"
        : "Revise product implementation for simulated-user rationale",
      implementationChange:
        "\(retargetPrefix)turn the repeated rationale into a visible product affordance, not just a better explanation.",
      scenarioChange:
        "Retarget the next scenario so \(targetName) must confront the repeated rationale before giving a tournament verdict.",
      proofPlan:
        "Rerun targeted persona-model proof and require a current-alternative comparison that says whether the rationale is resolved."
    )
  }

  private static func revisionPlan(
    for signal: TournamentAutomationTargetedProofOutcomeSignal
  ) -> RevisionPlan {
    let targetName = signal.targetPersonaName ?? "the target simulated user"
    switch (signal.targetDecision, signal.outcome) {
    case (.promote, .contradictsTarget), (.promoted, .contradictsTarget):
      return RevisionPlan(
        title: "Revise contradicted promotion proof",
        implementationChange:
          "narrow the promoted promise to the workflow moment that can prove current-alternative advantage for \(targetName), and remove unsupported lift claims from the product implementation.",
        scenarioChange:
          "Retarget the scenario so \(targetName) must compare the revised product implementation against the current alternative before giving a promote, narrow, or kill rationale.",
        proofPlan:
          "Rerun targeted persona-model promotion proof and require alternative advantage, switching readiness, and continued-use pull to clear the contradiction."
      )
    case (.kill, .contradictsTarget), (.archived, .contradictsTarget):
      return RevisionPlan(
        title: "Revise contradicted stop proof",
        implementationChange:
          "make the pull that contradicted killing visible in the first successful workflow moment, with explicit before/after value against the current alternative.",
        scenarioChange:
          "Retarget the scenario so \(targetName) tests whether that pull repeats or collapses under realistic switching objections.",
        proofPlan:
          "Rerun persona-model lift proof before cutting, and require the persona to choose continue, promote, narrow, or kill with reasons."
      )
    case (.narrow, .supportsTarget), (.pivot, .supportsTarget):
      return RevisionPlan(
        title: "Apply supported reshape proof",
        implementationChange:
          "reshape the product implementation around the smaller product contender that the targeted proof supported, preserving only the capabilities that created pull.",
        scenarioChange:
          "Retarget the scenario to the narrower workflow and require \(targetName) to judge whether the narrower promise beats the current alternative.",
        proofPlan:
          "Rerun targeted persona-model proof for the narrowed contender before considering lift/cut."
      )
    case (_, .inconclusive):
      return RevisionPlan(
        title: "Sharpen inconclusive tournament proof",
        implementationChange:
          "make the decision criteria visible in the product implementation so the simulated user can judge pain recognition, alternative advantage, switching readiness, and continued-use pull.",
        scenarioChange:
          "Rewrite the scenario around a single forced tournament decision for \(targetName), with explicit current-alternative comparison.",
        proofPlan:
          "Rerun targeted persona-model proof and require the result to support or contradict \(signal.targetDecision.rawValue), not remain inconclusive."
      )
    default:
      return RevisionPlan(
        title: signal.title,
        implementationChange:
          "translate the targeted proof outcome into a visible product change before the same tournament decision is tested again.",
        scenarioChange:
          "Retarget the scenario to the proof outcome and require \(targetName) to explain whether the product contender should continue, narrow, pivot, kill, or promote.",
        proofPlan:
          "Rerun targeted persona-model proof and compare the new outcome with \(signal.runIDs.prefix(3).joined(separator: ", "))."
      )
    }
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }
}

struct TournamentAutomationProofTarget: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var label: String
  var readinessScore: Int
  var debtSummary: String
  var nextActionTitle: String?
  var nextActionKind: ProductTournamentNextActionKind?
  var nextActionPriority: Int
  var tournamentID: String?
  var contenderID: String?
  var roundID: String?
  var cohortID: String?
  var targetScenarioID: String?
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetDecision: ProductTournamentExperimentDecision?
  var requiredSimulationMode: ProductTournamentSimulationMode?
  var tournamentPositionSummary: String?

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
    if let targetDecision {
      parts.append("decision \(targetDecision.rawValue)")
    } else if let contenderID {
      parts.append("contender \(contenderID)")
    }
    return parts.joined(separator: ", ")
  }

  var displayDetail: String {
    var parts = ["Debt: \(debtSummary)"]
    if let nextActionTitle {
      parts.append("Next: \(nextActionTitle)")
    }
    if let tournamentPositionSummary {
      parts.append("Tournament position: \(tournamentPositionSummary)")
    }
    if let tournamentID {
      parts.append("Tournament: \(tournamentID)")
    }
    if let targetDecision {
      parts.append("Decision: \(targetDecision.rawValue)")
    }
    if let targetScenarioID {
      parts.append("Scenario: \(targetScenarioID)")
    } else if let cohortID {
      parts.append("Cohort: \(cohortID)")
    } else if let roundID {
      parts.append("Round: \(roundID)")
    }
    if let contenderID {
      parts.append("Contender: \(contenderID)")
    }
    if targetScenarioID == nil, let targetPersonaName {
      parts.append("Persona: \(targetPersonaName)")
    }
    return parts.joined(separator: " ")
  }

  var auditSummary: String {
    var parts = ["\(experimentID): \(label)"]
    if let targetDecision {
      parts.append("target_decision \(targetDecision.rawValue)")
    }
    if let requiredSimulationMode {
      parts.append("required_mode \(requiredSimulationMode.rawValue)")
    }
    if let targetPersonaName {
      parts.append("target \(targetPersonaName)")
    }
    if let tournamentID {
      parts.append("tournament \(tournamentID)")
    }
    if let targetScenarioID {
      parts.append("scenario \(targetScenarioID)")
    } else if let cohortID {
      parts.append("cohort \(cohortID)")
    } else if let roundID {
      parts.append("round \(roundID)")
    }
    if let contenderID {
      parts.append("contender \(contenderID)")
    }
    if let tournamentPositionSummary {
      parts.append("position \(tournamentPositionSummary)")
    }
    parts.append("debt \(debtSummary)")
    return StringUtils.boundedText(parts.joined(separator: "; "), limit: 360)
  }

  init(
    experimentID: String,
    label: String,
    readinessScore: Int,
    debtSummary: String,
    nextAction: ProductTournamentNextAction?,
    tournamentID: String? = nil,
    contenderID: String? = nil,
    roundID: String? = nil,
    tournamentPositionSummary: String? = nil,
    planProofActionTitle: String? = nil,
    planProofPriority: Int = 0
  ) {
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.label = ProductTournamentModelText.cleanedText(
      label,
      fallback: "close tournament proof debt",
      limit: 160
    )
    self.readinessScore = min(100, max(0, readinessScore))
    self.debtSummary = ProductTournamentModelText.cleanedText(
      debtSummary,
      fallback: "proof incomplete",
      limit: 240
    )
    self.nextActionTitle = nextAction?.title ?? planProofActionTitle
    self.nextActionKind = nextAction?.kind
    self.nextActionPriority = nextAction?.priority ?? planProofPriority
    self.tournamentID =
      nextAction?.tournamentID
      ?? ProductTournamentModelText.optionalIdentifier(tournamentID, fallback: "tournament")
    self.contenderID = ProductTournamentModelText.optionalIdentifier(
      nextAction?.contenderID ?? contenderID,
      fallback: "contender"
    )
    self.roundID =
      nextAction?.roundID
      ?? ProductTournamentModelText.optionalIdentifier(roundID, fallback: "round")
    self.cohortID = nextAction?.cohortID
    self.targetScenarioID = nextAction?.targetScenarioID
    self.targetPersonaID = nextAction?.targetPersonaID
    self.targetPersonaName = nextAction?.targetPersonaName
    self.targetDecision = nextAction?.targetDecision
    self.requiredSimulationMode = nextAction?.requiredSimulationMode
    self.tournamentPositionSummary = ProductTournamentModelText.optionalCleanedText(
      tournamentPositionSummary,
      limit: 220
    )
  }
}

enum TournamentAutomationProofTargetAdvisor {
  static func targets(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [TournamentAutomationProofTarget] {
    TournamentAutomationExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { experiment in
      target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    }
    .sorted { lhs, rhs in
      if lhs.urgencyScore == rhs.urgencyScore { return lhs.experimentID < rhs.experimentID }
      return lhs.urgencyScore > rhs.urgencyScore
    }
  }

  static func target(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationProofTarget? {
    guard
      !ProductTournamentRoundImplementationTargetResolver.blocksEvidenceLaunch(
        experimentID: experiment.id,
        in: config
      )
    else { return nil }
    if let readiness = evidenceIndex.currentTournamentReadiness(for: experiment),
      !readiness.proofDebt.isClear
    {
      let action = ProductTournamentNextActionAdvisor.nextAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
      return TournamentAutomationProofTarget(
        experimentID: experiment.id,
        label: label(readiness: readiness, action: action),
        readinessScore: Int(readiness.readinessScore.rounded()),
        debtSummary: readiness.proofDebt.summary,
        nextAction: action,
        tournamentPositionSummary: tournamentPositionSummary(
          for: experiment,
          nextAction: action,
          tournamentID: action?.tournamentID,
          contenderID: action?.contenderID,
          roundID: action?.roundID,
          config: config
        )
      )
    }
    return planProofTarget(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
  }

  private static func planProofTarget(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool
  ) -> TournamentAutomationProofTarget? {
    guard
      let contender = config.tournamentContenders.first(where: { $0.experimentID == experiment.id }
      ),
      isPlanProofEligible(contender.status),
      let planScope = activePlanRound(for: contender, config: config)
    else { return nil }
    let completed = evidenceIndex.planEvaluations(for: planScope.tournament, round: planScope.round)
      .filter { $0.contenderID == contender.id && $0.isCompleted }
    let readiness = completed.isEmpty ? nil : ProductTournamentPlanReadiness(summaries: completed)
    let proofDebt =
      readiness?.planProofDebt
      ?? ProductTournamentPlanProofDebt(
        completedEvaluationCount: 0,
        distinctPersonaCount: 0,
        buyerOrSponsorPersonaCount: 0,
        averageWillingnessToPayScore: 0
      )
    let needsPersonaModelPlanProof =
      readiness.map {
        isPersonaModelAvailable && $0.modelFreeEvaluationCount > 0
          && $0.personaModelEvaluationCount == 0
      } ?? false
    guard proofDebt.hasActionableFocusedProof || needsPersonaModelPlanProof else { return nil }
    let actionTitle =
      needsPersonaModelPlanProof ? "Run Persona Plan Proof" : proofDebt.focusedActionTitle
    let debtSummary =
      needsPersonaModelPlanProof
      ? "\(proofDebt.summary); persona-model plan proof missing"
      : proofDebt.summary
    return TournamentAutomationProofTarget(
      experimentID: experiment.id,
      label: actionTitle,
      readinessScore: Int((readiness?.readinessScore ?? 0).rounded()),
      debtSummary: debtSummary,
      nextAction: ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .runPlanProof,
        title: actionTitle,
        detail: "",
        priority: needsPersonaModelPlanProof ? 96 : 92,
        tournamentID: planScope.tournament.id,
        roundID: planScope.round.id,
        contenderID: contender.id,
        requiredSimulationMode: needsPersonaModelPlanProof ? .personaModel : nil
      ),
      tournamentID: planScope.tournament.id,
      contenderID: contender.id,
      roundID: planScope.round.id,
      tournamentPositionSummary: tournamentPositionSummary(
        for: experiment,
        nextAction: nil,
        tournamentID: planScope.tournament.id,
        contenderID: contender.id,
        roundID: planScope.round.id,
        config: config
      ),
      planProofActionTitle: actionTitle,
      planProofPriority: needsPersonaModelPlanProof ? 96 : 92
    )
  }

  private static func tournamentPositionSummary(
    for experiment: ProductTournamentExperiment,
    nextAction: ProductTournamentNextAction?,
    tournamentID: String?,
    contenderID: String?,
    roundID: String?,
    config: ProductTournamentConfig
  ) -> String? {
    guard
      let contender = tournamentContender(
        experimentID: experiment.id,
        contenderID: nextAction?.contenderID ?? contenderID,
        config: config
      ),
      let tournament = tournament(
        tournamentID: nextAction?.tournamentID ?? tournamentID ?? contender.tournamentID,
        contender: contender,
        config: config
      ),
      let round = round(
        roundID: nextAction?.roundID ?? roundID,
        contender: contender,
        tournament: tournament,
        config: config
      )
    else { return nil }

    let roundContenderIDs = round.contenderIDs.isEmpty
      ? tournament.contenderIDs
      : round.contenderIDs
    let contendersByID = Dictionary(
      uniqueKeysWithValues: config.tournamentContenders.map { ($0.id, $0) }
    )
    let roundContenders = roundContenderIDs.compactMap { contendersByID[$0] }
    let activeRoundContenders = roundContenders.filter { isActiveTournamentStatus($0.status) }
    let positionedContenders =
      activeRoundContenders.contains { $0.id == contender.id }
      ? activeRoundContenders
      : roundContenders
    guard !positionedContenders.isEmpty,
      let position = positionedContenders
        .sorted(by: tournamentPositionSort)
        .firstIndex(where: { $0.id == contender.id })
    else { return nil }

    let count = positionedContenders.count
    let rivalCount = max(0, count - 1)
    let activeText = activeRoundContenders.isEmpty ? "round" : "active"
    let rivalText = rivalCount == 1 ? "1 rival product" : "\(rivalCount) rival products"
    return "\(round.kind.title) contender \(position + 1) of \(count) \(activeText) contender(s); compare against \(rivalText)"
  }

  private static func tournamentContender(
    experimentID: String,
    contenderID: String?,
    config: ProductTournamentConfig
  ) -> ProductTournamentContender? {
    contenderID.flatMap { id in
      config.tournamentContenders.first { $0.id == id }
    } ?? config.tournamentContenders.first { $0.experimentID == experimentID }
  }

  private static func tournament(
    tournamentID: String?,
    contender: ProductTournamentContender,
    config: ProductTournamentConfig
  ) -> ProductTournament? {
    tournamentID.flatMap { id in
      config.tournaments.first { $0.id == id }
    } ?? config.tournaments.first { $0.id == contender.tournamentID }
  }

  private static func round(
    roundID: String?,
    contender: ProductTournamentContender,
    tournament: ProductTournament,
    config: ProductTournamentConfig
  ) -> ProductTournamentRound? {
    if let roundID,
      let round = config.tournamentRounds.first(where: {
        $0.id == roundID && $0.tournamentID == tournament.id
      })
    {
      return round
    }
    if let currentRoundID = tournament.currentRoundID,
      let currentRound = config.tournamentRounds.first(where: {
        $0.id == currentRoundID
          && $0.tournamentID == tournament.id
          && round($0, contains: contender.id, tournament: tournament)
      })
    {
      return currentRound
    }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id
          && $0.status != .completed
          && round($0, contains: contender.id, tournament: tournament)
      }
      .sorted {
        if $0.ordinal == $1.ordinal { return $0.id < $1.id }
        return $0.ordinal < $1.ordinal
      }
      .first
  }

  private static func tournamentPositionSort(
    lhs: ProductTournamentContender,
    rhs: ProductTournamentContender
  ) -> Bool {
    if lhs.title == rhs.title { return lhs.id < rhs.id }
    return lhs.title < rhs.title
  }

  private static func isActiveTournamentStatus(
    _ status: ProductTournamentContenderStatus
  ) -> Bool {
    switch status {
    case .competing, .narrowed, .needsRevision:
      return true
    case .eliminated, .winner, .archived:
      return false
    }
  }

  private static func activePlanRound(
    for contender: ProductTournamentContender,
    config: ProductTournamentConfig
  ) -> (tournament: ProductTournament, round: ProductTournamentRound)? {
    guard
      let tournament = config.tournaments.first(where: {
        $0.id == contender.tournamentID && ($0.status == .active || $0.status == .drafting)
      })
    else { return nil }
    if let currentRoundID = tournament.currentRoundID,
      let current = config.tournamentRounds.first(where: {
        $0.id == currentRoundID
          && $0.tournamentID == tournament.id
          && $0.kind == .productPlans
          && $0.status != .completed
      }),
      round(current, contains: contender.id, tournament: tournament)
    {
      return (tournament, current)
    }
    let fallback = config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id
          && $0.kind == .productPlans
          && $0.status != .completed
          && round($0, contains: contender.id, tournament: tournament)
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
        return lhs.ordinal < rhs.ordinal
      }
      .first
    return fallback.map { (tournament, $0) }
  }

  private static func round(
    _ round: ProductTournamentRound,
    contains contenderID: String,
    tournament: ProductTournament
  ) -> Bool {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.contains(contenderID)
  }

  private static func isPlanProofEligible(_ status: ProductTournamentContenderStatus) -> Bool {
    status == .competing || status == .narrowed || status == .needsRevision
  }

  private static func label(
    readiness: ProductTournamentReadiness,
    action: ProductTournamentNextAction?
  ) -> String {
    if readiness.proofDebt.failedRunCount > 0 {
      return "repair failed evidence"
    }
    if action?.targetScenarioID != nil {
      let targetsCurrentAlternative =
        readiness.proofDebt.personaModelCurrentAlternativeDeficit > 0
        && action?.title.localizedCaseInsensitiveContains("alternative") == true
      switch action?.targetDecision {
      case .promote:
        return targetsCurrentAlternative
          ? "run persona-model alternative validation proof"
          : "run targeted persona-model validation proof"
      case .kill:
        return targetsCurrentAlternative
          ? "run persona-model alternative rejection proof"
          : "run targeted persona-model rejection proof"
      case .notRun, .keepGoing, .narrow, .pivot, .archived, .promoted, nil:
        return targetsCurrentAlternative
          ? "run targeted persona-model alternative proof"
          : "run targeted persona-model simulated-user proof"
      }
    }
    if action?.requiredSimulationMode == .personaModel {
      switch action?.targetDecision {
      case .promote:
        return "add or enable persona-model validation proof"
      case .kill:
        return "add or enable persona-model rejection proof"
      case .notRun, .keepGoing, .narrow, .pivot, .archived, .promoted, nil:
        break
      }
      return "add or enable runnable persona-model proof"
    }
    if readiness.proofDebt.completedRunDeficit > 0 || readiness.proofDebt.personaDeficit > 0 {
      return "broaden completed persona coverage"
    }
    if readiness.proofDebt.personaModelCurrentAlternativeDeficit > 0 {
      return "add persona-model current-alternative proof"
    }
    return "close remaining tournament proof debt"
  }
}

enum TournamentAutomationExperimentRanker {
  static func rankedExperiments(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentExperiment] {
    let signals = Dictionary(
      uniqueKeysWithValues: experimentSignals(
        config: config,
        evidenceIndex: evidenceIndex
      ).map { ($0.experimentID, $0) }
    )
    return config.tournamentExperiments.sorted { lhs, rhs in
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
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [TournamentAutomationExperimentSignal] {
    config.tournamentExperiments.map {
      signal(for: $0, config: config, evidenceIndex: evidenceIndex)
    }
  }

  static func signal(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationExperimentSignal {
    let readiness = evidenceIndex.currentTournamentReadiness(for: experiment)
    let nextAction = ProductTournamentNextActionAdvisor.nextAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let planProofTarget =
      evidenceIndex.summaries.isEmpty && readiness == nil
      ? TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
      : nil
    let planProofNextActionKind: ProductTournamentNextActionKind? =
      planProofTarget?.contenderID == nil ? nil : .runPlanProof
    let effectiveNextActionKind = planProofNextActionKind ?? nextAction?.kind
    let effectiveNextActionTitle = planProofTarget?.nextActionTitle ?? nextAction?.title
    let effectiveNextActionPriority =
      planProofTarget?.nextActionPriority ?? nextAction?.priority ?? 0
    return TournamentAutomationExperimentSignal(
      experimentID: experiment.id,
      readinessScore: readiness.map { Int($0.readinessScore.rounded()) },
      readinessRecommendation: readiness?.recommendation,
      nextActionKind: effectiveNextActionKind,
      nextActionTitle: effectiveNextActionTitle,
      nextActionPriority: effectiveNextActionPriority,
      targetDecision: nextAction?.targetDecision,
      pressure: pressure(
        for: experiment,
        readiness: readiness,
        nextActionKind: effectiveNextActionKind,
        targetDecision: nextAction?.targetDecision
      ),
      staleEvidenceCount: evidenceIndex.staleSummaryCount(for: experiment),
      proofDebtCount: readiness?.proofDebt.blockingDebtCount
        ?? planProofBlockingDebtCount(planProofTarget)
        ?? 0,
      proofDebtSummary: readiness?.proofDebt.isClear == false
        ? readiness?.proofDebt.summary
        : planProofTarget?.debtSummary
    )
  }

  private static func pressure(
    for experiment: ProductTournamentExperiment,
    readiness: ProductTournamentReadiness?,
    nextActionKind: ProductTournamentNextActionKind?,
    targetDecision: ProductTournamentExperimentDecision?
  ) -> TournamentAutomationPortfolioPressure {
    if nextActionKind == .repairFailures {
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
    switch targetDecision {
    case .promote:
      return .lift
    case .kill:
      return .cut
    case .notRun, .keepGoing, .narrow, .pivot, .archived, .promoted, nil:
      break
    }
    switch nextActionKind {
    case .applyDecision, .applyRoundTransition:
      switch readiness?.recommendation {
      case .promote: return .lift
      case .kill: return .cut
      case .pivot, .narrow: return .reshape
      case .gatherEvidence, .keepGoing, nil: return .learn
      }
    case .prepareWorktree, .runPlanProof:
      return .learn
    case .runCohort, .rerunCohort:
      return .learn
    case .refineContender, .reviewDecision:
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

  private static func planProofBlockingDebtCount(
    _ target: TournamentAutomationProofTarget?
  ) -> Int? {
    guard let target, target.contenderID != nil else { return nil }
    let matches = target.debtSummary.matches(of: #/\d+/#)
    let total = matches.compactMap { Int($0.output) }.reduce(0, +)
    return total > 0 ? total : 1
  }
}

enum TournamentAutomationStepKind: String, Equatable, Sendable {
  case applyDecision = "apply_decision"
  case applyRoundTransition = "apply_round_transition"
  case prepareWorktree = "prepare_worktree"
  case runPlanProof = "run_plan_proof"
  case runCohort = "run_cohort"
  case applyRevision = "apply_revision"
  case blocked = "blocked"
}

struct TournamentAutomationStep: Equatable, Sendable, Identifiable {
  var id: String {
    "\(experimentID):\(idKind):\(idTarget)\(idDecisionSuffix)"
  }

  var experimentID: String
  var experimentTitle: String
  var kind: TournamentAutomationStepKind
  var action: ProductTournamentNextAction
  var cohortReadiness: ProductTournamentCohortRunReadiness?
  var canExecute: Bool
  var blockedReason: String?

  var cohortID: String? { action.cohortID }
  var targetScenarioID: String? { action.targetScenarioID }

  var tournamentID: String? { action.tournamentID }
  var roundID: String? { action.roundID }
  var contenderID: String? { action.contenderID }

  var decisionIntentSummary: String? {
    guard let targetDecision = action.targetDecision else { return nil }
    return "decision target \(targetDecision.rawValue)"
  }

  var queueTitle: String {
    guard let decisionIntentSummary else { return title }
    return "\(title) (\(decisionIntentSummary))"
  }

  private var idDecisionSuffix: String {
    action.targetDecision.map { ":target_decision:\($0.rawValue)" } ?? ""
  }

  private var idKind: String {
    switch kind {
    case .applyRevision:
      return TournamentAutomationStepKind.applyRevision.rawValue
    case .applyDecision, .applyRoundTransition, .prepareWorktree, .runPlanProof, .runCohort,
      .blocked:
      return action.kind.rawValue
    }
  }

  private var idTarget: String {
    targetScenarioID ?? cohortID ?? contenderID ?? roundID ?? "none"
  }

  var title: String {
    switch kind {
    case .applyDecision:
      return "Apply tournament decision"
    case .applyRoundTransition:
      return action.title
    case .prepareWorktree:
      return action.title
    case .runPlanProof:
      return action.title
    case .runCohort:
      return action.kind == .rerunCohort ? "Rerun evidence cohort" : "Run evidence cohort"
    case .applyRevision:
      return "Apply contender revision"
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
    experiment: ProductTournamentExperiment,
    action: ProductTournamentNextAction,
    cohortReadiness: ProductTournamentCohortRunReadiness?,
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
    case .applyRoundTransition:
      self.kind = .applyRoundTransition
      self.canExecute =
        action.tournamentID != nil && action.roundID != nil
        && action.contenderID != nil
      self.blockedReason =
        self.canExecute
        ? nil
        : "Tournament round transition is missing tournament, round, or contender scope."
    case .prepareWorktree:
      self.kind = .prepareWorktree
      self.canExecute = true
      self.blockedReason = nil
    case .runPlanProof:
      self.kind = .runPlanProof
      let modeBlockedReason = Self.simulationModeBlockedReason(
        for: action,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
      self.canExecute =
        action.tournamentID != nil && action.roundID != nil
        && action.contenderID != nil && modeBlockedReason == nil
      self.blockedReason =
        self.canExecute
        ? nil
        : modeBlockedReason
          ?? "Round 1 plan-proof target is missing tournament, round, or contender scope."
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
      self.blockedReason =
        action.detail.isEmpty
        ? "Repair failed evidence runs before Tournament Automation can continue."
        : action.detail
    case .refineContender:
      self.kind = .blocked
      self.canExecute = false
      self.blockedReason =
        action.detail.isEmpty
        ? "Refine the product contender before Tournament Automation can run more evidence."
        : action.detail
    case .reviewDecision:
      self.kind = .blocked
      self.canExecute = false
      self.blockedReason = "Review the decision path before Tournament Automation changes state."
    }
  }

  private static func simulationModeBlockedReason(
    for action: ProductTournamentNextAction,
    isPersonaModelAvailable: Bool
  ) -> String? {
    guard action.requiredSimulationMode == .personaModel, !isPersonaModelAvailable else {
      return nil
    }
    return "persona-model validation requires Foundation Models before this step can run."
  }
}

struct TournamentAutomationCyclePlan: Equatable, Sendable {
  var executableSteps: [TournamentAutomationStep]
  var blockedSteps: [TournamentAutomationStep]
  var maxSteps: Int
  var capped: Bool
  var refreshesQueueAfterStateChange: Bool

  var canRun: Bool { !executableSteps.isEmpty }

  var nextBlockedStep: TournamentAutomationStep? {
    blockedSteps.first
  }

  var summary: String {
    if executableSteps.isEmpty {
      if let nextBlockedStep {
        return
          "No executable tournament automation steps; next blocked action is \(nextBlockedStep.title)."
      }
      return "No tournament automation action queued."
    }
    let cappedText = capped ? ", capped at \(maxSteps)" : ""
    let refreshText =
      refreshesQueueAfterStateChange
      ? " Queue refreshes after state-changing steps."
      : ""
    return "\(executableSteps.count) executable tournament automation step(s)\(cappedText).\(refreshText)"
  }

  var queueSummary: String {
    if executableSteps.isEmpty {
      if let nextBlockedStep {
        return
          "Blocked: \(nextBlockedStep.experimentTitle): \(nextBlockedStep.queueTitle) - \(nextBlockedStep.detail)"
      }
      return "No tournament automation action queued."
    }
    let queued =
      executableSteps
      .map { "\($0.experimentTitle): \($0.queueTitle)" }
      .joined(separator: " -> ")
    let refreshText =
      refreshesQueueAfterStateChange
      ? " -> refresh queue for newly unblocked evidence"
      : ""
    return capped ? "\(queued)\(refreshText) -> plus more queued" : "\(queued)\(refreshText)"
  }

  init(
    executableSteps: [TournamentAutomationStep],
    blockedSteps: [TournamentAutomationStep],
    maxSteps: Int,
    capped: Bool,
    refreshesQueueAfterStateChange: Bool = false
  ) {
    self.executableSteps = executableSteps
    self.blockedSteps = blockedSteps
    self.maxSteps = max(1, maxSteps)
    self.capped = capped
    self.refreshesQueueAfterStateChange =
      refreshesQueueAfterStateChange && self.maxSteps > 1 && !executableSteps.isEmpty
  }
}

enum TournamentAutomationCycleStopReason: Equatable, Sendable {
  case reachedStepLimit
  case noExecutableStep
  case repeatedStep(stepID: String, title: String)
  case executionFailed(stepID: String, title: String, message: String?)
}

struct TournamentAutomationStepResult: Equatable, Sendable {
  var message: String
  var executedStepID: String?
  var targetScenarioID: String?
  var evidenceRunIDs: [String]
  var completedEvidenceRunCount: Int
  var failedEvidenceRunCount: Int
  var skippedScenarioCount: Int

  init(
    message: String,
    executedStepID: String? = nil,
    targetScenarioID: String? = nil,
    evidenceRunIDs: [String] = [],
    completedEvidenceRunCount: Int = 0,
    failedEvidenceRunCount: Int = 0,
    skippedScenarioCount: Int = 0
  ) {
    self.message = ProductTournamentModelText.cleanedText(
      message,
      fallback: "Tournament automation step completed.",
      limit: 1_200
    )
    self.executedStepID = ProductTournamentModelText.optionalCleanedText(
      executedStepID,
      limit: 240
    )
    self.targetScenarioID = ProductTournamentModelText.optionalIdentifier(
      targetScenarioID,
      fallback: "scenario"
    )
    self.evidenceRunIDs = ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
  }
}

struct TournamentAutomationCycleOutcome: Equatable, Sendable {
  var executedSteps: [TournamentAutomationStep]
  var executedStepIDs: [String]
  var messages: [String]
  var maxSteps: Int
  var stopReason: TournamentAutomationCycleStopReason
  var evidenceRunIDs: [String]
  var completedEvidenceRunCount: Int
  var failedEvidenceRunCount: Int
  var skippedScenarioCount: Int
  var startingProofDebtCount: Int?
  var endingProofDebtCount: Int?
  var startingProofDebtSummary: String?
  var endingProofDebtSummary: String?
  var startingPersonaModelPlanEvaluationCount: Int?
  var endingPersonaModelPlanEvaluationCount: Int?
  var startingModelFreePlanEvaluationCount: Int?
  var endingModelFreePlanEvaluationCount: Int?
  var decisionCandidateSummaries: [String]
  var evidenceTensionSummaries: [String]
  var proofTargetSummaries: [String]
  var actedProofPressureGroupSummaries: [String]
  var targetedProofOutcomeSummaries: [String]
  var personaRationaleSignalSummaries: [String]
  var revisionBriefSummaries: [String]

  init(
    executedSteps: [TournamentAutomationStep],
    executedStepIDs: [String] = [],
    messages: [String],
    maxSteps: Int,
    stopReason: TournamentAutomationCycleStopReason,
    evidenceRunIDs: [String] = [],
    completedEvidenceRunCount: Int = 0,
    failedEvidenceRunCount: Int = 0,
    skippedScenarioCount: Int = 0,
    startingProofDebtCount: Int? = nil,
    endingProofDebtCount: Int? = nil,
    startingProofDebtSummary: String? = nil,
    endingProofDebtSummary: String? = nil,
    startingPersonaModelPlanEvaluationCount: Int? = nil,
    endingPersonaModelPlanEvaluationCount: Int? = nil,
    startingModelFreePlanEvaluationCount: Int? = nil,
    endingModelFreePlanEvaluationCount: Int? = nil,
    decisionCandidateSummaries: [String] = [],
    evidenceTensionSummaries: [String] = [],
    proofTargetSummaries: [String] = [],
    actedProofPressureGroupSummaries: [String] = [],
    targetedProofOutcomeSummaries: [String] = [],
    personaRationaleSignalSummaries: [String] = [],
    revisionBriefSummaries: [String] = []
  ) {
    self.executedSteps = executedSteps
    self.executedStepIDs = ProductTournamentModelText.cleanedList(
      executedStepIDs.isEmpty ? executedSteps.map(\.id) : executedStepIDs,
      limit: 260
    )
    self.messages = ProductTournamentModelText.cleanedList(messages, limit: 500)
    self.maxSteps = max(1, maxSteps)
    self.stopReason = stopReason
    self.evidenceRunIDs = ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
    self.startingProofDebtCount = startingProofDebtCount.map { max(0, $0) }
    self.endingProofDebtCount = endingProofDebtCount.map { max(0, $0) }
    self.startingProofDebtSummary = ProductTournamentModelText.optionalCleanedText(
      startingProofDebtSummary,
      limit: 500
    )
    self.endingProofDebtSummary = ProductTournamentModelText.optionalCleanedText(
      endingProofDebtSummary,
      limit: 500
    )
    self.startingPersonaModelPlanEvaluationCount =
      startingPersonaModelPlanEvaluationCount.map { max(0, $0) }
    self.endingPersonaModelPlanEvaluationCount =
      endingPersonaModelPlanEvaluationCount.map { max(0, $0) }
    self.startingModelFreePlanEvaluationCount =
      startingModelFreePlanEvaluationCount.map { max(0, $0) }
    self.endingModelFreePlanEvaluationCount =
      endingModelFreePlanEvaluationCount.map { max(0, $0) }
    self.decisionCandidateSummaries = ProductTournamentModelText.cleanedList(
      decisionCandidateSummaries,
      limit: 300
    )
    self.evidenceTensionSummaries = ProductTournamentModelText.cleanedList(
      evidenceTensionSummaries,
      limit: 360
    )
    self.proofTargetSummaries = ProductTournamentModelText.cleanedList(
      proofTargetSummaries,
      limit: 360
    )
    self.actedProofPressureGroupSummaries = ProductTournamentModelText.cleanedList(
      actedProofPressureGroupSummaries,
      limit: 360
    )
    self.targetedProofOutcomeSummaries = ProductTournamentModelText.cleanedList(
      targetedProofOutcomeSummaries,
      limit: 360
    )
    self.personaRationaleSignalSummaries = ProductTournamentModelText.cleanedList(
      personaRationaleSignalSummaries,
      limit: 360
    )
    self.revisionBriefSummaries = ProductTournamentModelText.cleanedList(
      revisionBriefSummaries,
      limit: 700
    )
  }

  var appliedDecisionCount: Int {
    executedSteps.filter { $0.action.kind == .applyDecision }.count
  }

  var appliedRoundTransitionCount: Int {
    executedSteps.filter { $0.action.kind == .applyRoundTransition }.count
  }

  var promotedDecisionCount: Int {
    executedSteps.filter {
      $0.action.kind == .applyDecision && $0.action.targetDecision == .promote
    }.count
  }

  var killedDecisionCount: Int {
    executedSteps.filter {
      $0.action.kind == .applyDecision && $0.action.targetDecision == .kill
    }.count
  }

  var targetedPromoteProofCount: Int {
    executedSteps.filter {
      $0.action.kind != .applyDecision && $0.action.targetDecision == .promote
    }.count
  }

  var targetedKillProofCount: Int {
    executedSteps.filter {
      $0.action.kind != .applyDecision && $0.action.targetDecision == .kill
    }.count
  }

  var prepareWorktreeStepCount: Int {
    executedSteps.filter { $0.action.kind == .prepareWorktree }.count
  }

  var evidenceRunStepCount: Int {
    executedSteps.filter {
      $0.action.kind == .runPlanProof || $0.action.kind == .runCohort
        || $0.action.kind == .rerunCohort
    }.count
  }

  var proofDebtDelta: Int? {
    guard let startingProofDebtCount, let endingProofDebtCount else { return nil }
    return endingProofDebtCount - startingProofDebtCount
  }

  var userMessage: String {
    var parts = [
      executedSteps.isEmpty
        ? "Tournament automation cycle ran no steps."
        : "Tournament automation cycle ran \(executedSteps.count) step(s)."
    ]
    if let outcomeMessage {
      parts.append(outcomeMessage)
    }
    if !messages.isEmpty {
      parts.append(messages.joined(separator: " "))
    }
    if let proofDebtMessage {
      parts.append(proofDebtMessage)
    }
    if let planEvaluationModeMessage {
      parts.append(planEvaluationModeMessage)
    }
    parts.append(stopReasonMessage)
    if let decisionCandidateMessage {
      parts.append(decisionCandidateMessage)
    }
    if let evidenceTensionMessage {
      parts.append(evidenceTensionMessage)
    }
    if let proofTargetMessage {
      parts.append(proofTargetMessage)
    }
    if let actedPressureGroupMessage {
      parts.append(actedPressureGroupMessage)
    }
    if let targetedProofOutcomeMessage {
      parts.append(targetedProofOutcomeMessage)
    }
    if let personaRationaleSignalMessage {
      parts.append(personaRationaleSignalMessage)
    }
    if let revisionBriefMessage {
      parts.append(revisionBriefMessage)
    }
    return parts.joined(separator: " ")
  }

  var auditStopReason: TournamentAutomationCycleAuditStopReason {
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
  ) -> TournamentAutomationCycleAudit {
    let started = startedAt.timeIntervalSince1970
    let ended = endedAt.timeIntervalSince1970
    var experimentIDs: [String] = []
    for step in executedSteps where !experimentIDs.contains(step.experimentID) {
      experimentIDs.append(step.experimentID)
    }
    return TournamentAutomationCycleAudit(
      id: "tournament-cycle-\(Int(started))-\(Int(ended))-\(executedSteps.count)",
      startedAt: started,
      endedAt: ended,
      executedStepIDs: executedStepIDs,
      experimentIDs: experimentIDs,
      messages: messages,
      maxSteps: maxSteps,
      appliedDecisionCount: appliedDecisionCount,
      appliedRoundTransitionCount: appliedRoundTransitionCount,
      promotedDecisionCount: promotedDecisionCount,
      killedDecisionCount: killedDecisionCount,
      targetedPromoteProofCount: targetedPromoteProofCount,
      targetedKillProofCount: targetedKillProofCount,
      prepareWorktreeStepCount: prepareWorktreeStepCount,
      evidenceRunStepCount: evidenceRunStepCount,
      evidenceRunIDs: evidenceRunIDs,
      completedEvidenceRunCount: completedEvidenceRunCount,
      failedEvidenceRunCount: failedEvidenceRunCount,
      skippedScenarioCount: skippedScenarioCount,
      startingProofDebtCount: startingProofDebtCount,
      endingProofDebtCount: endingProofDebtCount,
      startingProofDebtSummary: startingProofDebtSummary,
      endingProofDebtSummary: endingProofDebtSummary,
      startingPersonaModelPlanEvaluationCount: startingPersonaModelPlanEvaluationCount,
      endingPersonaModelPlanEvaluationCount: endingPersonaModelPlanEvaluationCount,
      startingModelFreePlanEvaluationCount: startingModelFreePlanEvaluationCount,
      endingModelFreePlanEvaluationCount: endingModelFreePlanEvaluationCount,
      decisionCandidateSummaries: decisionCandidateSummaries,
      evidenceTensionSummaries: evidenceTensionSummaries,
      proofTargetSummaries: proofTargetSummaries,
      actedProofPressureGroupSummaries: actedProofPressureGroupSummaries,
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      personaRationaleSignalSummaries: personaRationaleSignalSummaries,
      revisionBriefSummaries: revisionBriefSummaries,
      stopReason: auditStopReason,
      stopStepID: stopStepID,
      stopStepTitle: stopStepTitle,
      stopDetail: stopDetail,
      userMessage: userMessage
    )
  }

  private var outcomeMessage: String? {
    guard
      appliedDecisionCount > 0 || appliedRoundTransitionCount > 0
        || prepareWorktreeStepCount > 0 || evidenceRunStepCount > 0 || hasEvidenceRunOutcomes
    else { return nil }
    let evidenceOutcome =
      hasEvidenceRunOutcomes
      ? ", evidence runs \(completedEvidenceRunCount) completed, \(failedEvidenceRunCount) needing review, \(skippedScenarioCount) skipped"
      : ""
    let targetedProofCount = targetedPromoteProofCount + targetedKillProofCount
    let targetedProof =
      targetedProofCount > 0
      ? ", targeted proof \(targetedPromoteProofCount) promote, \(targetedKillProofCount) kill"
      : ""
    let worktreePrep =
      prepareWorktreeStepCount > 0
      ? ", \(prepareWorktreeStepCount) worktree prepare step(s)"
      : ""
    return
      "Cycle outcomes: \(appliedDecisionCount) tournament decision(s) applied (\(promotedDecisionCount) promote, \(killedDecisionCount) kill), \(appliedRoundTransitionCount) round transition(s) applied\(worktreePrep), \(evidenceRunStepCount) evidence step(s)\(targetedProof)\(evidenceOutcome)."
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

  private var actedPressureGroupMessage: String? {
    guard !actedProofPressureGroupSummaries.isEmpty else { return nil }
    let groups = actedProofPressureGroupSummaries.prefix(3).joined(separator: " | ")
    return "Acted pressure groups: \(StringUtils.boundedText(groups, limit: 360))."
  }

  private var targetedProofOutcomeMessage: String? {
    guard !targetedProofOutcomeSummaries.isEmpty else { return nil }
    let outcomes = targetedProofOutcomeSummaries.prefix(3).joined(separator: " | ")
    return "Targeted proof outcomes: \(StringUtils.boundedText(outcomes, limit: 420))."
  }

  private var personaRationaleSignalMessage: String? {
    guard !personaRationaleSignalSummaries.isEmpty else { return nil }
    let signals = personaRationaleSignalSummaries.prefix(3).joined(separator: " | ")
    return "simulated-user rationale signals: \(StringUtils.boundedText(signals, limit: 420))."
  }

  private var revisionBriefMessage: String? {
    guard !revisionBriefSummaries.isEmpty else { return nil }
    let briefs = revisionBriefSummaries.prefix(3).joined(separator: " | ")
    return "Contender revisions: \(StringUtils.boundedText(briefs, limit: 420))."
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

  private var planEvaluationModeMessage: String? {
    guard hasPlanEvaluationModeCounts else { return nil }
    return
      "Plan evidence modes: persona-model \(startingPersonaModelPlanEvaluationCount ?? 0) -> \(endingPersonaModelPlanEvaluationCount ?? 0), model-free \(startingModelFreePlanEvaluationCount ?? 0) -> \(endingModelFreePlanEvaluationCount ?? 0)."
  }

  private var hasPlanEvaluationModeCounts: Bool {
    startingPersonaModelPlanEvaluationCount != nil
      || endingPersonaModelPlanEvaluationCount != nil
      || startingModelFreePlanEvaluationCount != nil
      || endingModelFreePlanEvaluationCount != nil
  }

  private var stopReasonMessage: String {
    switch stopReason {
    case .reachedStepLimit:
      return "Stopped after reaching the \(max(1, maxSteps))-step cycle limit."
    case .noExecutableStep:
      return "Stopped because no executable tournament automation step remains."
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

struct TournamentAutomationProofDebtSnapshot: Equatable, Sendable {
  var count: Int
  var summary: String
  var personaModelPlanEvaluationCount: Int
  var modelFreePlanEvaluationCount: Int

  init(
    count: Int,
    summary: String,
    personaModelPlanEvaluationCount: Int = 0,
    modelFreePlanEvaluationCount: Int = 0
  ) {
    self.count = max(0, count)
    self.summary = ProductTournamentModelText.cleanedText(
      summary,
      fallback: "Proof debt unavailable.",
      limit: 500
    )
    self.personaModelPlanEvaluationCount = max(0, personaModelPlanEvaluationCount)
    self.modelFreePlanEvaluationCount = max(0, modelFreePlanEvaluationCount)
  }
}

enum TournamentAutomationProofDebtSnapshotter {
  static func snapshot(
    experimentIDs: [String],
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    storedSnapshots: [String: TournamentAutomationProofDebtSnapshot] = [:],
    preferredSteps: [String: TournamentAutomationStep] = [:]
  ) -> TournamentAutomationProofDebtSnapshot? {
    var orderedExperimentIDs: [String] = []
    for experimentID in experimentIDs where !orderedExperimentIDs.contains(experimentID) {
      orderedExperimentIDs.append(experimentID)
    }

    var total = 0
    var personaModelPlanEvaluationCount = 0
    var modelFreePlanEvaluationCount = 0
    var parts: [String] = []
    for experimentID in orderedExperimentIDs {
      guard
        let snapshot = storedSnapshots[experimentID]
          ?? snapshot(
            forExperimentID: experimentID,
            config: config,
            evidenceIndex: evidenceIndex,
            preferredStep: preferredSteps[experimentID]
          )
      else { continue }
      total += snapshot.count
      personaModelPlanEvaluationCount += snapshot.personaModelPlanEvaluationCount
      modelFreePlanEvaluationCount += snapshot.modelFreePlanEvaluationCount
      parts.append(snapshot.summary)
    }

    guard !parts.isEmpty else { return nil }
    return TournamentAutomationProofDebtSnapshot(
      count: total,
      summary: parts.joined(separator: "; "),
      personaModelPlanEvaluationCount: personaModelPlanEvaluationCount,
      modelFreePlanEvaluationCount: modelFreePlanEvaluationCount
    )
  }

  static func snapshot(
    forExperimentID experimentID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    preferredStep: TournamentAutomationStep? = nil
  ) -> TournamentAutomationProofDebtSnapshot? {
    guard
      let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
    else { return nil }

    if let preferredStep,
      let planSnapshot = planProofSnapshot(
        for: experiment,
        tournamentID: preferredStep.tournamentID,
        roundID: preferredStep.roundID,
        contenderID: preferredStep.contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      return planSnapshot
    }

    if let readiness = evidenceIndex.currentTournamentReadiness(for: experiment) {
      return tournamentExperienceSnapshot(for: experiment, proofDebt: readiness.proofDebt)
    }

    if let target = TournamentAutomationProofTargetAdvisor.target(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ),
      let planSnapshot = planProofSnapshot(
        for: experiment,
        tournamentID: target.tournamentID,
        roundID: target.roundID,
        contenderID: target.contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      return planSnapshot
    }

    return tournamentExperienceSnapshot(
      for: experiment,
      proofDebt: ProductTournamentProofDebt(
        completedRunCount: 0,
        distinctPersonaCount: 0,
        personaModelDistinctPersonaCount: 0,
        personaModelCurrentAlternativePersonaCount: 0,
        failedRunCount: 0
      )
    )
  }

  private static func tournamentExperienceSnapshot(
    for experiment: ProductTournamentExperiment,
    proofDebt: ProductTournamentProofDebt
  ) -> TournamentAutomationProofDebtSnapshot {
    TournamentAutomationProofDebtSnapshot(
      count: proofDebt.blockingDebtCount,
      summary: "\(experiment.id): \(proofDebt.summary)"
    )
  }

  private static func planProofSnapshot(
    for experiment: ProductTournamentExperiment,
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationProofDebtSnapshot? {
    guard
      let tournamentID,
      let roundID,
      let contenderID,
      let tournament = config.tournaments.first(where: { $0.id == tournamentID }),
      let round = config.tournamentRounds.first(where: {
        $0.id == roundID && $0.tournamentID == tournament.id && $0.kind == .productPlans
      }),
      let contender = config.tournamentContenders.first(where: {
        $0.id == contenderID && $0.tournamentID == tournament.id
          && $0.experimentID == experiment.id
      })
    else { return nil }

    let completed = evidenceIndex.planEvaluations(for: tournament, round: round)
      .filter { $0.contenderID == contender.id && $0.isCompleted }
    let readiness = ProductTournamentPlanReadiness(summaries: completed)
    let proofDebt = readiness.planProofDebt
    return TournamentAutomationProofDebtSnapshot(
      count: proofDebt.blockingDebtCount,
      summary:
        "\(experiment.id): contender \(contender.id) Round \(round.ordinal) plan proof \(proofDebt.summary)",
      personaModelPlanEvaluationCount: readiness.personaModelEvaluationCount,
      modelFreePlanEvaluationCount: readiness.modelFreeEvaluationCount
    )
  }
}

enum TournamentAutomationCycleFailureAdvisor {
  static func stepID(for action: ProductTournamentNextAction) -> String {
    let decisionSuffix = action.targetDecision.map { ":target_decision:\($0.rawValue)" } ?? ""
    return
      "\(action.experimentID):\(action.kind.rawValue):\(action.targetScenarioID ?? action.cohortID ?? "none")\(decisionSuffix)"
  }

  static func blockingAudit(
    forStepID stepID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard let audit = recentExecutionFailureAudit(forStepID: stepID, config: config),
      !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
    else { return nil }
    return audit
  }

  private static func recentExecutionFailureAudit(
    forStepID stepID: String,
    config: ProductTournamentConfig
  ) -> TournamentAutomationCycleAudit? {
    config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first {
        $0.stopReason == .executionFailed
          && $0.stopStepID.map { stepIDsMatch($0, stepID) } == true
      }
  }

  private static func stepIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
    lhs == rhs || lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
  }

  private static func hasCompletedEvidence(
    after audit: TournamentAutomationCycleAudit,
    for experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> Bool {
    evidenceIndex.summaries(for: experiment).contains {
      $0.isCompleted && $0.endedAt > audit.endedAt
    }
  }
}

enum TournamentAutomationCycleLearningAdvisor {
  static func stalledProofDebtAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard isBroadCohortAction(action) else { return nil }
    let broadStepIDs = broadCohortStepIDs(for: action)
    return config.tournamentAutomationCycleAudits
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
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard isTargetedProofAction(action) else { return nil }
    let stepID = TournamentAutomationCycleFailureAdvisor.stepID(for: action)
    let currentTarget = TournamentAutomationProofTargetAdvisor.target(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return config.tournamentAutomationCycleAudits
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

  static func stalledEvidenceTensionAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard isTargetedEvidenceTensionAction(action) else { return nil }
    let stepID = TournamentAutomationCycleFailureAdvisor.stepID(for: action)
    let currentTension = TournamentAutomationEvidenceTensionAdvisor.tension(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return config.tournamentAutomationCycleAudits
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
          matchesExecutedStepID(stepID, audit: audit),
          !audit.evidenceTensionSummaries.isEmpty,
          matchesCurrentEvidenceTension(
            audit: audit,
            action: action,
            tension: currentTension
          ),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func stalledRationaleSignalAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard isTargetedRationaleSignalAction(action) else { return nil }
    let stepIDs = targetedScenarioStepIDs(for: action)
    let currentSignal = TournamentAutomationRationaleSignalAdvisor.signal(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return config.tournamentAutomationCycleAudits
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
          matchesAnyExecutedStepID(stepIDs, audit: audit),
          !audit.personaRationaleSignalSummaries.isEmpty,
          matchesCurrentRationaleSignal(
            audit: audit,
            action: action,
            signal: currentSignal
          ),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func stalledTargetedProofOutcomeAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard action.kind == .runCohort || action.kind == .rerunCohort,
      action.targetScenarioID != nil,
      action.requiredSimulationMode == .personaModel,
      let currentSignal = TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      currentSignal.title == action.title
        || action.title == "Validate targeted tournament proof revision"
    else { return nil }
    let stepIDs = targetedScenarioStepIDs(for: action)
    return config.tournamentAutomationCycleAudits
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
          matchesAnyExecutedStepID(stepIDs, audit: audit),
          !audit.targetedProofOutcomeSummaries.isEmpty,
          matchesCurrentTargetedProofOutcome(
            audit: audit,
            action: action,
            signal: currentSignal
          ),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func revisionFatigueAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard isTargetedRationaleSignalAction(action) else { return nil }
    let stepIDs = targetedScenarioStepIDs(for: action)
    let currentSignal = TournamentAutomationRationaleSignalAdvisor.signal(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let recentAudits = Array(
      config.tournamentAutomationCycleAudits
        .sorted { lhs, rhs in
          if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
          return lhs.endedAt > rhs.endedAt
        }
        .prefix(8)
    )
    let matchingValidationAudits = recentAudits.filter { audit in
      guard audit.stopReason != .executionFailed,
        audit.experimentIDs.contains(experiment.id),
        audit.evidenceRunStepCount > 0,
        audit.completedEvidenceRunCount > 0,
        matchesAnyExecutedStepID(stepIDs, audit: audit),
        !audit.personaRationaleSignalSummaries.isEmpty,
        matchesCurrentRationaleSignal(
          audit: audit,
          action: action,
          signal: currentSignal
        ),
        isRevisionValidationAudit(
          audit,
          recentAudits: recentAudits,
          action: action,
          experiment: experiment
        )
      else { return false }
      return true
    }
    guard matchingValidationAudits.count >= 2,
      let latestAudit = matchingValidationAudits.first,
      !hasCompletedEvidence(after: latestAudit, for: experiment, evidenceIndex: evidenceIndex)
    else { return nil }
    return latestAudit
  }

  static func appliedTargetedProofOutcomeRevisionAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard action.kind == .refineContender,
      let currentSignal = TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return nil }
    return config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first { audit in
        guard audit.stopReason != .executionFailed,
          audit.experimentIDs.contains(experiment.id),
          matchesCurrentTargetedProofOutcomeRevision(
            audit: audit,
            action: action,
            signal: currentSignal
          ),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func appliedRevisionBriefAudit(
    for brief: TournamentAutomationRevisionBrief,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first { audit in
        guard audit.stopReason != .executionFailed,
          audit.experimentIDs.contains(experiment.id),
          !audit.revisionBriefSummaries.isEmpty,
          matchesCurrentRevisionBrief(audit: audit, brief: brief),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  static func appliedRevisionBriefAudit(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationCycleAudit? {
    guard action.targetScenarioID != nil || action.targetPersonaName != nil else {
      return nil
    }
    return config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(5)
      .first { audit in
        guard audit.stopReason != .executionFailed,
          audit.experimentIDs.contains(experiment.id),
          !audit.revisionBriefSummaries.isEmpty,
          matchesCurrentRevisionBrief(audit: audit, action: action),
          !hasCompletedEvidence(after: audit, for: experiment, evidenceIndex: evidenceIndex)
        else { return false }
        return true
      }
  }

  private static func isRevisionValidationAudit(
    _ audit: TournamentAutomationCycleAudit,
    recentAudits: [TournamentAutomationCycleAudit],
    action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment
  ) -> Bool {
    if !audit.revisionBriefSummaries.isEmpty,
      matchesCurrentRevisionBrief(audit: audit, action: action)
    {
      return true
    }
    return recentAudits.contains { revisionAudit in
      guard revisionAudit.id != audit.id,
        revisionAudit.stopReason != .executionFailed,
        revisionAudit.experimentIDs.contains(experiment.id),
        revisionAudit.endedAt <= audit.endedAt,
        !revisionAudit.revisionBriefSummaries.isEmpty,
        matchesCurrentRevisionBrief(audit: revisionAudit, action: action)
      else { return false }
      return true
    }
  }

  private static func isBroadCohortAction(_ action: ProductTournamentNextAction) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.targetScenarioID == nil
      && action.cohortID != nil
  }

  private static func isTargetedProofAction(_ action: ProductTournamentNextAction) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.targetScenarioID != nil
      && action.requiredSimulationMode == .personaModel
  }

  private static func isTargetedEvidenceTensionAction(
    _ action: ProductTournamentNextAction
  ) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.title == "Resolve split tournament evidence"
      && action.targetScenarioID != nil
      && action.requiredSimulationMode == .personaModel
  }

  private static func isTargetedRationaleSignalAction(
    _ action: ProductTournamentNextAction
  ) -> Bool {
    (action.kind == .runCohort || action.kind == .rerunCohort)
      && action.title == "Resolve simulated-user rationale signal"
      && action.targetScenarioID != nil
      && action.requiredSimulationMode == .personaModel
  }

  private static func matchesExecutedStepID(
    _ stepID: String,
    audit: TournamentAutomationCycleAudit
  ) -> Bool {
    audit.executedStepIDs.contains { executedStepID in
      executedStepID == stepID
        || stepID.hasPrefix(executedStepID)
        || executedStepID.hasPrefix(stepID)
    }
  }

  private static func matchesAnyExecutedStepID(
    _ stepIDs: Set<String>,
    audit: TournamentAutomationCycleAudit
  ) -> Bool {
    stepIDs.contains { matchesExecutedStepID($0, audit: audit) }
  }

  private static func targetedScenarioStepIDs(
    for action: ProductTournamentNextAction
  ) -> Set<String> {
    guard let targetScenarioID = action.targetScenarioID else {
      return [TournamentAutomationCycleFailureAdvisor.stepID(for: action)]
    }
    return [
      "\(action.experimentID):\(ProductTournamentNextActionKind.runCohort.rawValue):\(targetScenarioID)",
      "\(action.experimentID):\(ProductTournamentNextActionKind.rerunCohort.rawValue):\(targetScenarioID)",
    ]
  }

  private static func matchesCurrentProofTarget(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction,
    target: TournamentAutomationProofTarget?
  ) -> Bool {
    audit.proofTargetSummaries.contains { summary in
      if let target {
        let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
        let personaMatches =
          action.targetPersonaName.map {
            summary.localizedCaseInsensitiveContains($0)
          } ?? true
        let decisionMatches =
          (action.targetDecision ?? target.targetDecision).map {
            summary.contains("target_decision \($0.rawValue)")
          } ?? true
        return summary.localizedCaseInsensitiveContains(target.label)
          && scenarioMatches
          && personaMatches
          && decisionMatches
      }
      return action.targetScenarioID.map { summary.contains($0) } ?? false
    }
  }

  private static func matchesCurrentEvidenceTension(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction,
    tension: TournamentAutomationEvidenceTension?
  ) -> Bool {
    audit.evidenceTensionSummaries.contains { summary in
      if let tension {
        let labelMatches = summary.localizedCaseInsensitiveContains(tension.label)
        let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
        let personaMatches =
          action.targetPersonaName.map {
            summary.localizedCaseInsensitiveContains($0)
          } ?? true
        let decisionMatches =
          (action.targetDecision ?? tension.targetDecision).map {
            summary.contains("target_decision \($0.rawValue)")
          } ?? true
        return labelMatches && scenarioMatches && personaMatches && decisionMatches
      }
      return action.targetScenarioID.map { summary.contains($0) } ?? false
    }
  }

  private static func matchesCurrentRationaleSignal(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction,
    signal: TournamentAutomationRationaleSignal?
  ) -> Bool {
    audit.personaRationaleSignalSummaries.contains { summary in
      if let signal {
        let labelMatches =
          summary.localizedCaseInsensitiveContains("resolve simulated-user rationale signal")
        let rationaleMatches = summary.localizedCaseInsensitiveContains(signal.rationale)
        let personaMatches =
          action.targetPersonaName.map {
            summary.localizedCaseInsensitiveContains($0)
          } ?? true
        let decisionMatches =
          (action.targetDecision ?? signal.targetDecision).map {
            summary.contains("target_decision \($0.rawValue)")
          } ?? true
        return labelMatches && rationaleMatches && personaMatches && decisionMatches
      }
      return action.targetScenarioID.map { summary.contains($0) } ?? false
    }
  }

  private static func matchesCurrentTargetedProofOutcome(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction,
    signal: TournamentAutomationTargetedProofOutcomeSignal
  ) -> Bool {
    audit.targetedProofOutcomeSummaries.contains { summary in
      let labelMatches = summary.localizedCaseInsensitiveContains(
        "targeted tournament proof outcome")
      let targetDecisionMatches = summary.contains(
        "target_decision \(signal.targetDecision.rawValue)"
      )
      let outcomeMatches = summary.contains("outcome \(signal.outcome.rawValue)")
      let recommendedMatches =
        signal.recommendedDecision.map {
          summary.contains("recommended_decision \($0.rawValue)")
        } ?? true
      let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
      let personaMatches =
        action.targetPersonaName.map {
          summary.localizedCaseInsensitiveContains($0)
        } ?? true
      return labelMatches
        && targetDecisionMatches
        && outcomeMatches
        && recommendedMatches
        && scenarioMatches
        && personaMatches
    }
  }

  private static func matchesCurrentTargetedProofOutcomeRevision(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction,
    signal: TournamentAutomationTargetedProofOutcomeSignal
  ) -> Bool {
    let revisionMatches = audit.revisionBriefSummaries.contains { summary in
      let sourceMatches = summary.contains(
        TournamentAutomationRevisionBriefSource.targetedProofOutcome.rawValue
      )
      let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
      let personaMatches =
        action.targetPersonaName.map {
          summary.localizedCaseInsensitiveContains($0)
        } ?? true
      let decisionMatches =
        action.targetDecision.map {
          summary.contains("target_decision \($0.rawValue)")
        } ?? true
      return sourceMatches && scenarioMatches && personaMatches && decisionMatches
    }
    if revisionMatches {
      return true
    }
    return matchesCurrentTargetedProofOutcome(audit: audit, action: action, signal: signal)
  }

  private static func matchesCurrentRevisionBrief(
    audit: TournamentAutomationCycleAudit,
    brief: TournamentAutomationRevisionBrief
  ) -> Bool {
    audit.revisionBriefSummaries.contains { summary in
      let titleMatches = summary.localizedCaseInsensitiveContains(brief.title)
      let sourceMatches = summary.contains(brief.source.rawValue)
      let scenarioMatches = brief.targetScenarioID.map { summary.contains($0) } ?? true
      let personaMatches =
        brief.targetPersonaName.map {
          summary.localizedCaseInsensitiveContains($0)
        } ?? true
      let decisionMatches =
        brief.targetDecision.map {
          summary.contains("target_decision \($0.rawValue)")
        } ?? true
      return titleMatches && sourceMatches && scenarioMatches && personaMatches && decisionMatches
    }
  }

  private static func matchesCurrentRevisionBrief(
    audit: TournamentAutomationCycleAudit,
    action: ProductTournamentNextAction
  ) -> Bool {
    audit.revisionBriefSummaries.contains { summary in
      let scenarioMatches = action.targetScenarioID.map { summary.contains($0) } ?? true
      let personaMatches =
        action.targetPersonaName.map {
          summary.localizedCaseInsensitiveContains($0)
        } ?? true
      let decisionMatches =
        action.targetDecision.map {
          summary.contains("target_decision \($0.rawValue)")
        } ?? true
      return scenarioMatches && personaMatches && decisionMatches
    }
  }

  private static func broadCohortStepIDs(for action: ProductTournamentNextAction) -> Set<String> {
    guard let cohortID = action.cohortID else { return [] }
    return [
      "\(action.experimentID):\(ProductTournamentNextActionKind.runCohort.rawValue):\(cohortID)",
      "\(action.experimentID):\(ProductTournamentNextActionKind.rerunCohort.rawValue):\(cohortID)",
    ]
  }

  private static func hasCompletedEvidence(
    after audit: TournamentAutomationCycleAudit,
    for experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> Bool {
    evidenceIndex.summaries(for: experiment).contains {
      $0.isCompleted && $0.endedAt > audit.endedAt
    }
  }
}

enum TournamentAutomationPlanner {
  static func cohortSimulationMode(
    isPersonaModelAvailable: Bool
  ) -> ProductTournamentSimulationMode {
    isPersonaModelAvailable ? .personaModel : .modelFree
  }

  static func steps(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [TournamentAutomationStep] {
    let plannedSteps = TournamentAutomationExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: evidenceIndex
    ).compactMap { experiment in
      let planProofStep = planProofStep(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
      if planProofStep?.action.requiredSimulationMode == .personaModel {
        return planProofStep
      }
      if let transitionStep = roundTransitionStep(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ) {
        return applyingRecentCycleFailureBlock(
          to: transitionStep,
          experiment: experiment,
          config: config,
          evidenceIndex: evidenceIndex
        )
      }
      if let planProofStep {
        return planProofStep
      }
      if let revisionStep = revisionBriefStep(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ) {
        let failureGuarded = applyingRecentCycleFailureBlock(
          to: revisionStep,
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
      guard
        let action = ProductTournamentNextActionAdvisor.nextAction(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex
        )
      else { return nil }
      guard
        !shouldOmitForRoundTwoImplementationTarget(
          action: action,
          experimentID: experiment.id,
          config: config
        )
      else { return nil }
      let step = TournamentAutomationStep(
        experiment: experiment,
        action: action,
        cohortReadiness: ProductTournamentNextActionAdvisor.cohortRunReadiness(
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
      let revisionReady = applyingRevisionBriefStep(
        to: failureGuarded,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
      return applyingRecentCycleLearningBlock(
        to: revisionReady,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    return plannedSteps.sorted { lhs, rhs in
      if lhs.canExecute != rhs.canExecute { return lhs.canExecute && !rhs.canExecute }
      if lhs.action.priority == rhs.action.priority {
        if lhs.experimentID == rhs.experimentID { return lhs.id < rhs.id }
        return lhs.experimentID < rhs.experimentID
      }
      return lhs.action.priority > rhs.action.priority
    }
  }

  private static func roundTransitionStep(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationStep? {
    if let proposal = ProductTournamentPlanTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first(where: { $0.isActionable && contender($0.contenderID, matches: experiment, in: config) })
    {
      return transitionStep(
        experiment: experiment,
        title: "Apply Round 1 transition",
        detail:
          "\(proposal.title): \(proposal.detail)",
        priority: proposal.priority,
        tournamentID: proposal.tournamentID,
        roundID: proposal.roundID,
        contenderID: proposal.contenderID,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    }

    if let proposal = ProductTournamentRoundEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first(where: {
      $0.isActionable
        && contender($0.contenderID, matches: experiment, in: config)
        && !isRedundantRoundTwoRevision($0, for: experiment, in: config)
    })
    {
      return transitionStep(
        experiment: experiment,
        title: "Apply Round 2 transition",
        detail:
          "\(proposal.title): \(proposal.detail)",
        priority: proposal.priority,
        tournamentID: proposal.tournamentID,
        roundID: proposal.roundID,
        contenderID: proposal.contenderID,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    }

    if let proposal = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first(where: {
      $0.isActionable
        && contender($0.contenderID, matches: experiment, in: config)
        && !isRoundThreeImplementationRevision($0, for: experiment, in: config)
    })
    {
      return transitionStep(
        experiment: experiment,
        title: "Apply Round 3 transition",
        detail:
          "\(proposal.title): \(proposal.detail)",
        priority: proposal.priority,
        tournamentID: proposal.tournamentID,
        roundID: proposal.roundID,
        contenderID: proposal.contenderID,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    }

    return nil
  }

  private static func isRedundantRoundTwoRevision(
    _ proposal: ProductTournamentRoundEvidenceTransitionProposal,
    for experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> Bool {
    guard proposal.recommendation == .reviseCoreTechnology else { return false }
    return config.tournamentContenders.contains {
      $0.id == proposal.contenderID
        && $0.experimentID == experiment.id
        && $0.status == .needsRevision
    }
  }

  private static func isRoundThreeImplementationRevision(
    _ proposal: ProductTournamentProductImplementationEvidenceTransitionProposal,
    for experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> Bool {
    proposal.recommendation == .reviseImplementation
      && contender(proposal.contenderID, matches: experiment, in: config)
  }

  private static func transitionStep(
    experiment: ProductTournamentExperiment,
    title: String,
    detail: String,
    priority: Int,
    tournamentID: String,
    roundID: String,
    contenderID: String,
    isPersonaModelAvailable: Bool
  ) -> TournamentAutomationStep {
    TournamentAutomationStep(
      experiment: experiment,
      action: ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .applyRoundTransition,
        title: title,
        detail: detail,
        priority: priority,
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID
      ),
      cohortReadiness: nil,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
  }

  private static func contender(
    _ contenderID: String,
    matches experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> Bool {
    config.tournamentContenders.contains {
      $0.id == contenderID && $0.experimentID == experiment.id
    }
  }

  private static func planProofStep(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationStep? {
    guard evidenceIndex.summaries.isEmpty else { return nil }
    guard
      let target = TournamentAutomationProofTargetAdvisor.target(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ),
      let tournamentID = target.tournamentID,
      let roundID = target.roundID,
      let contenderID = target.contenderID
    else { return nil }
    let actionTitle = target.nextActionTitle ?? target.label
    let planMode = target.requiredSimulationMode
    let planModeLabel = planMode == .personaModel ? "persona-model" : "model-free"
    let action = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .runPlanProof,
      title: actionTitle,
      detail:
        "Run focused Round 1 \(planModeLabel) simulated-user plan proof for contender `\(contenderID)` in round `\(roundID)`. Remaining plan proof debt: \(target.debtSummary).",
      priority: target.nextActionPriority,
      tournamentID: tournamentID,
      roundID: roundID,
      contenderID: contenderID,
      requiredSimulationMode: planMode
    )
    return TournamentAutomationStep(
      experiment: experiment,
      action: action,
      cohortReadiness: nil,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
  }

  private static func revisionBriefStep(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool
  ) -> TournamentAutomationStep? {
    let brief =
      TournamentAutomationRevisionBriefAdvisor.roundTwoProofGapBrief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
      ?? TournamentAutomationRevisionBriefAdvisor.roundThreeImplementationRevisionBrief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    guard let brief else { return nil }
    guard
      TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: brief,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ) == nil
    else { return nil }
    let action = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .refineContender,
      title: brief.title,
      detail:
        "Proof: \(brief.proofPlan) Implementation: \(brief.implementationChange) Scenario: \(brief.scenarioChange) Trigger: \(brief.triggerSummary)",
      priority: brief.priority,
      cohortID: brief.targetCohortID,
      targetPersonaID: brief.targetPersonaID,
      targetPersonaName: brief.targetPersonaName,
      targetScenarioID: brief.targetScenarioID,
      targetDecision: brief.targetDecision
    )
    var step = TournamentAutomationStep(
      experiment: experiment,
      action: action,
      cohortReadiness: nil,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    step.kind = .applyRevision
    step.canExecute = true
    step.blockedReason = nil
    return step
  }

  static func nextExecutableStep(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationStep? {
    steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    .first { $0.canExecute }
  }

  static func nextStep(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationStep? {
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
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    maxSteps: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationCyclePlan {
    let limit = max(1, maxSteps)
    let allSteps = steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    let executableSteps = allSteps.filter(\.canExecute)
    let selectedExecutableSteps = Array(executableSteps.prefix(limit))
    return TournamentAutomationCyclePlan(
      executableSteps: selectedExecutableSteps,
      blockedSteps: allSteps.filter { !$0.canExecute },
      maxSteps: limit,
      capped: executableSteps.count > selectedExecutableSteps.count,
      refreshesQueueAfterStateChange: selectedExecutableSteps.contains {
        $0.kind == .prepareWorktree
      }
    )
  }

  private static func applyingRecentCycleFailureBlock(
    to step: TournamentAutomationStep,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationStep {
    guard step.canExecute,
      let audit = TournamentAutomationCycleFailureAdvisor.blockingAudit(
        forStepID: step.id,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return step }
    var blocked = step
    blocked.canExecute = false
    blocked.blockedReason =
      "Recent tournament automation cycle \(audit.id) failed while running this step; repair the generated app contract, runner, scenario, or cohort before retrying. \(audit.stopDetail)"
    return blocked
  }

  private static func shouldOmitForRoundTwoImplementationTarget(
    action: ProductTournamentNextAction,
    experimentID: String,
    config: ProductTournamentConfig
  ) -> Bool {
    guard action.kind != .applyDecision && action.kind != .applyRoundTransition else {
      return false
    }
    return ProductTournamentRoundImplementationTargetResolver.blocksEvidenceLaunch(
      experimentID: experimentID,
      in: config
    )
  }

  private static func applyingRecentCycleLearningBlock(
    to step: TournamentAutomationStep,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationStep {
    if step.canExecute,
      step.kind == .applyRevision,
      let brief = TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let audit = TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: brief,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      var blocked = step
      blocked.canExecute = false
      blocked.blockedReason =
        "Recent tournament automation cycle \(audit.id) already applied this contender revision; run fresh targeted persona-model evidence or change the product implementation before applying it again."
      return blocked
    }
    if step.canExecute,
      let audit = TournamentAutomationCycleLearningAdvisor.stalledTargetedProofOutcomeAudit(
        for: step.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      var blocked = step
      blocked.canExecute = false
      blocked.blockedReason =
        "Recent tournament automation cycle \(audit.id) already attempted this targeted tournament proof outcome and the same outcome is still present; revise the product implementation, scenario, target persona, or decision criteria before retrying."
      return blocked
    }
    if step.canExecute,
      let audit = TournamentAutomationCycleLearningAdvisor.stalledEvidenceTensionAudit(
        for: step.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      var blocked = step
      blocked.canExecute = false
      blocked.blockedReason =
        "Recent tournament automation cycle \(audit.id) already attempted this split-evidence target and the current tournament evidence is still split; revise the scenario, persona, product implementation, or decision criteria before retrying."
      return blocked
    }
    if step.canExecute,
      let audit = TournamentAutomationCycleLearningAdvisor.stalledRationaleSignalAudit(
        for: step.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      var blocked = step
      blocked.canExecute = false
      blocked.blockedReason =
        "Recent tournament automation cycle \(audit.id) already attempted this simulated-user rationale signal and the same rationale is still present; revise the product implementation, scenario, or current-alternative proof before retrying."
      return blocked
    }
    guard step.canExecute,
      let audit = TournamentAutomationCycleLearningAdvisor.stalledProofTargetAudit(
        for: step.action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return step }
    var blocked = step
    blocked.canExecute = false
    blocked.blockedReason =
      "Recent tournament automation cycle \(audit.id) already attempted this proof target without reducing proof debt; inspect the run evidence, change the scenario or current-alternative proof, or choose a different persona-model target before retrying."
    return blocked
  }

  private static func applyingRevisionBriefStep(
    to step: TournamentAutomationStep,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> TournamentAutomationStep {
    guard step.action.kind == .refineContender,
      let brief = TournamentAutomationRevisionBriefAdvisor.brief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      revisionBriefMatches(action: step.action, brief: brief)
    else { return step }
    var executable = step
    executable.kind = .applyRevision
    executable.canExecute = true
    executable.blockedReason = nil
    return executable
  }

  private static func revisionBriefMatches(
    action: ProductTournamentNextAction,
    brief: TournamentAutomationRevisionBrief
  ) -> Bool {
    if action.targetScenarioID == nil && action.targetPersonaID == nil {
      return false
    }
    if let targetScenarioID = action.targetScenarioID,
      brief.targetScenarioID != targetScenarioID
    {
      return false
    }
    if let targetPersonaID = action.targetPersonaID,
      brief.targetPersonaID != targetPersonaID
    {
      return false
    }
    if let targetDecision = action.targetDecision,
      brief.targetDecision != targetDecision
    {
      return false
    }
    return true
  }
}

enum TournamentAutomationPlanProofStepError: LocalizedError, Equatable {
  case invalidStep(String)
  case missingScope(String)
  case personaModelRequiresAsync(String)

  var errorDescription: String? {
    switch self {
    case .invalidStep(let id):
      return "Tournament automation step \(id) is not a Round 1 plan-proof step."
    case .missingScope(let id):
      return
        "Tournament automation plan-proof step \(id) is missing tournament, round, or contender scope."
    case .personaModelRequiresAsync(let id):
      return "Tournament automation plan-proof step \(id) requires persona-model evaluation."
    }
  }
}

enum TournamentAutomationPrepareWorktreeStepError: LocalizedError, Equatable {
  case invalidStep(String)

  var errorDescription: String? {
    switch self {
    case .invalidStep(let id):
      return "Tournament automation step \(id) is not an implementation worktree prepare step."
    }
  }
}

struct TournamentAutomationPrepareWorktreeStepOutcome: Equatable, Sendable {
  var userMessage: String
  var prepared: ProductTournamentExperimentWorktree
  var config: ProductTournamentConfig

  init(
    userMessage: String,
    prepared: ProductTournamentExperimentWorktree,
    config: ProductTournamentConfig
  ) {
    self.userMessage = ProductTournamentModelText.cleanedText(
      userMessage,
      fallback: "Prepared implementation worktree.",
      limit: 1_200
    )
    self.prepared = prepared
    self.config = config
  }
}

enum TournamentAutomationPrepareWorktreeStepExecutor {
  static func run(
    _ step: TournamentAutomationStep,
    in workspace: CompassWorkspace
  ) async throws -> TournamentAutomationPrepareWorktreeStepOutcome {
    guard step.kind == .prepareWorktree, step.action.kind == .prepareWorktree else {
      throw TournamentAutomationPrepareWorktreeStepError.invalidStep(step.id)
    }

    let prepared = try await workspace.prepareProductTournamentExperimentWorktree(
      experimentID: step.experimentID
    )
    let config = try workspace.readProductTournamentConfig()
    let shortCommit = String(prepared.currentSha.prefix(12))
    return TournamentAutomationPrepareWorktreeStepOutcome(
      userMessage:
        "Prepared implementation worktree for \(step.experimentTitle) at \(shortCommit) on \(prepared.branchName).",
      prepared: prepared,
      config: config
    )
  }
}

enum TournamentAutomationRoundTransitionStepError: LocalizedError, Equatable {
  case invalidStep(String)
  case missingScope(String)
  case unknownRound(String)
  case unsupportedRound(String, ProductTournamentRoundKind)
  case missingProposal(String, String)

  var errorDescription: String? {
    switch self {
    case .invalidStep(let id):
      return "Tournament automation step \(id) is not a round-transition step."
    case .missingScope(let id):
      return
        "Tournament automation round-transition step \(id) is missing tournament, round, or contender scope."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unsupportedRound(let id, let kind):
      return "Product tournament round \(id) has unsupported transition kind \(kind.rawValue)."
    case .missingProposal(let contenderID, let roundID):
      return
        "No actionable tournament transition exists for contender \(contenderID) in round \(roundID)."
    }
  }
}

struct TournamentAutomationRoundTransitionStepOutcome: Equatable, Sendable {
  var userMessage: String
  var config: ProductTournamentConfig
  var tournamentID: String
  var roundID: String
  var contenderID: String
  var roundKind: ProductTournamentRoundKind
  var toRoundID: String?

  init(
    userMessage: String,
    config: ProductTournamentConfig,
    tournamentID: String,
    roundID: String,
    contenderID: String,
    roundKind: ProductTournamentRoundKind,
    toRoundID: String? = nil
  ) {
    self.userMessage = ProductTournamentModelText.cleanedText(
      userMessage,
      fallback: "Applied tournament round transition.",
      limit: 1_200
    )
    self.config = config
    self.tournamentID = tournamentID
    self.roundID = roundID
    self.contenderID = contenderID
    self.roundKind = roundKind
    self.toRoundID = ProductTournamentModelText.optionalIdentifier(toRoundID, fallback: "round")
  }
}

enum TournamentAutomationRoundTransitionStepExecutor {
  static func run(
    _ step: TournamentAutomationStep,
    in workspace: CompassWorkspace,
    now: Date = Date()
  ) throws -> TournamentAutomationRoundTransitionStepOutcome {
    guard step.kind == .applyRoundTransition,
      step.action.kind == .applyRoundTransition
    else {
      throw TournamentAutomationRoundTransitionStepError.invalidStep(step.id)
    }
    guard
      let tournamentID = step.tournamentID,
      let roundID = step.roundID,
      let contenderID = step.contenderID
    else {
      throw TournamentAutomationRoundTransitionStepError.missingScope(step.id)
    }

    let config = try workspace.readProductTournamentConfig()
    let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
    guard let round = config.tournamentRounds.first(where: { $0.id == roundID }) else {
      throw TournamentAutomationRoundTransitionStepError.unknownRound(roundID)
    }

    let result: (message: String, config: ProductTournamentConfig, toRoundID: String?)
    switch round.kind {
    case .productPlans:
      let proposal = try planProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentPlanTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      result = (outcome.userMessage, outcome.config, outcome.toRoundID)
    case .coreTechnology:
      let proposal = try roundTwoProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentRoundEvidenceTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      result = (outcome.userMessage, outcome.config, outcome.toRoundID)
    case .productImplementation:
      let proposal = try roundThreeProposal(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      result = (outcome.userMessage, outcome.config, outcome.toRoundID)
    }

    try workspace.writeProductTournamentConfig(result.config)
    return TournamentAutomationRoundTransitionStepOutcome(
      userMessage: result.message,
      config: result.config,
      tournamentID: tournamentID,
      roundID: roundID,
      contenderID: contenderID,
      roundKind: round.kind,
      toRoundID: result.toRoundID
    )
  }

  private static func planProposal(
    tournamentID: String,
    roundID: String,
    contenderID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentPlanTransitionProposal {
    guard
      let proposal = ProductTournamentPlanTransitioner.proposals(
        tournamentID: tournamentID,
        roundID: roundID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: { $0.contenderID == contenderID && $0.isActionable })
    else {
      throw TournamentAutomationRoundTransitionStepError.missingProposal(contenderID, roundID)
    }
    return proposal
  }

  private static func roundTwoProposal(
    tournamentID: String,
    roundID: String,
    contenderID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentRoundEvidenceTransitionProposal {
    guard
      let proposal = ProductTournamentRoundEvidenceTransitioner.proposals(
        tournamentID: tournamentID,
        roundID: roundID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: { $0.contenderID == contenderID && $0.isActionable })
    else {
      throw TournamentAutomationRoundTransitionStepError.missingProposal(contenderID, roundID)
    }
    return proposal
  }

  private static func roundThreeProposal(
    tournamentID: String,
    roundID: String,
    contenderID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentProductImplementationEvidenceTransitionProposal {
    guard
      let proposal = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        tournamentID: tournamentID,
        roundID: roundID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: { $0.contenderID == contenderID && $0.isActionable })
    else {
      throw TournamentAutomationRoundTransitionStepError.missingProposal(contenderID, roundID)
    }
    return proposal
  }
}

enum TournamentAutomationPlanProofStepExecutor {
  static func runAutomation(
    _ step: TournamentAutomationStep,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    now: Date = Date(),
    streamText: (@Sendable (_ prompt: String) async -> String?)? = nil
  ) async throws -> ProductTournamentPlanEvaluationOutcome {
    guard step.kind == .runPlanProof, step.action.kind == .runPlanProof else {
      throw TournamentAutomationPlanProofStepError.invalidStep(step.id)
    }
    guard
      let tournamentID = step.tournamentID,
      let roundID = step.roundID,
      let contenderID = step.contenderID
    else {
      throw TournamentAutomationPlanProofStepError.missingScope(step.id)
    }
    guard step.action.requiredSimulationMode == .personaModel else {
      return try run(step, in: workspace, projectID: projectID, now: now)
    }
    if let streamText {
      return try await ProductTournamentPlanEvaluator.runPlanRoundPersonaModel(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID,
        in: workspace,
        projectID: projectID,
        now: now,
        streamText: streamText
      )
    }
    return try await ProductTournamentPlanEvaluator.runPlanRoundPersonaModel(
      tournamentID: tournamentID,
      roundID: roundID,
      contenderID: contenderID,
      in: workspace,
      projectID: projectID,
      now: now
    )
  }

  static func run(
    _ step: TournamentAutomationStep,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    now: Date = Date()
  ) throws -> ProductTournamentPlanEvaluationOutcome {
    guard step.kind == .runPlanProof, step.action.kind == .runPlanProof else {
      throw TournamentAutomationPlanProofStepError.invalidStep(step.id)
    }
    guard
      let tournamentID = step.tournamentID,
      let roundID = step.roundID,
      let contenderID = step.contenderID
    else {
      throw TournamentAutomationPlanProofStepError.missingScope(step.id)
    }
    guard step.action.requiredSimulationMode != .personaModel else {
      throw TournamentAutomationPlanProofStepError.personaModelRequiresAsync(step.id)
    }
    return try ProductTournamentPlanEvaluator.runPlanRound(
      tournamentID: tournamentID,
      roundID: roundID,
      contenderID: contenderID,
      in: workspace,
      projectID: projectID,
      now: now
    )
  }
}

enum ProductTournamentDecisionAdvisorError: LocalizedError, Equatable {
  case noProposal(String)

  var errorDescription: String? {
    switch self {
    case .noProposal(let experimentID):
      return
        "No tournament decision recommendation is available for tournament experiment \(experimentID)."
    }
  }
}

enum ProductTournamentNextActionAdvisor {
  static func actions(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentNextAction] {
    config.tournamentExperiments.compactMap { experiment in
      nextAction(for: experiment, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.priority == rhs.priority { return lhs.experimentID < rhs.experimentID }
      return lhs.priority > rhs.priority
    }
  }

  static func nextAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    switch experiment.decision {
    case .archived, .promoted:
      return nil
    case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
      break
    }

    if let implementationRevisionValidationAction =
      roundThreeImplementationRevisionValidationAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      return applyingRecentCycleGuards(
        to: implementationRevisionValidationAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let implementationRevisionPartialValidationAction =
      roundThreeImplementationRevisionPartialValidationAction(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      return applyingRecentCycleGuards(
        to: implementationRevisionPartialValidationAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let roundThreeProofAction = roundThreeProductImplementationProofAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return applyingRecentCycleGuards(
        to: roundThreeProofAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    if let proposal = ProductTournamentDecisionAdvisor.proposal(
      experimentID: experiment.id,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .applyDecision,
        title: "Apply tournament decision",
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
        return ProductTournamentNextAction(
          experimentID: experiment.id,
          kind: .refineContender,
          title: "Define evidence cohort",
          detail:
            "No enabled scenario cohort is ready for this experiment; define an enabled cohort before tournament automation can gather evidence.",
          priority: staleCount > 0 ? 96 : 91
        )
      }
      let runAction = ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: staleCount > 0 ? .rerunCohort : .runCohort,
        title: staleCount > 0 ? "Rerun current evidence" : "Run product tournament cohort",
        detail: staleCount > 0
          ? "\(staleCount) stale run(s) exist for older commits; rerun cohort `\(cohort.id)` against the current experiment commit before deciding."
          : "No current-commit evidence exists yet; run cohort `\(cohort.id)` before changing the tournament decision.",
        priority: staleCount > 0 ? 95 : 90,
        cohortID: cohort.id
      )
      return applyingRecentCycleGuards(
        to: prepareWorktreeActionIfNeeded(
          replacing: runAction,
          experiment: experiment,
          config: config
        )
          ?? runAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    guard let readiness = evidenceIndex.currentTournamentReadiness(for: experiment) else {
      return nil
    }
    if readiness.failedRunCount > readiness.completedRunCount {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .repairFailures,
        title: "Repair evidence run failures",
        detail:
          "\(readiness.failedRunCount) of \(readiness.runCount) current run(s) failed; fix the generated app contract or runner before trusting tournament signals.",
        priority: 85
      )
    }
    if let proofGapRevisionValidationAction = roundTwoProofGapRevisionValidationAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return applyingRecentCycleGuards(
        to: proofGapRevisionValidationAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let proofGapPartialValidationAction = roundTwoProofGapPartialValidationAction(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return applyingRecentCycleGuards(
        to: proofGapPartialValidationAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let proofOutcomeSignal = TournamentAutomationTargetedProofOutcomeAdvisor.signal(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return applyingRecentCycleGuards(
        to: nextAction(for: proofOutcomeSignal),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if readiness.completedRunCount < 2 || readiness.distinctPersonaCount < 2 {
      let runAction = ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: cohort == nil ? .refineContender : .runCohort,
        title: "Gather broader persona evidence",
        detail: cohort.map {
          "Current evidence has \(readiness.completedRunCount) completed run(s) across \(readiness.distinctPersonaCount) persona(s); run cohort `\($0.id)` to broaden evidence before deciding."
        }
          ?? "Current evidence has \(readiness.completedRunCount) completed run(s) across \(readiness.distinctPersonaCount) persona(s); define another enabled scenario or persona before deciding.",
        priority: 80,
        cohortID: cohort?.id
      )
      return applyingRecentCycleGuards(
        to: prepareWorktreeActionIfNeeded(
          replacing: runAction,
          experiment: experiment,
          config: config
        )
          ?? runAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    let missingPersonaModelUserTarget = missingPersonaModelTarget(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex,
      cohort: cohort
    )
    if readiness.personaModelDistinctPersonaCount < 2 && readiness.readinessScore >= 70 {
      return applyingRecentCycleGuards(
        to: personaModelBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingPersonaModelUserTarget,
          title: "Run persona-model validation cohort",
          decisionGate: "promotion",
          gateReason: "promotion requires at least 2",
          targetDecision: .promote,
          priority: 78,
          observedCount: readiness.personaModelDistinctPersonaCount,
          observedEvidenceLabel: "persona-model simulated user(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if readiness.personaModelDistinctPersonaCount < 2 && shouldRunPersonaModelRejectionCheck(readiness) {
      return applyingRecentCycleGuards(
        to: personaModelBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingPersonaModelUserTarget,
          title: "Run persona-model rejection check",
          decisionGate: "stopping the experiment",
          gateReason: "stopping a contender requires at least 2",
          targetDecision: .kill,
          priority: 82,
          observedCount: readiness.personaModelDistinctPersonaCount,
          observedEvidenceLabel: "persona-model simulated user(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    let currentAlternativePersonaIDs = personaModelCurrentAlternativePersonaIDs(
      for: experiment,
      evidenceIndex: evidenceIndex
    )
    let missingCurrentAlternativeTarget = missingPersonaModelTarget(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex,
      cohort: cohort,
      testedPersonaIDs: currentAlternativePersonaIDs
    )
    if readiness.personaModelCurrentAlternativePersonaCount < 2 && readiness.readinessScore >= 70 {
      return applyingRecentCycleGuards(
        to: personaModelBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingCurrentAlternativeTarget,
          title: "Run persona-model alternative challenge",
          decisionGate: "promotion",
          gateReason:
            "decisive tournament decisions require current-alternative proof from at least 2 persona-model simulated users",
          targetDecision: .promote,
          priority: 77,
          observedCount: readiness.personaModelCurrentAlternativePersonaCount,
          observedEvidenceLabel: "persona-model current-alternative simulated user(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if readiness.personaModelCurrentAlternativePersonaCount < 2
      && shouldRunPersonaModelRejectionCheck(readiness)
    {
      return applyingRecentCycleGuards(
        to: personaModelBreadthAction(
          experiment: experiment,
          selectedCohort: cohort,
          target: missingCurrentAlternativeTarget,
          title: "Run persona-model alternative rejection check",
          decisionGate: "stopping the experiment",
          gateReason:
            "decisive tournament decisions require current-alternative proof from at least 2 persona-model simulated users",
          targetDecision: .kill,
          priority: 81,
          observedCount: readiness.personaModelCurrentAlternativePersonaCount,
          observedEvidenceLabel: "persona-model current-alternative simulated user(s)"
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    if let tension = TournamentAutomationEvidenceTensionAdvisor.tension(
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
          "\(tension.summary) Rerun rejecting persona-model scenario `\(targetScenarioID)` for \(targetPersonaName) in cohort `\(targetCohortID)` before lift/cut."
      } else if let targetPersonaName = tension.targetPersonaName {
        detail =
          "\(tension.summary) Add or enable a cohort scenario for \(targetPersonaName), then rerun it in persona-model mode before lift/cut."
      } else if let actionCohortID {
        detail =
          "\(tension.summary) Run cohort `\(actionCohortID)` in persona-model mode to compare the disagreeing personas before lift/cut."
      } else {
        detail =
          "\(tension.summary) Add an enabled persona-model scenario that directly compares the disagreeing evidence before lift/cut."
      }
      return applyingRecentCycleGuards(
        to: ProductTournamentNextAction(
          experimentID: experiment.id,
          kind: canRunTarget ? .runCohort : .refineContender,
          title: "Resolve split tournament evidence",
          detail: detail,
          priority: tension.urgencyScore,
          cohortID: actionCohortID,
          requiredSimulationMode: .personaModel,
          targetPersonaID: tension.targetPersonaID,
          targetPersonaName: tension.targetPersonaName,
          targetScenarioID: tension.targetScenarioID,
          targetDecision: liftCutDecisionHint(for: readiness.recommendation)
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    if let rationaleSignal = TournamentAutomationRationaleSignalAdvisor.signal(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      let canRunTarget =
        rationaleSignal.targetCohortID != nil
        && rationaleSignal.targetScenarioID != nil
      let shouldRunTarget =
        canRunTarget
        && (readiness.recommendation == .gatherEvidence || readiness.recommendation == .keepGoing)
      let actionKind: ProductTournamentNextActionKind =
        shouldRunTarget ? .runCohort : .refineContender
      let targetDetail: String
      if shouldRunTarget, let cohortID = rationaleSignal.targetCohortID,
        let scenarioID = rationaleSignal.targetScenarioID,
        let targetPersonaName = rationaleSignal.targetPersonaName
      {
        targetDetail =
          "\(rationaleSignal.summary) Rerun persona-model scenario `\(scenarioID)` for \(targetPersonaName) in cohort `\(cohortID)` after this rationale has been addressed."
      } else if let targetPersonaName = rationaleSignal.targetPersonaName {
        targetDetail =
          "\(rationaleSignal.summary) Update the product implementation or scenario for \(targetPersonaName), then rerun persona-model proof before investing further."
      } else {
        targetDetail =
          "\(rationaleSignal.summary) Update the product implementation, scenario, or decision criteria, then rerun persona-model proof before investing further."
      }
      return applyingRecentCycleGuards(
        to: ProductTournamentNextAction(
          experimentID: experiment.id,
          kind: actionKind,
          title: "Resolve simulated-user rationale signal",
          detail: targetDetail,
          priority: rationaleSignal.urgencyScore,
          cohortID: shouldRunTarget ? rationaleSignal.targetCohortID : nil,
          requiredSimulationMode: .personaModel,
          targetPersonaID: rationaleSignal.targetPersonaID,
          targetPersonaName: rationaleSignal.targetPersonaName,
          targetScenarioID: rationaleSignal.targetScenarioID,
          targetDecision: rationaleSignal.targetDecision
        ),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }

    switch readiness.recommendation {
    case .narrow:
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Narrow the product contender",
        detail:
          "Current tournament evidence points to missing capabilities or repeated objections; narrow the next product implementation before more rollout work.",
        priority: 75
      )
    case .pivot:
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Prepare a pivot",
        detail:
          "Users recognize the pain, but current contender pull is weak; reshape the contender plan before more cohort runs.",
        priority: 74
      )
    case .kill:
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .reviewDecision,
        title: "Review kill decision",
        detail:
          "Current evidence is weak, but the existing experiment state blocks an automatic kill recommendation; inspect the decision path.",
        priority: 73
      )
    case .promote:
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .reviewDecision,
        title: "Review promotion path",
        detail:
          "Current evidence has promotion strength, but the existing experiment state blocks an automatic promote recommendation.",
        priority: 73
      )
    case .gatherEvidence, .keepGoing:
      let runAction = ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: cohort == nil ? .refineContender : .runCohort,
        title: "Run another evidence cohort",
        detail: cohort.map {
          "Current tournament readiness is \(readiness.scoreLabel)/100; run cohort `\($0.id)` or add a scenario variant before changing the tournament decision."
        }
          ?? "Current tournament readiness is \(readiness.scoreLabel)/100; define another enabled scenario cohort before changing the tournament decision.",
        priority: 70,
        cohortID: cohort?.id
      )
      return applyingRecentCycleGuards(
        to: prepareWorktreeActionIfNeeded(
          replacing: runAction,
          experiment: experiment,
          config: config
        )
          ?? runAction,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
  }

  private enum RoundThreeProductImplementationProofNeed: Equatable, Sendable {
    case implementationUse
    case currentAlternative
    case willingnessToPay
    case personaBreadth
    case completedRun
    case remaining

    init(proposal: ProductTournamentProductImplementationEvidenceTransitionProposal) {
      if proposal.completedRunCount == 0 || proposal.implementationUseProofCount < 3 {
        self = .implementationUse
      } else if proposal.currentAlternativeProofCount < 2 {
        self = .currentAlternative
      } else if proposal.willingnessToPayProofCount < 2 {
        self = .willingnessToPay
      } else if proposal.distinctPersonaCount < 2 {
        self = .personaBreadth
      } else if proposal.completedRunCount < 3 {
        self = .completedRun
      } else {
        self = .remaining
      }
    }

    var title: String {
      switch self {
      case .implementationUse:
        return "Run Round 3 implementation-use proof"
      case .currentAlternative:
        return "Run Round 3 alternative proof"
      case .willingnessToPay:
        return "Run Round 3 pay proof"
      case .personaBreadth:
        return "Broaden Round 3 persona proof"
      case .completedRun:
        return "Run Round 3 product proof"
      case .remaining:
        return "Run Round 3 proof-gap validation"
      }
    }

    var proofLabel: String {
      switch self {
      case .implementationUse:
        return "implementation-use trace"
      case .currentAlternative:
        return "current-alternative comparison"
      case .willingnessToPay:
        return "explicit willingness-to-pay or sponsorship proof"
      case .personaBreadth:
        return "second simulated-user persona"
      case .completedRun:
        return "completed Round 3 run"
      case .remaining:
        return "remaining Round 3 proof gap"
      }
    }

    var priority: Int {
      switch self {
      case .implementationUse: return 93
      case .currentAlternative: return 92
      case .willingnessToPay: return 92
      case .personaBreadth: return 91
      case .completedRun: return 90
      case .remaining: return 89
      }
    }

    func isProven(by summary: ProductTournamentEvidenceSummary) -> Bool {
      guard summary.isCompleted else { return false }
      switch self {
      case .implementationUse:
        return summary.completedUseProof
      case .currentAlternative:
        return hasCurrentAlternativeProof(summary)
      case .willingnessToPay:
        return hasExplicitRoundThreePayProof(summary)
      case .personaBreadth, .completedRun, .remaining:
        return true
      }
    }

    private func hasCurrentAlternativeProof(
      _ summary: ProductTournamentEvidenceSummary
    ) -> Bool {
      let comparison = summary.currentAlternativeComparison
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard !comparison.isEmpty else { return false }
      return !comparison.contains("did not address")
        && !comparison.contains("no current-alternative comparison")
        && !comparison.contains("no current alternative")
    }

    private func hasExplicitRoundThreePayProof(
      _ summary: ProductTournamentEvidenceSummary
    ) -> Bool {
      let intent = normalizedText(summary.sponsorshipIntent)
      guard !intent.isEmpty else { return false }
      return ![
        "the simulated user shows strong willingness to pay for or sponsor this contender",
        "the simulated user shows moderate willingness to pay for or sponsor this contender after more proof",
        "the simulated user recognizes some contender value but is not ready to pay or sponsor",
        "the simulated user shows weak willingness to pay for or sponsor this contender",
      ].contains(intent)
    }

    private func normalizedText(_ value: String) -> String {
      value
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
  }

  private static func roundThreeProductImplementationProofAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let proposal = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
        config: config,
        evidenceIndex: evidenceIndex
      )
      .first(where: {
        $0.recommendation == .gatherEvidence
          && contender($0.contenderID, matches: experiment, in: config)
      })
    else { return nil }

    let need = RoundThreeProductImplementationProofNeed(proposal: proposal)
    let selectedCohort =
      roundScopedRunnableCohort(
        roundID: proposal.roundID,
        experiment: experiment,
        config: config
      ) ?? runnableCohort(for: experiment, config: config)
    let summaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == proposal.tournamentID
          && $0.roundID == proposal.roundID
          && $0.contenderID == proposal.contenderID
      }
    let target = roundThreeProductImplementationTarget(
      need: need,
      summaries: summaries,
      experiment: experiment,
      config: config,
      selectedCohort: selectedCohort
    )
    let gaps =
      proposal.proofGaps.isEmpty
      ? proposal.detail
      : proposal.proofGaps.prefix(3).joined(separator: "; ")
    let targetName = target?.name ?? "the next simulated user"
    let executableCohortID = target?.executableCohortID
    let executableScenarioID = target?.executableScenarioID
    let canRunTarget = executableCohortID != nil && executableScenarioID != nil
    let actionKind: ProductTournamentNextActionKind =
      canRunTarget
      ? (proposal.completedRunCount == 0 ? .runCohort : .rerunCohort)
      : .refineContender
    let detail: String
    if let executableCohortID, let executableScenarioID {
      detail =
        "Round 3 product implementation needs \(need.proofLabel) before winner selection; run persona-model scenario `\(executableScenarioID)` for \(targetName) in cohort `\(executableCohortID)` to close \(gaps). Next validation: \(proposal.nextValidationTarget)"
    } else if let selectedCohort {
      let guidance =
        target?.guidance(selectedCohort: selectedCohort, executableCohortID: executableCohortID)
        ?? " Target simulated-user segment: add an enabled scenario for this Round 3 proof gap."
      detail =
        "Round 3 product implementation needs \(need.proofLabel) before winner selection; cohort `\(selectedCohort.id)` does not cover a runnable target. \(guidance) Remaining gaps: \(gaps)."
    } else {
      let guidance =
        target?.guidance(selectedCohort: nil, executableCohortID: executableCohortID)
        ?? " Target simulated-user segment: add an enabled scenario and cohort for this Round 3 proof gap."
      detail =
        "Round 3 product implementation needs \(need.proofLabel) before winner selection; define an enabled persona-model scenario cohort.\(guidance) Remaining gaps: \(gaps)."
    }
    let action = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: actionKind,
      title: need.title,
      detail: detail,
      priority: need.priority,
      tournamentID: proposal.tournamentID,
      roundID: proposal.roundID,
      contenderID: proposal.contenderID,
      cohortID: executableCohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target?.id,
      targetPersonaName: target?.name,
      targetScenarioID: executableScenarioID,
      targetDecision: .promote
    )
    return prepareWorktreeActionIfNeeded(
      replacing: action,
      experiment: experiment,
      config: config
    ) ?? action
  }

  private static func roundThreeProductImplementationTarget(
    need: RoundThreeProductImplementationProofNeed,
    summaries: [ProductTournamentEvidenceSummary],
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    selectedCohort: ProductScenarioCohort?
  ) -> PersonaModelTarget? {
    let proofCounts = Dictionary(
      grouping: summaries.filter { need.isProven(by: $0) && !$0.personaID.isEmpty },
      by: \.personaID
    )
    .mapValues(\.count)
    let enabledScenarios = config.scenarios
      .filter { $0.experimentID == experiment.id && $0.enabled }
    let selectedScenarioIDs = Set(selectedCohort?.scenarioIDs ?? [])
    let selectedScenarios = enabledScenarios.filter { selectedScenarioIDs.contains($0.id) }
    let candidateScenarios = selectedScenarios.isEmpty ? enabledScenarios : selectedScenarios
    if let scenario = candidateScenarios.sorted(by: {
      let lhsCount = proofCounts[$0.segmentID, default: 0]
      let rhsCount = proofCounts[$1.segmentID, default: 0]
      if lhsCount == rhsCount { return scenarioSort(config: config)($0, $1) }
      return lhsCount < rhsCount
    }).first {
      let executableCohortID =
        selectedScenarioIDs.contains(scenario.id)
        ? selectedCohort?.id
        : executableCohortID(
          forScenarioID: scenario.id,
          experiment: experiment,
          config: config
        )
      return PersonaModelTarget(
        id: scenario.segmentID,
        name: segmentName(for: scenario.segmentID, config: config),
        scenarioID: scenario.id,
        executableCohortID: executableCohortID
      )
    }

    guard let segmentID = targetSegmentIDs(for: experiment, config: config).first else {
      return nil
    }
    return PersonaModelTarget(
      id: segmentID,
      name: segmentName(for: segmentID, config: config),
      scenarioID: nil,
      executableCohortID: nil
    )
  }

  private static func roundScopedRunnableCohort(
    roundID: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> ProductScenarioCohort? {
    guard
      let round = config.tournamentRounds.first(where: { $0.id == roundID }),
      !round.scenarioCohortIDs.isEmpty
    else { return nil }
    let enabledScenarioIDs = Set(
      config.scenarios
        .filter { $0.experimentID == experiment.id && $0.enabled }
        .map(\.id)
    )
    return config.scenarioCohorts
      .filter {
        $0.experimentID == experiment.id
          && $0.enabled
          && round.scenarioCohortIDs.contains($0.id)
          && $0.scenarioIDs.contains { enabledScenarioIDs.contains($0) }
      }
      .sorted {
        let lhsCoverage = $0.scenarioIDs.filter { enabledScenarioIDs.contains($0) }.count
        let rhsCoverage = $1.scenarioIDs.filter { enabledScenarioIDs.contains($0) }.count
        if lhsCoverage == rhsCoverage { return $0.title < $1.title }
        return lhsCoverage > rhsCoverage
      }
      .first
  }

  private static func contender(
    _ contenderID: String,
    matches experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> Bool {
    config.tournamentContenders.contains {
      $0.id == contenderID && $0.experimentID == experiment.id
    }
  }

  private static func shouldRunPersonaModelRejectionCheck(
    _ readiness: ProductTournamentReadiness
  ) -> Bool {
    readiness.completedRunCount >= 2
      && (readiness.readinessScore <= 40
        || readiness.averageScore > 0 && readiness.averageScore <= 2.5
        || readiness.weakestVerdict == .rejected)
  }

  private static func prepareWorktreeActionIfNeeded(
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> ProductTournamentNextAction? {
    guard (action.kind == .runCohort || action.kind == .rerunCohort),
      let cohortID = action.cohortID,
      let cohort = config.scenarioCohorts.first(where: {
        $0.id == cohortID && $0.experimentID == experiment.id
      }),
      let readiness = cohortRunReadiness(
        for: action,
        experiment: experiment,
        config: config
      ),
      readiness.cohortEnabled,
      readiness.enabledScenarioCount > 0,
      readiness.missingTargetCommitCount > 0,
      targetCommit(for: experiment) == nil
    else { return nil }
    let isCandidateTrack =
      cohort.tags.contains("discover") && cohort.tags.contains("candidate-implementation-track")
    let isRoundTwoProofGapValidation =
      action.title == "Validate Round 2 proof-gap revision"
      || action.title == "Complete Round 2 proof-gap validation"
    let isRoundThreeImplementationRevisionValidation =
      action.title == "Validate Round 3 implementation revision"
      || action.title == "Complete Round 3 implementation validation"
    let isRoundThreeProductImplementationProof = action.title.hasPrefix("Run Round 3")
      || action.title == "Broaden Round 3 persona proof"
    guard isCandidateTrack || isRoundTwoProofGapValidation
      || isRoundThreeImplementationRevisionValidation || isRoundThreeProductImplementationProof
    else { return nil }

    let scenarioText =
      isRoundTwoProofGapValidation
      ? "Round 2 revision validation scenario needs"
      : isRoundThreeImplementationRevisionValidation
      ? "Round 3 implementation revision validation scenario needs"
      : isRoundThreeProductImplementationProof
      ? "Round 3 product implementation proof scenario needs"
      : readiness.missingTargetCommitCount == 1
      ? "1 candidate starter scenario needs"
      : "\(readiness.missingTargetCommitCount) candidate starter scenarios need"
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .prepareWorktree,
      title: "Prepare implementation worktree",
      detail:
        "\(scenarioText) a target commit before simulated-user evidence can run; prepare or refresh worktree `\(experiment.worktreeID)` on branch `\(experiment.branchName)` for cohort `\(cohort.id)`.",
      priority: min(99, max(action.priority + 2, 92)),
      cohortID: cohort.id
    )
  }

  private static func targetCommit(for experiment: ProductTournamentExperiment) -> String? {
    let commit = experiment.currentSha ?? experiment.baseSha
    let trimmed = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func nextAction(
    for signal: TournamentAutomationTargetedProofOutcomeSignal
  ) -> ProductTournamentNextAction {
    let runnableCohortID: String?
    switch signal.actionKind {
    case .runCohort, .rerunCohort:
      runnableCohortID = signal.targetCohortID
    case .applyDecision, .applyRoundTransition, .prepareWorktree, .runPlanProof, .repairFailures,
      .refineContender, .reviewDecision:
      runnableCohortID = nil
    }
    return ProductTournamentNextAction(
      experimentID: signal.experimentID,
      kind: signal.actionKind,
      title: signal.title,
      detail: signal.displayDetail,
      priority: signal.priority,
      cohortID: runnableCohortID,
      requiredSimulationMode: signal.requiredSimulationMode,
      targetPersonaID: signal.targetPersonaID,
      targetPersonaName: signal.targetPersonaName,
      targetScenarioID: signal.targetScenarioID,
      targetDecision: signal.recommendedDecision ?? signal.targetDecision
    )
  }

  private static func liftCutDecisionHint(
    for recommendation: ProductTournamentReadinessRecommendation
  ) -> ProductTournamentExperimentDecision? {
    switch recommendation {
    case .promote:
      return .promote
    case .kill:
      return .kill
    case .gatherEvidence, .keepGoing, .narrow, .pivot:
      return nil
    }
  }

  private static func personaModelBreadthAction(
    experiment: ProductTournamentExperiment,
    selectedCohort: ProductScenarioCohort?,
    target: PersonaModelTarget?,
    title: String,
    decisionGate: String,
    gateReason: String,
    targetDecision: ProductTournamentExperimentDecision,
    priority: Int,
    observedCount: Int,
    observedEvidenceLabel: String
  ) -> ProductTournamentNextAction {
    let executableCohortID = target?.executableCohortID
    let executableScenarioID = target?.executableScenarioID
    let canRunTarget = executableCohortID != nil && executableScenarioID != nil
    let guidance =
      target?.guidance(selectedCohort: selectedCohort, executableCohortID: executableCohortID)
      ?? " Target simulated-user segment: add an enabled scenario for an untested segment."
    let detail: String
    if let executableCohortID, executableScenarioID != nil {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); run the targeted persona-model scenario in cohort `\(executableCohortID)` before \(decisionGate).\(guidance)"
    } else if let selectedCohort {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); cohort `\(selectedCohort.id)` does not cover a runnable simulated-user target before \(decisionGate).\(guidance)"
    } else {
      detail =
        "Current evidence has \(observedCount) \(observedEvidenceLabel), but \(gateReason); define an enabled persona-model scenario cohort before \(decisionGate).\(guidance)"
    }
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: canRunTarget ? .runCohort : .refineContender,
      title: title,
      detail: detail,
      priority: priority,
      cohortID: executableCohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target?.id,
      targetPersonaName: target?.name,
      targetScenarioID: executableScenarioID,
      targetDecision: targetDecision
    )
  }

  private struct PersonaModelTarget: Equatable, Sendable {
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
          " Target simulated-user segment: \(name) via scenario `\(scenarioID)` in cohort `\(executableCohortID)`."
      }
      if let scenarioID, let selectedCohort {
        return
          " Target simulated-user segment: \(name); add scenario `\(scenarioID)` to cohort `\(selectedCohort.id)` or enable a cohort that includes it."
      }
      if let scenarioID {
        return
          " Target simulated-user segment: \(name); enable a cohort that includes scenario `\(scenarioID)`."
      }
      return " Target simulated-user segment: \(name); add an enabled scenario for this segment."
    }
  }

  private static func missingPersonaModelTarget(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    cohort: ProductScenarioCohort?,
    testedPersonaIDs explicitTestedPersonaIDs: Set<String>? = nil
  ) -> PersonaModelTarget? {
    let testedPersonaIDs =
      explicitTestedPersonaIDs
      ?? Set(
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
      return PersonaModelTarget(
        id: scenario.segmentID,
        name: segmentName(for: scenario.segmentID, config: config),
        scenarioID: scenario.id,
        executableCohortID: cohort?.id
      )
    }

    let candidateSegmentIDs = targetSegmentIDs(for: experiment, config: config)
    guard
      let segmentID = candidateSegmentIDs.first(where: { segmentID in
        !testedPersonaIDs.contains(segmentID)
      })
    else { return nil }
    let scenario = enabledScenarios.filter { scenario in
      scenario.segmentID == segmentID
    }
    .sorted(by: scenarioSort(config: config))
    .first
    return PersonaModelTarget(
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

  private static func personaModelCurrentAlternativePersonaIDs(
    for experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
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
    _ summary: ProductTournamentEvidenceSummary
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
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> [String] {
    let contenderPlan = config.contenderPlans.first { $0.id == experiment.contenderPlanID }
    let painID = contenderPlan?.painID
    var segmentIDs: [String] = []
    if let contenderPlan {
      segmentIDs.append(contentsOf: contenderPlan.targetSegmentIDs)
    }
    segmentIDs.append(
      contentsOf: config.userSegments
        .filter { painID == nil || $0.painID == painID }
        .map(\.id))
    segmentIDs.append(
      contentsOf: config.scenarios
        .filter { $0.experimentID == experiment.id }
        .map(\.segmentID))
    return orderedUnique(segmentIDs)
  }

  private static func segmentName(for segmentID: String, config: ProductTournamentConfig) -> String
  {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }

  private static func scenarioSort(
    config: ProductTournamentConfig
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
    to action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction {
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
    to action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction {
    if let revisionAudit =
      TournamentAutomationCycleLearningAdvisor
      .appliedTargetedProofOutcomeRevisionAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let validationAction = targetedProofOutcomeValidationAction(
        after: revisionAudit,
        replacing: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    {
      return validationAction
    }
    if let audit = TournamentAutomationCycleLearningAdvisor.stalledTargetedProofOutcomeAudit(
      for: action,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Retarget tournament proof outcome",
        detail:
          "Recent tournament automation cycle \(audit.id) reran the same targeted tournament proof outcome and it is still present (\(audit.summary)); revise the product implementation, scenario, target persona, or decision criteria before retrying.",
        priority: min(98, max(action.priority + 1, 87)),
        requiredSimulationMode: .personaModel,
        targetPersonaID: action.targetPersonaID,
        targetPersonaName: action.targetPersonaName,
        targetScenarioID: action.targetScenarioID,
        targetDecision: action.targetDecision
      )
    }
    if let audit = TournamentAutomationCycleLearningAdvisor.stalledEvidenceTensionAudit(
      for: action,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Retarget split tournament evidence",
        detail:
          "Recent tournament automation cycle \(audit.id) reran the split-evidence target without resolving the contradiction (\(audit.summary)); revise the scenario, persona, product implementation, or decision criteria before retrying.",
        priority: min(98, max(action.priority + 1, 86)),
        targetPersonaID: action.targetPersonaID,
        targetPersonaName: action.targetPersonaName,
        targetScenarioID: action.targetScenarioID,
        targetDecision: action.targetDecision
      )
    }
    if let audit = TournamentAutomationCycleLearningAdvisor.stalledRationaleSignalAudit(
      for: action,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      if let fatigueAudit = TournamentAutomationCycleLearningAdvisor.revisionFatigueAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ) {
        return revisionFatigueAction(
          after: fatigueAudit,
          replacing: action,
          experiment: experiment,
          evidenceIndex: evidenceIndex
        )
      }
      if let revisionAudit = TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: action,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
        let validationAction = revisionValidationAction(
          after: revisionAudit,
          stalledAudit: audit,
          replacing: action,
          experiment: experiment
        )
      {
        return validationAction
      }
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Retarget simulated-user rationale signal",
        detail:
          "Recent tournament automation cycle \(audit.id) reran the same simulated-user rationale target and the rationale is still present (\(audit.summary)); revise the product implementation, scenario, current-alternative proof, or decision criteria before retrying.",
        priority: min(98, max(action.priority + 1, 86)),
        requiredSimulationMode: .personaModel,
        targetPersonaID: action.targetPersonaID,
        targetPersonaName: action.targetPersonaName,
        targetScenarioID: action.targetScenarioID,
        targetDecision: action.targetDecision
      )
    }
    guard
      let audit = TournamentAutomationCycleLearningAdvisor.stalledProofDebtAudit(
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
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .refineContender,
      title: "Retarget stalled proof debt",
      detail:
        "Recent tournament automation cycle \(audit.id) ran broad evidence without reducing proof debt (\(audit.summary)); retarget the scenario cohort, persona, or current-alternative proof before rerunning broad evidence.",
      priority: min(98, max(action.priority + 1, 84))
    )
  }

  private static func targetedProofOutcomeValidationAction(
    after audit: TournamentAutomationCycleAudit,
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let signal = TournamentAutomationTargetedProofOutcomeAdvisor.signal(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let cohortID = signal.targetCohortID,
      let scenarioID = signal.targetScenarioID
    else { return nil }
    let targetName = signal.targetPersonaName ?? "the target simulated user"
    let targetDecision =
      action.targetDecision ?? signal.recommendedDecision ?? signal.targetDecision
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Validate targeted tournament proof revision",
      detail:
        "Recent tournament automation cycle \(audit.id) applied a targeted tournament proof revision; rerun the persona-model scenario for \(targetName) before applying the same revision again.",
      priority: min(99, max(action.priority + 3, 90)),
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: signal.targetPersonaID,
      targetPersonaName: signal.targetPersonaName,
      targetScenarioID: scenarioID,
      targetDecision: targetDecision
    )
  }

  private struct RevisionValidationTarget: Equatable, Sendable {
    var scenarioID: String
    var cohortID: String?
    var personaID: String?
    var personaName: String?
  }

  private static func roundTwoProofGapRevisionValidationAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let brief = TournamentAutomationRevisionBriefAdvisor.roundTwoProofGapBrief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let audit = TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: brief,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let target = revisionValidationTarget(
        after: audit,
        brief: brief,
        experiment: experiment,
        config: config
      )
    else { return nil }

    let targetName = target.personaName ?? "the target simulated user"
    let targetDecision = brief.targetDecision ?? .narrow
    guard let cohortID = target.cohortID else {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Enable Round 2 proof-gap validation",
        detail:
          "Recent tournament automation cycle \(audit.id) applied a Round 2 proof-gap revision to scenario `\(target.scenarioID)`, but no enabled cohort contains that scenario. Enable or add a cohort for the revision scenario before applying the same proof-gap revision again.",
        priority: min(99, max(brief.priority + 2, 90)),
        requiredSimulationMode: .personaModel,
        targetPersonaID: target.personaID,
        targetPersonaName: target.personaName,
        targetScenarioID: target.scenarioID,
        targetDecision: targetDecision
      )
    }

    let validationAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Validate Round 2 proof-gap revision",
      detail:
        "Recent tournament automation cycle \(audit.id) applied a Round 2 proof-gap revision; rerun persona-model scenario `\(target.scenarioID)` for \(targetName) in cohort `\(cohortID)` before applying the same proof-gap revision again. Proof plan: \(brief.proofPlan)",
      priority: min(99, max(brief.priority + 3, 91)),
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target.personaID,
      targetPersonaName: target.personaName,
      targetScenarioID: target.scenarioID,
      targetDecision: targetDecision
    )
    return prepareWorktreeActionIfNeeded(
      replacing: validationAction,
      experiment: experiment,
      config: config
    ) ?? validationAction
  }

  private static func roundTwoProofGapPartialValidationAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let result = ProductTournamentRoundTwoProofGapValidationAdvisor.results(
        config: config,
        evidenceIndex: evidenceIndex,
        limit: 8
      )
      .first(where: {
        $0.experimentID == experiment.id && $0.outcome == .partialValidation
      })
    else { return nil }

    let latestAudit = ProductTournamentRoundTwoProofGapValidationAdvisor
      .latestAppliedProofGapRevisionAudit(for: experiment.id, config: config)
    let audit = config.tournamentAutomationCycleAudits.first {
      $0.id == result.revisionAuditID
    } ?? latestAudit
    guard
      let audit,
      let target = revisionValidationTarget(
        after: audit,
        brief: nil,
        scenarioID: result.revisionScenarioID,
        experiment: experiment,
        config: config
      )
    else { return nil }

    let personaTarget = roundTwoProofGapValidationPersonaTarget(
      after: audit,
      result: result,
      revisionTarget: target,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let actionCohortID = personaTarget?.executableCohortID ?? target.cohortID
    let actionScenarioID = personaTarget?.executableScenarioID ?? target.scenarioID
    let actionPersonaID = personaTarget?.id ?? target.personaID
    let actionPersonaName = personaTarget?.name ?? target.personaName
    let targetName = actionPersonaName ?? "the target simulated user"
    let gapSummary =
      result.persistedProofGaps.isEmpty
      ? "the remaining Round 2 proof threshold"
      : result.persistedProofGaps.prefix(3).joined(separator: "; ")
    guard let cohortID = actionCohortID else {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Enable Round 2 proof-gap validation",
        detail:
          "Round 2 proof-gap validation after audit \(result.revisionAuditID) is partial (\(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s)), but no enabled cohort contains scenario `\(actionScenarioID)`. Enable or add a cohort for the revision validation scenario before deciding the Round 2 transition.",
        priority: 92,
        requiredSimulationMode: .personaModel,
        targetPersonaID: actionPersonaID,
        targetPersonaName: actionPersonaName,
        targetScenarioID: actionScenarioID,
        targetDecision: .narrow
      )
    }

    let validationAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Complete Round 2 proof-gap validation",
      detail:
        "Round 2 proof-gap validation after audit \(result.revisionAuditID) is partial (\(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s)); rerun persona-model scenario `\(actionScenarioID)` for \(targetName) in cohort `\(cohortID)` to close \(gapSummary) before applying another revision or transition. Proof plan: \(result.nextValidationTarget)",
      priority: 94,
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: actionPersonaID,
      targetPersonaName: actionPersonaName,
      targetScenarioID: actionScenarioID,
      targetDecision: .narrow
    )
    return prepareWorktreeActionIfNeeded(
      replacing: validationAction,
      experiment: experiment,
      config: config
    ) ?? validationAction
  }

  private static func roundThreeImplementationRevisionValidationAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let brief = TournamentAutomationRevisionBriefAdvisor.roundThreeImplementationRevisionBrief(
        for: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let audit = TournamentAutomationCycleLearningAdvisor.appliedRevisionBriefAudit(
        for: brief,
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      ),
      let target = revisionValidationTarget(
        after: audit,
        brief: brief,
        experiment: experiment,
        config: config
      )
    else { return nil }

    let targetName = target.personaName ?? "the target simulated user"
    guard let cohortID = target.cohortID else {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Enable Round 3 implementation validation",
        detail:
          "Recent tournament automation cycle \(audit.id) applied a Round 3 implementation revision to scenario `\(target.scenarioID)`, but no enabled cohort contains that scenario. Enable or add a cohort for the revision scenario before selecting a tournament winner.",
        priority: min(99, max(brief.priority + 2, 90)),
        requiredSimulationMode: .personaModel,
        targetPersonaID: target.personaID,
        targetPersonaName: target.personaName,
        targetScenarioID: target.scenarioID,
        targetDecision: .promote
      )
    }

    let validationAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Validate Round 3 implementation revision",
      detail:
        "Recent tournament automation cycle \(audit.id) applied a Round 3 implementation revision; rerun persona-model scenario `\(target.scenarioID)` for \(targetName) in cohort `\(cohortID)` before selecting a tournament winner or applying the same implementation revision again. Proof plan: \(brief.proofPlan)",
      priority: min(99, max(brief.priority + 3, 91)),
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target.personaID,
      targetPersonaName: target.personaName,
      targetScenarioID: target.scenarioID,
      targetDecision: .promote
    )
    return prepareWorktreeActionIfNeeded(
      replacing: validationAction,
      experiment: experiment,
      config: config
    ) ?? validationAction
  }

  private static func roundThreeImplementationRevisionPartialValidationAction(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard
      let result = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
        config: config,
        evidenceIndex: evidenceIndex,
        limit: 8
      )
      .first(where: {
        $0.experimentID == experiment.id && $0.outcome == .partialValidation
      })
    else { return nil }

    let latestAudit = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
      .latestAppliedImplementationRevisionAudit(for: experiment.id, config: config)
    let audit = config.tournamentAutomationCycleAudits.first {
      $0.id == result.revisionAuditID
    } ?? latestAudit
    guard
      let audit,
      let target = revisionValidationTarget(
        after: audit,
        brief: nil,
        scenarioID: result.revisionScenarioID,
        experiment: experiment,
        config: config
      )
    else { return nil }

    let personaTarget = roundThreeImplementationRevisionValidationPersonaTarget(
      after: audit,
      result: result,
      revisionTarget: target,
      experiment: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let actionCohortID = personaTarget?.executableCohortID ?? target.cohortID
    let actionScenarioID = personaTarget?.executableScenarioID ?? target.scenarioID
    let actionPersonaID = personaTarget?.id ?? target.personaID
    let actionPersonaName = personaTarget?.name ?? target.personaName
    let targetName = actionPersonaName ?? "the target simulated user"
    let gapSummary =
      result.persistedProofGaps.isEmpty
      ? "the remaining Round 3 winner threshold"
      : result.persistedProofGaps.prefix(3).joined(separator: "; ")
    guard let cohortID = actionCohortID else {
      return ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .refineContender,
        title: "Enable Round 3 implementation validation",
        detail:
          "Round 3 implementation validation after audit \(result.revisionAuditID) is partial (\(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s)), but no enabled cohort contains scenario `\(actionScenarioID)`. Enable or add a cohort for the revision validation scenario before selecting a winner.",
        priority: 92,
        requiredSimulationMode: .personaModel,
        targetPersonaID: actionPersonaID,
        targetPersonaName: actionPersonaName,
        targetScenarioID: actionScenarioID,
        targetDecision: .promote
      )
    }

    let validationAction = ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Complete Round 3 implementation validation",
      detail:
        "Round 3 implementation validation after audit \(result.revisionAuditID) is partial (\(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s)); rerun persona-model scenario `\(actionScenarioID)` for \(targetName) in cohort `\(cohortID)` to close \(gapSummary) before selecting a winner or applying another implementation revision. Proof plan: \(result.nextValidationTarget)",
      priority: 94,
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: actionPersonaID,
      targetPersonaName: actionPersonaName,
      targetScenarioID: actionScenarioID,
      targetDecision: .promote
    )
    return prepareWorktreeActionIfNeeded(
      replacing: validationAction,
      experiment: experiment,
      config: config
    ) ?? validationAction
  }

  private static func roundTwoProofGapValidationPersonaTarget(
    after audit: TournamentAutomationCycleAudit,
    result: ProductTournamentRoundTwoProofGapValidationResult,
    revisionTarget: RevisionValidationTarget,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> PersonaModelTarget? {
    guard
      let validationScenarioIDs = ProductTournamentRoundTwoProofGapValidationAdvisor
        .validationScenarioIDs(
          after: audit,
          experimentID: experiment.id,
          config: config
        )
    else { return nil }
    let scopedSummaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == result.tournamentID
          && $0.roundID == result.roundID
          && $0.contenderID == result.contenderID
      }
    let validationSummaries = ProductTournamentRoundTwoProofGapValidationAdvisor
      .validationSummaries(
        in: scopedSummaries,
        after: audit,
        scenarioID: result.revisionScenarioID,
        scenarioIDs: validationScenarioIDs
      )
    let testedPersonaIDs = Set(
      validationSummaries
        .filter { $0.isCompleted && $0.mode == .personaModel }
        .map(\.personaID)
        .filter { !$0.isEmpty }
    )
    guard testedPersonaIDs.count < 2 else { return nil }

    let validationCohort = revisionTarget.cohortID.flatMap { cohortID in
      config.scenarioCohorts.first {
        $0.id == cohortID && $0.experimentID == experiment.id && $0.enabled
      }
    }
    let candidates = config.scenarios
      .filter {
        $0.experimentID == experiment.id
          && $0.enabled
          && validationScenarioIDs.contains($0.id)
          && !testedPersonaIDs.contains($0.segmentID)
      }
      .sorted(by: scenarioSort(config: config))
    guard let scenario = candidates.first else { return nil }
    let targetCohortID =
      validationCohort?.scenarioIDs.contains(scenario.id) == true
      ? validationCohort?.id
      : executableCohortID(forScenarioID: scenario.id, experiment: experiment, config: config)
    return PersonaModelTarget(
      id: scenario.segmentID,
      name: segmentName(for: scenario.segmentID, config: config),
      scenarioID: scenario.id,
      executableCohortID: targetCohortID
    )
  }

  private static func roundThreeImplementationRevisionValidationPersonaTarget(
    after audit: TournamentAutomationCycleAudit,
    result: ProductTournamentRoundThreeImplementationRevisionValidationResult,
    revisionTarget: RevisionValidationTarget,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> PersonaModelTarget? {
    guard
      let validationScenarioIDs = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
        .validationScenarioIDs(
          after: audit,
          experimentID: experiment.id,
          config: config
        )
    else { return nil }
    let scopedSummaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == result.tournamentID
          && $0.roundID == result.roundID
          && $0.contenderID == result.contenderID
      }
    let validationSummaries = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
      .validationSummaries(
        in: scopedSummaries,
        after: audit,
        scenarioID: result.revisionScenarioID,
        scenarioIDs: validationScenarioIDs
      )
    let testedPersonaIDs = Set(
      validationSummaries
        .filter { $0.isCompleted && $0.mode == .personaModel }
        .map(\.personaID)
        .filter { !$0.isEmpty }
    )
    guard testedPersonaIDs.count < 2 else { return nil }

    let validationCohort = revisionTarget.cohortID.flatMap { cohortID in
      config.scenarioCohorts.first {
        $0.id == cohortID && $0.experimentID == experiment.id && $0.enabled
      }
    }
    let candidates = config.scenarios
      .filter {
        $0.experimentID == experiment.id
          && $0.enabled
          && validationScenarioIDs.contains($0.id)
          && !testedPersonaIDs.contains($0.segmentID)
      }
      .sorted(by: scenarioSort(config: config))
    guard let scenario = candidates.first else { return nil }
    let targetCohortID =
      validationCohort?.scenarioIDs.contains(scenario.id) == true
      ? validationCohort?.id
      : executableCohortID(forScenarioID: scenario.id, experiment: experiment, config: config)
    return PersonaModelTarget(
      id: scenario.segmentID,
      name: segmentName(for: scenario.segmentID, config: config),
      scenarioID: scenario.id,
      executableCohortID: targetCohortID
    )
  }

  private static func revisionValidationTarget(
    after audit: TournamentAutomationCycleAudit,
    brief: TournamentAutomationRevisionBrief?,
    scenarioID providedScenarioID: String? = nil,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> RevisionValidationTarget? {
    guard
      let scenarioID = providedScenarioID
        ?? revisionScenarioID(from: audit, experimentID: experiment.id)
        ?? brief?.targetScenarioID
    else { return nil }
    let scenario = config.scenarios.first {
      $0.id == scenarioID && $0.experimentID == experiment.id
    }
    let personaID = scenario?.segmentID ?? brief?.targetPersonaID
    let personaName =
      personaID.map { segmentName(for: $0, config: config) } ?? brief?.targetPersonaName
    let cohortID =
      executableCohortID(forScenarioID: scenarioID, experiment: experiment, config: config)
      ?? brief?.targetCohortID
    return RevisionValidationTarget(
      scenarioID: scenarioID,
      cohortID: cohortID,
      personaID: personaID,
      personaName: personaName
    )
  }

  private static func revisionScenarioID(
    from audit: TournamentAutomationCycleAudit,
    experimentID: String
  ) -> String? {
    let prefix = "\(experimentID):\(TournamentAutomationStepKind.applyRevision.rawValue):"
    for stepID in audit.executedStepIDs where stepID.hasPrefix(prefix) {
      var target = String(stepID.dropFirst(prefix.count))
      if let decisionRange = target.range(of: ":target_decision:") {
        target = String(target[..<decisionRange.lowerBound])
      }
      if !target.isEmpty && target != "none" {
        return target
      }
    }
    return nil
  }

  private static func revisionFatigueAction(
    after audit: TournamentAutomationCycleAudit,
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction {
    let readiness = evidenceIndex.currentTournamentReadiness(for: experiment)
    let targetDecision = revisionFatigueTargetDecision(
      readiness: readiness,
      currentDecision: experiment.decision
    )
    let targetDetail =
      targetDecision.map {
        "Review whether to mark the contender \($0.rawValue) before more contender revisions."
      } ?? "Review whether to narrow, pivot, or kill before more contender revisions."
    let detail = [
      "Recent tournament automation cycle \(audit.id) repeated a contender revision validation.",
      "The same simulated-user rationale still survived (\(audit.summary)).",
      targetDetail,
    ].joined(separator: " ")
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .reviewDecision,
      title: "Review revision fatigue",
      detail: detail,
      priority: min(99, max(action.priority + 5, 94)),
      requiredSimulationMode: .personaModel,
      targetPersonaID: action.targetPersonaID,
      targetPersonaName: action.targetPersonaName,
      targetScenarioID: action.targetScenarioID,
      targetDecision: targetDecision
    )
  }

  private static func revisionFatigueTargetDecision(
    readiness: ProductTournamentReadiness?,
    currentDecision: ProductTournamentExperimentDecision
  ) -> ProductTournamentExperimentDecision? {
    let shouldKill =
      readiness?.recommendation == .kill
      || readiness.map { $0.readinessScore <= 40 } == true
      || readiness?.weakestVerdict == .rejected
    if shouldKill {
      switch currentDecision {
      case .keepGoing, .narrow, .pivot:
        return .kill
      case .notRun, .kill, .promote, .archived, .promoted:
        return nil
      }
    }
    switch currentDecision {
    case .keepGoing:
      return .narrow
    case .narrow:
      return .pivot
    case .pivot:
      return .kill
    case .notRun, .kill, .promote, .archived, .promoted:
      return nil
    }
  }

  private static func revisionValidationAction(
    after revisionAudit: TournamentAutomationCycleAudit,
    stalledAudit: TournamentAutomationCycleAudit,
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment
  ) -> ProductTournamentNextAction? {
    guard let cohortID = action.cohortID,
      action.targetScenarioID != nil
    else { return nil }
    let targetName = action.targetPersonaName ?? "the target simulated user"
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .rerunCohort,
      title: "Validate contender revision",
      detail:
        "Recent tournament automation cycle \(revisionAudit.id) applied a contender revision after stalled rationale audit \(stalledAudit.id); rerun the targeted persona-model scenario for \(targetName) before revising again.",
      priority: min(99, max(action.priority + 3, 90)),
      cohortID: cohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: action.targetPersonaID,
      targetPersonaName: action.targetPersonaName,
      targetScenarioID: action.targetScenarioID,
      targetDecision: action.targetDecision
    )
  }

  private static func stalledProofDebtRetargetAction(
    audit: TournamentAutomationCycleAudit,
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction? {
    guard let readiness = evidenceIndex.currentTournamentReadiness(for: experiment),
      !readiness.proofDebt.isClear
    else { return nil }
    let selectedCohort =
      action.cohortID.flatMap { cohortID in
        config.scenarioCohorts.first {
          $0.id == cohortID && $0.experimentID == experiment.id
        }
      } ?? runnableCohort(for: experiment, config: config)
    if readiness.proofDebt.personaModelSimulatedUserDeficit > 0 {
      return retargetedPersonaModelProofDebtAction(
        audit: audit,
        replacing: action,
        experiment: experiment,
        readiness: readiness,
        selectedCohort: selectedCohort,
        target: missingPersonaModelTarget(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex,
          cohort: selectedCohort
        ),
        title: "Retarget persona-model proof debt",
        proofNeed: "\(readiness.proofDebt.personaModelSimulatedUserDeficit) persona-model simulated user(s)"
      )
    }
    if readiness.proofDebt.personaModelCurrentAlternativeDeficit > 0 {
      return retargetedPersonaModelProofDebtAction(
        audit: audit,
        replacing: action,
        experiment: experiment,
        readiness: readiness,
        selectedCohort: selectedCohort,
        target: missingPersonaModelTarget(
          for: experiment,
          config: config,
          evidenceIndex: evidenceIndex,
          cohort: selectedCohort,
          testedPersonaIDs: personaModelCurrentAlternativePersonaIDs(
            for: experiment,
            evidenceIndex: evidenceIndex
          )
        ),
        title: "Retarget persona-model alternative proof",
        proofNeed:
          "\(readiness.proofDebt.personaModelCurrentAlternativeDeficit) persona-model current-alternative proof(s)"
      )
    }
    return nil
  }

  private static func retargetedPersonaModelProofDebtAction(
    audit: TournamentAutomationCycleAudit,
    replacing action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    readiness: ProductTournamentReadiness,
    selectedCohort: ProductScenarioCohort?,
    target: PersonaModelTarget?,
    title: String,
    proofNeed: String
  ) -> ProductTournamentNextAction {
    let executableCohortID = target?.executableCohortID
    let executableScenarioID = target?.executableScenarioID
    let canRunTarget = executableCohortID != nil && executableScenarioID != nil
    let guidance =
      target?.guidance(selectedCohort: selectedCohort, executableCohortID: executableCohortID)
      ?? " Target simulated-user segment: add an enabled scenario for an untested segment."
    let debtSummary = StringUtils.boundedText(readiness.proofDebt.summary, limit: 140)
    let targetName = target?.name ?? "the missing simulated-user segment"
    let targetDecision = action.targetDecision ?? liftCutDecisionHint(for: readiness.recommendation)
    let detail: String
    if canRunTarget {
      detail =
        "Recent tournament automation cycle \(audit.id) ran broad evidence without reducing proof debt; run a targeted persona-model scenario for \(targetName) to pay down \(proofNeed). Remaining proof debt: \(debtSummary)."
    } else if let selectedCohort {
      let cohortTitle = StringUtils.boundedText(selectedCohort.title, limit: 80)
      detail =
        "Recent tournament automation cycle \(audit.id) ran broad evidence without reducing proof debt; cohort \(cohortTitle) does not cover a runnable simulated-user target for \(proofNeed). \(guidance) Remaining proof debt: \(debtSummary)."
    } else {
      detail =
        "Recent tournament automation cycle \(audit.id) ran broad evidence without reducing proof debt; define an enabled persona-model scenario cohort for \(proofNeed).\(guidance) Remaining proof debt: \(debtSummary)."
    }
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: canRunTarget ? .runCohort : .refineContender,
      title: title,
      detail: detail,
      priority: min(98, max(action.priority + 2, 86)),
      cohortID: executableCohortID,
      requiredSimulationMode: .personaModel,
      targetPersonaID: target?.id,
      targetPersonaName: target?.name,
      targetScenarioID: executableScenarioID,
      targetDecision: targetDecision
    )
  }

  private static func applyingRecentCycleFailureGuard(
    to action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentNextAction {
    guard action.kind == .prepareWorktree || action.kind == .runCohort || action.kind == .rerunCohort,
      let audit = TournamentAutomationCycleFailureAdvisor.blockingAudit(
        forStepID: TournamentAutomationCycleFailureAdvisor.stepID(for: action),
        experiment: experiment,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else { return action }
    return ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .repairFailures,
      title: "Repair tournament automation failure",
      detail:
        "Recent tournament automation cycle \(audit.id) failed while running the suggested cohort; repair the generated app contract, runner, scenario, or cohort before retrying. \(audit.stopDetail)",
      priority: min(99, max(action.priority + 1, 86))
    )
  }

  static func cohortRunReadiness(
    for action: ProductTournamentNextAction,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
  ) -> ProductTournamentCohortRunReadiness? {
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
    let runnableScenarios =
      action.targetScenarioID.map { targetScenarioID in
        enabledScenarios.filter { $0.id == targetScenarioID }
      } ?? enabledScenarios
    let missingTargetCommitCount = runnableScenarios.filter {
      targetCommit(for: $0, experiment: experiment) == nil
    }.count
    return ProductTournamentCohortRunReadiness(
      cohortID: cohort.id,
      cohortTitle: cohort.title,
      cohortEnabled: cohort.enabled,
      enabledScenarioCount: cohort.enabled ? runnableScenarios.count : 0,
      missingTargetCommitCount: cohort.enabled ? missingTargetCommitCount : 0,
      targetScenarioID: action.targetScenarioID
    )
  }

  private static func runnableCohort(
    for experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig
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
    experiment: ProductTournamentExperiment
  ) -> String? {
    let commit = scenario.targetCommitSha ?? experiment.currentSha ?? experiment.baseSha
    let trimmed = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}

enum ProductTournamentDecisionAdvisor {
  static func proposals(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentDecisionProposal] {
    return config.tournamentExperiments.compactMap { experiment in
      guard let readiness = evidenceIndex.currentTournamentReadiness(for: experiment),
        let target = targetDecision(for: readiness, current: experiment.decision),
        target != experiment.decision,
        !TournamentAutomationEvidenceTensionAdvisor.blocksAutomaticDecision(
          targetDecision: target,
          experiment: experiment,
          evidenceIndex: evidenceIndex
        )
      else { return nil }
      let summary = summary(for: readiness, target: target, experiment: experiment)
      do {
        try ProductTournamentDecisionTransitionValidator.validate(
          experimentID: experiment.id,
          from: experiment.decision,
          to: target,
          summary: summary
        )
      } catch {
        return nil
      }
      let update = ProductTournamentReflectDecisionUpdate(
        experimentID: experiment.id,
        decision: target,
        summary: summary,
        evidenceRunIDs: readiness.evidenceRunIDs,
        decidedBy: "Product Tournament Decision Advisor"
      )
      return ProductTournamentDecisionProposal(
        experimentID: experiment.id,
        currentDecision: experiment.decision,
        update: update,
        readiness: readiness
      )
    }
  }

  static func proposal(
    experimentID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentDecisionProposal? {
    proposals(config: config, evidenceIndex: evidenceIndex)
      .first { $0.experimentID == experimentID }
  }

  static func applyingRecommendedDecision(
    experimentID: String,
    to config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    now: Date = Date()
  ) throws -> ProductTournamentConfig {
    guard
      let proposal = proposal(
        experimentID: experimentID,
        config: config,
        evidenceIndex: evidenceIndex
      )
    else {
      throw ProductTournamentDecisionAdvisorError.noProposal(experimentID)
    }
    return try ProductTournamentReflectDecisionApplier.applying(
      [proposal.update],
      to: config,
      now: now
    )
  }

  private static func targetDecision(
    for readiness: ProductTournamentReadiness,
    current: ProductTournamentExperimentDecision
  ) -> ProductTournamentExperimentDecision? {
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
    for readiness: ProductTournamentReadiness,
    target: ProductTournamentExperimentDecision,
    experiment: ProductTournamentExperiment
  ) -> String {
    let evidence =
      readiness.evidenceRunIDs.isEmpty
      ? "no evidence runs"
      : "evidence \(readiness.evidenceRunIDs.prefix(4).joined(separator: ", "))"
    let rationale = readiness.rationale.prefix(3).joined(separator: " ")
    let proof =
      "\(readiness.personaModelCompletedRunCount) persona-model run(s) across \(readiness.personaModelDistinctPersonaCount) simulated user(s); current-alternative proof from \(readiness.personaModelCurrentAlternativePersonaCount) persona-model simulated user(s)."
    return StringUtils.boundedText(
      """
      Tournament readiness \(readiness.scoreLabel)/100 recommends \(target.rawValue) for \(experiment.title): \(rationale) \(proof) Supporting \(evidence).
      """,
      limit: 1_000
    )
  }
}

enum ProductTournamentReflectDecisionApplier {
  static func applying(
    _ updates: [ProductTournamentReflectDecisionUpdate],
    to config: ProductTournamentConfig,
    now: Date = Date()
  ) throws -> ProductTournamentConfig {
    guard !updates.isEmpty else { return config }

    var next = config
    let timestamp = now.timeIntervalSince1970
    var decisionSequence = next.decisions.count

    for update in updates {
      guard
        let experimentIndex = next.tournamentExperiments.firstIndex(where: {
          $0.id == update.experimentID
        })
      else {
        throw ProductTournamentDecisionTransitionError.unknownExperiment(update.experimentID)
      }

      let currentDecision = next.tournamentExperiments[experimentIndex].decision
      try ProductTournamentDecisionTransitionValidator.validate(
        experimentID: update.experimentID,
        from: currentDecision,
        to: update.decision,
        summary: update.summary
      )

      next.tournamentExperiments[experimentIndex].decision = update.decision
      next.tournamentExperiments[experimentIndex].evidenceSummary =
        update.summary.isEmpty
        ? next.tournamentExperiments[experimentIndex].evidenceSummary
        : update.summary
      next.tournamentExperiments[experimentIndex].updatedAt = timestamp

      decisionSequence += 1
      next.decisions.append(
        ProductTournamentDecision(
          id:
            "\(update.experimentID)-\(update.decision.rawValue)-\(Int(timestamp))-\(decisionSequence)",
          experimentID: update.experimentID,
          decision: update.decision,
          summary: update.summary,
          evidenceRunIDs: update.evidenceRunIDs,
          branchName: next.tournamentExperiments[experimentIndex].branchName,
          beforeSha: next.tournamentExperiments[experimentIndex].currentSha
            ?? next.tournamentExperiments[experimentIndex].baseSha,
          afterSha: next.tournamentExperiments[experimentIndex].currentSha
            ?? next.tournamentExperiments[experimentIndex].baseSha,
          decidedAt: timestamp,
          decidedBy: update.decidedBy
        )
      )
    }

    return next
  }
}
