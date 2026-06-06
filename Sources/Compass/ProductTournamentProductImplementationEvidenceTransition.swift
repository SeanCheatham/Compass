import Foundation

enum ProductTournamentProductImplementationEvidenceRecommendation: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case gatherEvidence = "gather_evidence"
  case selectWinner = "select_winner"
  case reviseImplementation = "revise_implementation"
  case eliminate

  var title: String {
    switch self {
    case .gatherEvidence: return "Gather Evidence"
    case .selectWinner: return "Select Winner"
    case .reviseImplementation: return "Revise"
    case .eliminate: return "Eliminate"
    }
  }
}

struct ProductTournamentProductImplementationEvidenceTransitionProposal: Codable, Equatable, Identifiable,
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
  var recommendation: ProductTournamentProductImplementationEvidenceRecommendation
  var readinessScore: Double
  var averageScore: Double
  var willingnessToPayScore: Double
  var willingnessToPayProofCount: Int
  var runCount: Int
  var completedRunCount: Int
  var failedRunCount: Int
  var distinctPersonaCount: Int
  var currentAlternativeProofCount: Int
  var implementationUseProofCount: Int
  var strongOrPromisingCount: Int
  var weakOrRejectedCount: Int
  var missingCapabilityCount: Int
  var evidenceRunIDs: [String]
  var priority: Int
  var title: String
  var detail: String
  var proofGaps: [String]
  var nextValidationTarget: String
  var rationale: [String]

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var isActionable: Bool {
    switch recommendation {
    case .selectWinner, .reviseImplementation, .eliminate:
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
    let gaps =
      proofGaps.isEmpty
      ? "none"
      : proofGaps.prefix(4).joined(separator: "; ")
    return
      "- round_3_product_implementation contender \(contenderID) [round \(roundID), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, average \(Self.format(averageScore))/5, willingness_to_pay \(Self.format(willingnessToPayScore))/5, willingness_to_pay_proofs \(willingnessToPayProofCount), completed \(completedRunCount)/\(runCount), personas \(distinctPersonaCount), current_alternative_proofs \(currentAlternativeProofCount), implementation_use_proofs \(implementationUseProofCount), missing_capabilities \(missingCapabilityCount), \(evidence), proof_gaps \(Self.bounded(gaps, limit: 260))]: \(detail); next_validation \(Self.bounded(nextValidationTarget, limit: 220))"
  }

  private static func format(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

struct ProductTournamentProductImplementationEvidenceTransitionOutcome: Equatable, Sendable {
  var proposal: ProductTournamentProductImplementationEvidenceTransitionProposal
  var config: ProductTournamentConfig
  var affectedContenderIDs: [String]
  var fromRoundID: String
  var toRoundID: String?

  var userMessage: String {
    switch proposal.recommendation {
    case .selectWinner:
      return
        "Selected \(proposal.contenderTitle) as the product tournament winner from Round 3 product implementation evidence."
    case .reviseImplementation:
      return "Marked \(proposal.contenderTitle) for Round 3 product implementation revision."
    case .eliminate:
      return "Eliminated \(proposal.contenderTitle) after Round 3 product implementation evidence."
    case .gatherEvidence:
      return
        "Round 3 still needs more product implementation evidence for \(proposal.contenderTitle)."
    }
  }
}

enum ProductTournamentRoundThreeImplementationRevisionValidationOutcome: String, Codable, Equatable,
  Sendable
{
  case pendingValidation = "pending_validation"
  case partialValidation = "partial_validation"
  case resolved
  case persisted
  case eliminated

  var title: String {
    switch self {
    case .pendingValidation: return "Pending Validation"
    case .partialValidation: return "Partial Validation"
    case .resolved: return "Resolved"
    case .persisted: return "Persisted"
    case .eliminated: return "Eliminated"
    }
  }
}

struct ProductTournamentRoundThreeImplementationRevisionValidationResult: Equatable, Sendable,
  Identifiable
{
  var id: String { "\(experimentID)-\(revisionAuditID)" }

  var tournamentID: String
  var roundID: String
  var contenderID: String
  var experimentID: String
  var revisionAuditID: String
  var revisionEndedAt: Double
  var revisionScenarioID: String?
  var outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome
  var recommendation: ProductTournamentProductImplementationEvidenceRecommendation
  var readinessScore: Double
  var validationRunIDs: [String]
  var validationRunCount: Int
  var completedValidationRunCount: Int
  var originalProofGaps: [String]
  var resolvedProofGaps: [String]
  var persistedProofGaps: [String]
  var nextValidationTarget: String

  var scoreLabel: String {
    "\(Int(readinessScore.rounded()))"
  }

  var displaySummary: String {
    "\(outcome.title), \(completedValidationRunCount)/\(validationRunCount) validation run(s), readiness \(scoreLabel)/100"
  }

  var displayDetail: String {
    let scenario = revisionScenarioID.map { "scenario \($0)" } ?? "unknown scenario"
    let resolved =
      resolvedProofGaps.isEmpty
      ? "resolved none"
      : "resolved \(resolvedProofGaps.prefix(3).joined(separator: "; "))"
    let persisted =
      persistedProofGaps.isEmpty
      ? "persisted none"
      : "persisted \(persistedProofGaps.prefix(3).joined(separator: "; "))"
    return
      "Audit \(revisionAuditID), \(scenario); \(resolved); \(persisted). Next: \(nextValidationTarget)"
  }

  var contextLine: String {
    let scenario = revisionScenarioID ?? "unknown"
    let runs =
      validationRunIDs.isEmpty
      ? "validation_runs none"
      : "validation_runs \(validationRunIDs.prefix(4).joined(separator: ", "))"
    let audited = originalProofGaps.isEmpty
      ? "audited gaps unavailable"
      : originalProofGaps.prefix(4).joined(separator: "; ")
    let resolved = resolvedProofGaps.isEmpty
      ? "none"
      : resolvedProofGaps.prefix(4).joined(separator: "; ")
    let persisted = persistedProofGaps.isEmpty
      ? "none"
      : persistedProofGaps.prefix(4).joined(separator: "; ")
    return
      "- round_3_implementation_revision_validation contender \(contenderID) [round \(roundID), experiment \(experimentID), audit \(revisionAuditID), scenario \(scenario), outcome \(outcome.rawValue), recommendation \(recommendation.rawValue), readiness \(scoreLabel)/100, completed_validation \(completedValidationRunCount)/\(validationRunCount), \(runs)]: audited \(Self.bounded(audited, limit: 220)); resolved \(Self.bounded(resolved, limit: 180)); persisted \(Self.bounded(persisted, limit: 220)); next \(Self.bounded(nextValidationTarget, limit: 220))."
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

enum ProductTournamentRoundThreeImplementationRevisionValidationAdvisor {
  static func results(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 3
  ) -> [ProductTournamentRoundThreeImplementationRevisionValidationResult] {
    guard limit > 0 else { return [] }
    return ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      config: config,
      evidenceIndex: evidenceIndex
    )
    .compactMap { proposal in
      result(for: proposal, config: config, evidenceIndex: evidenceIndex)
    }
    .sorted { lhs, rhs in
      if lhs.revisionEndedAt == rhs.revisionEndedAt {
        return lhs.contenderID < rhs.contenderID
      }
      return lhs.revisionEndedAt > rhs.revisionEndedAt
    }
    .prefix(limit)
    .map { $0 }
  }

  static func contextLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 3
  ) -> [String] {
    let scopedResults = results(config: config, evidenceIndex: evidenceIndex, limit: limit)
    guard !scopedResults.isEmpty else { return [] }
    return ["Round 3 implementation revision validation:"]
      + scopedResults.map(\.contextLine)
  }

  static func latestAppliedImplementationRevisionAudit(
    for experimentID: String,
    config: ProductTournamentConfig
  ) -> TournamentAutomationCycleAudit? {
    config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .first { audit in
        audit.stopReason != .executionFailed
          && audit.experimentIDs.contains(experimentID)
          && audit.executedStepIDs.contains {
            $0.hasPrefix(
              "\(experimentID):\(TournamentAutomationStepKind.applyRevision.rawValue):"
            )
          }
          && audit.revisionBriefSummaries.contains {
            $0.contains(
              "source \(TournamentAutomationRevisionBriefSource.roundThreeImplementationRevision.rawValue)"
            )
          }
      }
  }

  static func revisionScenarioID(
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

  static func validationSummaries(
    in summaries: [ProductTournamentEvidenceSummary],
    after audit: TournamentAutomationCycleAudit,
    scenarioID: String?,
    scenarioIDs: Set<String>? = nil
  ) -> [ProductTournamentEvidenceSummary] {
    let scopedScenarioIDs =
      scenarioIDs?.filter { !$0.isEmpty }
      ?? scenarioID.map { Set([$0]) }
    return summaries
      .filter { summary in
        summary.endedAt > audit.endedAt
          && (scopedScenarioIDs?.contains(summary.scenarioID) ?? true)
      }
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
        return lhs.endedAt > rhs.endedAt
      }
  }

  static func validationScenarioIDs(
    after audit: TournamentAutomationCycleAudit,
    experimentID: String,
    config: ProductTournamentConfig
  ) -> Set<String>? {
    guard let scenarioID = revisionScenarioID(from: audit, experimentID: experimentID) else {
      return nil
    }
    let enabledScenarioIDs = Set(
      config.scenarios
        .filter { $0.experimentID == experimentID && $0.enabled }
        .map(\.id)
    )
    let cohort = config.scenarioCohorts
      .filter {
        $0.experimentID == experimentID
          && $0.enabled
          && $0.scenarioIDs.contains(scenarioID)
      }
      .sorted {
        if $0.scenarioIDs.count == $1.scenarioIDs.count { return $0.title < $1.title }
        return $0.scenarioIDs.count < $1.scenarioIDs.count
      }
      .first
    guard let cohort else { return [scenarioID] }
    let cohortScenarioIDs = Set(
      cohort.scenarioIDs.filter { enabledScenarioIDs.contains($0) || $0 == scenarioID }
    )
    return cohortScenarioIDs.isEmpty ? [scenarioID] : cohortScenarioIDs
  }

  private static func result(
    for proposal: ProductTournamentProductImplementationEvidenceTransitionProposal,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentRoundThreeImplementationRevisionValidationResult? {
    guard
      let contender = config.tournamentContenders.first(where: {
        $0.id == proposal.contenderID
      }),
      let experimentID = contender.experimentID,
      let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID }),
      let audit = latestAppliedImplementationRevisionAudit(for: experiment.id, config: config)
    else { return nil }

    let scenarioID = revisionScenarioID(from: audit, experimentID: experiment.id)
    let scopedSummaries = evidenceIndex.summaries(for: experiment)
      .filter {
        $0.tournamentID == proposal.tournamentID
          && $0.roundID == proposal.roundID
          && $0.contenderID == proposal.contenderID
      }
    let validationSummaries = validationSummaries(
      in: scopedSummaries,
      after: audit,
      scenarioID: scenarioID,
      scenarioIDs: validationScenarioIDs(
        after: audit,
        experimentID: experiment.id,
        config: config
      )
    )
    let originalGaps = auditedProofGaps(from: audit)
    let outcome = outcome(for: proposal, validationSummaries: validationSummaries)
    let persisted = persistedProofGaps(
      outcome: outcome,
      proposalProofGaps: proposal.proofGaps,
      originalProofGaps: originalGaps
    )

    return ProductTournamentRoundThreeImplementationRevisionValidationResult(
      tournamentID: proposal.tournamentID,
      roundID: proposal.roundID,
      contenderID: proposal.contenderID,
      experimentID: experiment.id,
      revisionAuditID: audit.id,
      revisionEndedAt: audit.endedAt,
      revisionScenarioID: scenarioID,
      outcome: outcome,
      recommendation: proposal.recommendation,
      readinessScore: proposal.readinessScore,
      validationRunIDs: validationSummaries.prefix(8).map(\.runID),
      validationRunCount: validationSummaries.count,
      completedValidationRunCount: validationSummaries.filter(\.isCompleted).count,
      originalProofGaps: originalGaps,
      resolvedProofGaps: resolvedProofGaps(
        outcome: outcome,
        originalProofGaps: originalGaps,
        persistedProofGaps: persisted
      ),
      persistedProofGaps: persisted,
      nextValidationTarget: proposal.nextValidationTarget
    )
  }

  private static func outcome(
    for proposal: ProductTournamentProductImplementationEvidenceTransitionProposal,
    validationSummaries: [ProductTournamentEvidenceSummary]
  ) -> ProductTournamentRoundThreeImplementationRevisionValidationOutcome {
    guard !validationSummaries.isEmpty else { return .pendingValidation }
    switch proposal.recommendation {
    case .selectWinner:
      return .resolved
    case .eliminate:
      return .eliminated
    case .reviseImplementation:
      return .persisted
    case .gatherEvidence:
      return .partialValidation
    }
  }

  private static func persistedProofGaps(
    outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome,
    proposalProofGaps: [String],
    originalProofGaps: [String]
  ) -> [String] {
    switch outcome {
    case .resolved:
      return []
    case .pendingValidation:
      return originalProofGaps.isEmpty ? proposalProofGaps : originalProofGaps
    case .partialValidation, .persisted, .eliminated:
      return proposalProofGaps.isEmpty ? originalProofGaps : proposalProofGaps
    }
  }

  private static func resolvedProofGaps(
    outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome,
    originalProofGaps: [String],
    persistedProofGaps: [String]
  ) -> [String] {
    switch outcome {
    case .resolved:
      return originalProofGaps.isEmpty ? ["all audited Round 3 implementation gaps"] : originalProofGaps
    case .partialValidation, .persisted:
      let resolved = originalProofGaps.filter { original in
        !persistedProofGaps.contains { persisted in
          gapsMatch(original, persisted)
        }
      }
      return Array(resolved.prefix(4))
    case .pendingValidation, .eliminated:
      return []
    }
  }

  private static func auditedProofGaps(
    from audit: TournamentAutomationCycleAudit
  ) -> [String] {
    for summary in audit.revisionBriefSummaries
    where summary.contains(
      "source \(TournamentAutomationRevisionBriefSource.roundThreeImplementationRevision.rawValue)"
    ) {
      let gapText = auditedProofGapText(in: summary)
      let gaps = gapText
        .split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if !gaps.isEmpty {
        return Array(gaps.prefix(6))
      }
    }
    return []
  }

  private static func auditedProofGapText(in summary: String) -> String {
    if let implementationRange = summary.range(
      of: "implementation Revise the low-medium fidelity product implementation against ")
    {
      let text = String(summary[implementationRange.upperBound...])
      return clipped(text, before: [
        " before selecting a tournament winner",
        "; scenario",
        "; proof",
      ])
    }
    if let triggerRange = summary.range(of: "recommends revising contender"),
      let colonRange = summary[triggerRange.upperBound...].range(of: ":")
    {
      let text = String(summary[colonRange.upperBound...])
      return clipped(text, before: [".", "; implementation", "; proof"])
    }
    return ""
  }

  private static func clipped(_ text: String, before markers: [String]) -> String {
    var clipped = text
    for marker in markers {
      if let range = clipped.range(of: marker) {
        clipped = String(clipped[..<range.lowerBound])
      }
    }
    return clipped.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func gapsMatch(_ lhs: String, _ rhs: String) -> Bool {
    let lhsKey = gapKey(lhs)
    let rhsKey = gapKey(rhs)
    return lhsKey == rhsKey
      || lhsKey.contains(rhsKey)
      || rhsKey.contains(lhsKey)
  }

  private static func gapKey(_ value: String) -> String {
    let normalized = value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.contains("willingness") || normalized.contains("pay")
      || normalized.contains("sponsor")
    {
      return "willingness_to_pay"
    }
    if normalized.contains("implementation use") {
      return "implementation_use"
    }
    if normalized.contains("current alternative") {
      return "current_alternative"
    }
    if normalized.contains("missing capability") {
      return "missing_capability"
    }
    if normalized.contains("completed") {
      return "completed_run"
    }
    if normalized.contains("persona") {
      return "persona"
    }
    if normalized.contains("average implementation") {
      return "average_implementation"
    }
    if normalized.contains("readiness") {
      return "readiness"
    }
    if normalized.contains("weak") || normalized.contains("rejected") {
      return "weak_or_rejected"
    }
    return normalized
  }
}

enum ProductTournamentProductImplementationEvidenceTransitionError: LocalizedError, Equatable {
  case unknownTournament(String)
  case unknownRound(String)
  case unsupportedRound(String)
  case unknownContender(String)
  case missingProductImplementationEvidence(String)
  case recommendationNotActionable(String, ProductTournamentProductImplementationEvidenceRecommendation)

  var errorDescription: String? {
    switch self {
    case .unknownTournament(let id):
      return "Product tournament \(id) was not found."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unsupportedRound(let id):
      return "Product tournament round \(id) is not a product implementation round."
    case .unknownContender(let id):
      return "Product tournament contender \(id) was not found."
    case .missingProductImplementationEvidence(let contenderID):
      return "No scoped Round 3 product implementation evidence exists for contender \(contenderID)."
    case .recommendationNotActionable(let contenderID, let recommendation):
      return
        "Round 3 recommendation \(recommendation.rawValue) for contender \(contenderID) is not a tournament transition."
    }
  }
}

enum ProductTournamentProductImplementationEvidenceTransitioner {
  static func proposals(
    tournamentID: String? = nil,
    roundID: String? = nil,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentProductImplementationEvidenceTransitionProposal] {
    activeProductImplementationRounds(
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
  ) -> ProductTournamentProductImplementationEvidenceTransitionProposal? {
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
  ) throws -> ProductTournamentProductImplementationEvidenceTransitionOutcome {
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
      throw ProductTournamentProductImplementationEvidenceTransitionError.missingProductImplementationEvidence(contenderID)
    }
    return try apply(proposal: proposal, to: config, now: now)
  }

  static func apply(
    proposal: ProductTournamentProductImplementationEvidenceTransitionProposal,
    to config: ProductTournamentConfig,
    now: Date = Date()
  ) throws -> ProductTournamentProductImplementationEvidenceTransitionOutcome {
    guard proposal.isActionable else {
      throw ProductTournamentProductImplementationEvidenceTransitionError.recommendationNotActionable(
        proposal.contenderID,
        proposal.recommendation
      )
    }
    guard let tournament = config.tournaments.first(where: { $0.id == proposal.tournamentID })
    else {
      throw ProductTournamentProductImplementationEvidenceTransitionError.unknownTournament(
        proposal.tournamentID)
    }
    guard let round = config.tournamentRounds.first(where: { $0.id == proposal.roundID }) else {
      throw ProductTournamentProductImplementationEvidenceTransitionError.unknownRound(proposal.roundID)
    }
    guard round.kind == .productImplementation else {
      throw ProductTournamentProductImplementationEvidenceTransitionError.unsupportedRound(round.id)
    }
    guard config.tournamentContenders.contains(where: { $0.id == proposal.contenderID }) else {
      throw ProductTournamentProductImplementationEvidenceTransitionError.unknownContender(
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
        updateProductTournamentContenderPlan(for: losingContender.id, in: &next) { contenderPlan in
          contenderPlan.status = .rejected
        }
      }
      updateExperiment(for: proposal.contenderID, in: &next, timestamp: timestamp) { experiment in
        experiment.decision = .promote
      }
      updateProductTournamentContenderPlan(for: proposal.contenderID, in: &next) { contenderPlan in
        contenderPlan.status = .promoted
      }

    case .reviseImplementation:
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
      updateProductTournamentContenderPlan(for: proposal.contenderID, in: &next) { contenderPlan in
        contenderPlan.status = .rejected
      }

    case .gatherEvidence:
      break
    }

    return ProductTournamentProductImplementationEvidenceTransitionOutcome(
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
  ) -> [ProductTournamentProductImplementationEvidenceTransitionProposal] {
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    return contenderIDs.compactMap { contenderID in
      guard
        let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
        contender.isRoundThreeProductImplementationTransitionCandidate
      else { return nil }
      let summaries = evidenceIndex.summaries.filter {
        $0.tournamentID == tournament.id
          && $0.roundID == round.id
          && $0.contenderID == contender.id
      }
      let effectiveSummaries = effectiveSummariesAfterImplementationRevisionIfAvailable(
        summaries,
        contender: contender,
        config: config
      )
      return proposal(
        for: effectiveSummaries,
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
  ) -> ProductTournamentProductImplementationEvidenceTransitionProposal {
    let summaries = rawSummaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    let completed = summaries.filter(\.isCompleted)
    let failedCount = summaries.count - completed.count
    let distinctPersonaCount = Set(completed.map(\.personaID).filter { !$0.isEmpty }).count
    let currentAlternativeProofCount = completed.filter(hasCurrentAlternativeProof).count
    let implementationUseProofCount = completed.filter(hasImplementationUseProof).count
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
    let willingnessToPayProofCount = completed.filter(hasWillingnessToPayProof).count
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
      implementationUseProofCount: implementationUseProofCount,
      willingnessToPayProofCount: willingnessToPayProofCount,
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
      implementationUseProofCount: implementationUseProofCount,
      missingCapabilityCount: missingCapabilityCount
    )
    let proofGaps = proofGaps(
      summaries: summaries,
      completedRunCount: completed.count,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      implementationUseProofCount: implementationUseProofCount,
      willingnessToPayProofCount: willingnessToPayProofCount,
      readinessScore: readinessScore,
      averageScore: averageScore,
      willingnessToPayScore: willingnessToPayScore,
      weakOrRejectedCount: weakCount,
      missingCapabilities: completed.flatMap(\.missingCapabilities),
      objections: completed.flatMap(\.objections),
      recommendation: recommendation
    )
    let nextValidationTarget = nextValidationTarget(
      for: recommendation,
      proofGaps: proofGaps
    )

    return ProductTournamentProductImplementationEvidenceTransitionProposal(
      tournamentID: tournament.id,
      roundID: round.id,
      roundTitle: round.title,
      contenderID: contender.id,
      contenderTitle: contender.title,
      recommendation: recommendation,
      readinessScore: readinessScore,
      averageScore: roundedScore(averageScore, upperBound: 5),
      willingnessToPayScore: roundedScore(willingnessToPayScore, upperBound: 5),
      willingnessToPayProofCount: willingnessToPayProofCount,
      runCount: summaries.count,
      completedRunCount: completed.count,
      failedRunCount: failedCount,
      distinctPersonaCount: distinctPersonaCount,
      currentAlternativeProofCount: currentAlternativeProofCount,
      implementationUseProofCount: implementationUseProofCount,
      strongOrPromisingCount: strongCount,
      weakOrRejectedCount: weakCount,
      missingCapabilityCount: missingCapabilityCount,
      evidenceRunIDs: summaries.prefix(8).map(\.runID),
      priority: priority,
      title: title,
      detail: detail,
      proofGaps: proofGaps,
      nextValidationTarget: nextValidationTarget,
      rationale: rationale(
        completedRunCount: completed.count,
        runCount: summaries.count,
        distinctPersonaCount: distinctPersonaCount,
        currentAlternativeProofCount: currentAlternativeProofCount,
        implementationUseProofCount: implementationUseProofCount,
        willingnessToPayProofCount: willingnessToPayProofCount,
        readinessScore: readinessScore,
        averageScore: averageScore,
        willingnessToPayScore: willingnessToPayScore,
        missingCapabilityCount: missingCapabilityCount,
        repeatedObjectionCount: repeatedObjectionCount,
        recommendation: recommendation
      )
    )
  }

  private static func effectiveSummariesAfterImplementationRevisionIfAvailable(
    _ summaries: [ProductTournamentEvidenceSummary],
    contender: ProductTournamentContender,
    config: ProductTournamentConfig
  ) -> [ProductTournamentEvidenceSummary] {
    guard
      let experimentID = contender.experimentID,
      let audit = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
        .latestAppliedImplementationRevisionAudit(
          for: experimentID,
          config: config
        )
    else { return summaries }
    let scenarioID =
      ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.revisionScenarioID(
        from: audit,
        experimentID: experimentID
      )
    let validationSummaries = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
      .validationSummaries(
        in: summaries,
        after: audit,
        scenarioID: scenarioID,
        scenarioIDs: ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
          .validationScenarioIDs(
            after: audit,
            experimentID: experimentID,
            config: config
          )
      )
    return validationSummaries.isEmpty ? summaries : validationSummaries
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
    implementationUseProofCount: Int,
    willingnessToPayProofCount: Int,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    strongOrPromisingCount: Int,
    weakOrRejectedCount: Int,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int
  ) -> ProductTournamentProductImplementationEvidenceRecommendation {
    guard completedRunCount > 0 else { return .gatherEvidence }
    if completedRunCount >= 2
      && (readinessScore <= 30 || averageScore > 0 && averageScore <= 2.2
        || weakOrRejectedCount >= 2)
    {
      return .eliminate
    }
    if completedRunCount < 3 || distinctPersonaCount < 2 || currentAlternativeProofCount < 2
      || implementationUseProofCount < 3 || willingnessToPayProofCount < 2
    {
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
    return .reviseImplementation
  }

  private static func copy(
    recommendation: ProductTournamentProductImplementationEvidenceRecommendation,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    implementationUseProofCount: Int,
    missingCapabilityCount: Int
  ) -> (String, String) {
    let score = "\(Int(readinessScore.rounded()))"
    let averageLabel = format(averageScore)
    let payLabel = format(willingnessToPayScore)
    switch recommendation {
    case .selectWinner:
      return (
        "Select Tournament Winner",
        "Readiness \(score)/100 with implementation score \(averageLabel)/5, willingness to pay \(payLabel)/5, and \(implementationUseProofCount) implementation-use proof(s)."
      )
    case .reviseImplementation:
      let blocker =
        missingCapabilityCount > 0
        ? "\(missingCapabilityCount) missing capability signal(s)"
        : "mixed implementation pull"
      return (
        "Revise Implementation",
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
        "\(completedRunCount) completed of \(runCount) run(s), \(distinctPersonaCount) persona(s), \(currentAlternativeProofCount) current-alternative proof(s), \(implementationUseProofCount) implementation-use proof(s); Round 3 needs broader winner evidence."
      )
    }
  }

  private static func rationale(
    completedRunCount: Int,
    runCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    implementationUseProofCount: Int,
    willingnessToPayProofCount: Int,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    missingCapabilityCount: Int,
    repeatedObjectionCount: Int,
    recommendation: ProductTournamentProductImplementationEvidenceRecommendation
  ) -> [String] {
    var lines = [
      "\(completedRunCount) completed of \(runCount) Round 3 run(s) across \(distinctPersonaCount) persona(s)."
    ]
    lines.append("\(currentAlternativeProofCount) run(s) compare against the current alternative.")
    lines.append(
      "\(implementationUseProofCount) run(s) completed the expected tournament experience trace before judging the implementation."
    )
    lines.append("\(willingnessToPayProofCount) run(s) captured explicit willingness-to-pay or sponsorship proof.")
    if averageScore > 0 {
      lines.append(
        "Average implementation score \(format(averageScore))/5; readiness \(format(readinessScore))/100."
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
      lines.append("Product implementation evidence is strong enough to select a tournament winner.")
    case .reviseImplementation:
      lines.append("Product implementation evidence needs a revision before winner selection.")
    case .eliminate:
      lines.append("Product implementation evidence is weak enough to stop this contender.")
    case .gatherEvidence:
      lines.append("Run more scoped Round 3 scenarios before selecting a winner.")
    }
    return lines
  }

  private static func proofGaps(
    summaries: [ProductTournamentEvidenceSummary],
    completedRunCount: Int,
    distinctPersonaCount: Int,
    currentAlternativeProofCount: Int,
    implementationUseProofCount: Int,
    willingnessToPayProofCount: Int,
    readinessScore: Double,
    averageScore: Double,
    willingnessToPayScore: Double,
    weakOrRejectedCount: Int,
    missingCapabilities: [String],
    objections: [String],
    recommendation: ProductTournamentProductImplementationEvidenceRecommendation
  ) -> [String] {
    var gaps: [String] = []
    if summaries.isEmpty {
      gaps.append("no scoped Round 3 product implementation evidence yet")
    }
    if completedRunCount < 3 {
      gaps.append("needs \(3 - completedRunCount) more completed Round 3 run(s)")
    }
    if distinctPersonaCount < 2 {
      gaps.append("needs \(2 - distinctPersonaCount) more persona(s)")
    }
    if currentAlternativeProofCount < 2 {
      gaps.append("needs \(2 - currentAlternativeProofCount) current-alternative comparison(s)")
    }
    if implementationUseProofCount < 3 {
      gaps.append("needs \(3 - implementationUseProofCount) implementation-use trace(s)")
    }
    if willingnessToPayProofCount < 2 {
      gaps.append("needs \(2 - willingnessToPayProofCount) explicit willingness-to-pay proof(s)")
    }
    gaps += countedLabels(
      missingCapabilities,
      prefix: "missing capability",
      minimumCount: 1
    )
    gaps += countedLabels(
      objections,
      prefix: "repeated objection",
      minimumCount: 2
    )
    if completedRunCount >= 2, averageScore > 0, averageScore < 3.6 {
      gaps.append("average implementation score \(format(averageScore))/5 below 3.6")
    }
    if completedRunCount >= 2, willingnessToPayScore > 0, willingnessToPayScore < 3.6 {
      gaps.append("willingness to pay \(format(willingnessToPayScore))/5 below 3.6")
    }
    if weakOrRejectedCount >= 2 {
      gaps.append("\(weakOrRejectedCount) weak or rejected verdict(s)")
    }
    if recommendation == .reviseImplementation, readinessScore < 76 {
      gaps.append("readiness \(format(readinessScore))/100 below winner threshold")
    }
    return Array(gaps.prefix(8))
  }

  private static func nextValidationTarget(
    for recommendation: ProductTournamentProductImplementationEvidenceRecommendation,
    proofGaps: [String]
  ) -> String {
    let gaps =
      proofGaps.isEmpty
      ? "no remaining Round 3 proof gaps"
      : proofGaps.prefix(3).joined(separator: "; ")
    switch recommendation {
    case .selectWinner:
      return
        "Select the tournament winner and preserve the evidence trail for implementation-use, current-alternative, and willingness-to-pay proof."
    case .reviseImplementation:
      return
        "Revise the low-medium fidelity product implementation against \(gaps), then rerun scoped Round 3 implementation-use and willingness-to-pay validation."
    case .eliminate:
      return "Stop this contender unless new scoped Round 3 evidence rebuts \(gaps)."
    case .gatherEvidence:
      return "Run scoped Round 3 product implementation evidence for \(gaps)."
    }
  }

  private static func countedLabels(
    _ values: [String],
    prefix: String,
    minimumCount: Int
  ) -> [String] {
    var counts: [String: Int] = [:]
    var display: [String: String] = [:]
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = normalizedEvidenceText(trimmed)
      guard !normalized.isEmpty else { continue }
      counts[normalized, default: 0] += 1
      if display[normalized] == nil {
        display[normalized] = StringUtils.boundedText(trimmed, limit: 80)
      }
    }
    return counts
      .filter { $0.value >= minimumCount }
      .sorted {
        if $0.value == $1.value { return $0.key < $1.key }
        return $0.value > $1.value
      }
      .prefix(3)
      .map { key, count in
        "\(prefix) \(display[key] ?? key) (\(count)x)"
      }
  }

  private static func activeProductImplementationRounds(
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
            && $0.kind == .productImplementation
            && $0.status == .active
        }) {
          pairs.append((tournament, round))
        }
        continue
      }

      let currentRound = tournament.currentRoundID.flatMap { roundID in
        config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
      }
      if let currentRound, currentRound.kind == .productImplementation, currentRound.status == .active {
        pairs.append((tournament, currentRound))
        continue
      }
      guard tournament.currentRoundID == nil else { continue }
      if let activeRound = config.tournamentRounds
        .filter({
          $0.tournamentID == tournament.id && $0.kind == .productImplementation && $0.status == .active
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
    for recommendation: ProductTournamentProductImplementationEvidenceRecommendation,
    readinessScore: Double
  ) -> Int {
    switch recommendation {
    case .selectWinner:
      return 10_000 + Int(readinessScore.rounded())
    case .eliminate:
      return 8_000 + Int((100 - readinessScore).rounded())
    case .reviseImplementation:
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

  private static func hasImplementationUseProof(_ summary: ProductTournamentEvidenceSummary) -> Bool {
    summary.completedUseProof
  }

  private static func hasWillingnessToPayProof(_ summary: ProductTournamentEvidenceSummary) -> Bool {
    let intent = normalizedEvidenceText(summary.sponsorshipIntent)
    guard !intent.isEmpty else { return false }
    return !isDerivedSponsorshipIntent(intent)
  }

  private static func isDerivedSponsorshipIntent(_ normalized: String) -> Bool {
    let derived = [
      "the simulated user shows strong willingness to pay for or sponsor this contender",
      "the simulated user shows moderate willingness to pay for or sponsor this contender after more proof",
      "the simulated user recognizes some contender value but is not ready to pay or sponsor",
      "the simulated user shows weak willingness to pay for or sponsor this contender",
    ]
    return derived.contains(normalized)
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
    mutate: (inout ProductTournamentExperiment) -> Void
  ) {
    guard
      let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
      let experimentID = contender.experimentID,
      let index = config.tournamentExperiments.firstIndex(where: { $0.id == experimentID })
    else { return }
    mutate(&config.tournamentExperiments[index])
    config.tournamentExperiments[index].updatedAt = timestamp
  }

  private static func updateProductTournamentContenderPlan(
    for contenderID: String,
    in config: inout ProductTournamentConfig,
    mutate: (inout ProductTournamentContenderPlan) -> Void
  ) {
    guard
      let contender = config.tournamentContenders.first(where: { $0.id == contenderID }),
      let index = config.contenderPlans.firstIndex(where: { $0.id == contender.contenderPlanID })
    else { return }
    mutate(&config.contenderPlans[index])
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
  func applyBestProductTournamentProductImplementationEvidenceTransition(
    tournamentID: String? = nil,
    roundID: String? = nil
  ) async -> ProductTournamentProductImplementationEvidenceTransitionOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      let config = try workspace.readProductTournamentConfig()
      let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
      let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.applyBestProposal(
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
  fileprivate var isRoundThreeProductImplementationTransitionCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision:
      return true
    case .competing, .eliminated, .winner, .archived:
      return false
    }
  }
}
