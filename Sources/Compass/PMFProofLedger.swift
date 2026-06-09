import Foundation

struct PMFProofLedger: Equatable, Sendable {
  var hypothesis: PMFProofHypothesis
  var unknowns: [PMFUnknown]
  var evidence: [PMFProofEvidence]
  var nextAction: PMFProofAction?
  var tokenPosture: PMFTokenPosture?

  var isEmpty: Bool {
    hypothesis.isEmpty && unknowns.isEmpty && evidence.isEmpty && nextAction == nil
  }

  var riskiestUnknown: PMFUnknown? {
    unknowns.sorted { lhs, rhs in
      if lhs.severity == rhs.severity {
        if lhs.proofDebt == rhs.proofDebt { return lhs.title < rhs.title }
        return lhs.proofDebt > rhs.proofDebt
      }
      return lhs.severity.rank > rhs.severity.rank
    }.first
  }

  var promptDigest: String {
    guard !isEmpty else {
      return "PMF Proof Ledger\nNo PMF hypothesis is active yet."
    }

    var lines = [
      "PMF Proof Ledger",
      "Hypothesis: \(hypothesis.promptLine)",
    ]

    let topUnknowns = unknowns.prefix(3)
    if topUnknowns.isEmpty {
      lines.append("Top unknowns: none")
    } else {
      lines.append("Top unknowns:")
      lines += topUnknowns.map { unknown in
        "- \(unknown.kind.rawValue): \(unknown.title) | debt \(unknown.proofDebt) | signal \(unknown.currentSignal)"
      }
    }

    if let nextAction {
      lines += [
        "Next proof action: \(nextAction.kind.rawValue) - \(nextAction.title)",
        "Why: \(nextAction.rationale)",
        "Expected token cost: \(nextAction.expectedTokenCostClass.rawValue)",
      ]
    } else {
      lines.append("Next proof action: none")
    }

    let latestProof = evidence.prefix(3)
    if latestProof.isEmpty {
      lines.append("Latest proof: none")
    } else {
      lines.append("Latest proof:")
      lines += latestProof.map { proof in
        "- \(proof.kind.rawValue): \(proof.summary) | confidence \(proof.confidence.rawValue)"
      }
    }

    let refs = (nextAction?.legacyReferences ?? hypothesis.sourceReferences)
      .prefix(6)
      .map { "\($0.kind.rawValue)=\($0.value)" }
      .joined(separator: ", ")
    if !refs.isEmpty {
      lines.append("Legacy refs: \(refs)")
    }

    return bounded(lines.joined(separator: "\n"), limit: 2_000)
  }

  static func build(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> PMFProofLedger {
    guard !config.isEmpty else {
      return PMFProofLedger(
        hypothesis: .empty,
        unknowns: [],
        evidence: [],
        nextAction: nil,
        tokenPosture: nil
      )
    }

    let readModel = ProductTournamentReadModel(config: config)
    let selection = selectActiveHypothesis(readModel: readModel, evidenceIndex: evidenceIndex)
    let pain = selection.tournament.flatMap { readModel.pain(for: $0) }
      ?? config.painHypotheses.sorted {
        if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
        return $0.updatedAt > $1.updatedAt
      }.first
    let plan = selection.contender.flatMap { readModel.plan(for: $0) }
    let experiment = selection.contender.flatMap { readModel.experiment(for: $0) }

    let hypothesis = proofHypothesis(
      pain: pain,
      contender: selection.contender,
      plan: plan,
      experiment: experiment,
      readModel: readModel,
      config: config
    )
    let unknowns = proofUnknowns(
      selection: selection,
      pain: pain,
      plan: plan,
      experiment: experiment,
      readModel: readModel,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let evidence = proofEvidence(
      selection: selection,
      evidenceIndex: evidenceIndex,
      config: config
    )
    let nextAction = proofAction(
      hypothesis: hypothesis,
      unknowns: unknowns,
      selection: selection
    )

    return PMFProofLedger(
      hypothesis: hypothesis,
      unknowns: unknowns,
      evidence: evidence,
      nextAction: nextAction,
      tokenPosture: nextAction.map {
        PMFTokenPosture(
          summary: "Use only the proof brief, top unknowns, latest evidence, and referenced legacy IDs.",
          expectedCostClass: $0.expectedTokenCostClass,
          contextBudgetHint: "Keep PMF proof context under 2k tokens until context packs land."
        )
      }
    )
  }
}

struct PMFProofHypothesis: Equatable, Sendable {
  static let empty = PMFProofHypothesis(
    pain: "",
    targetUser: "",
    buyer: "",
    currentAlternative: "",
    promisedOutcome: "",
    pricingOrValueClaim: "",
    sourceReferences: []
  )

  var pain: String
  var targetUser: String
  var buyer: String
  var currentAlternative: String
  var promisedOutcome: String
  var pricingOrValueClaim: String
  var sourceReferences: [PMFProofSourceReference]

  var isEmpty: Bool {
    [pain, targetUser, buyer, currentAlternative, promisedOutcome, pricingOrValueClaim]
      .allSatisfy { $0.isEmpty }
  }

  var promptLine: String {
    [
      "pain=\(pain)",
      "target_user=\(targetUser)",
      "buyer=\(buyer)",
      "current_alternative=\(currentAlternative)",
      "promised_outcome=\(promisedOutcome)",
      "value_claim=\(pricingOrValueClaim)",
    ]
    .filter { !$0.hasSuffix("=") }
    .joined(separator: "; ")
  }
}

struct PMFUnknown: Equatable, Sendable, Identifiable {
  var id: String { "\(kind.rawValue)|\(title)" }

  var kind: PMFUnknownKind
  var title: String
  var currentSignal: String
  var proofDebt: Int
  var severity: PMFUnknownSeverity
  var sourceReferences: [PMFProofSourceReference]
}

enum PMFUnknownKind: String, Equatable, Sendable, CaseIterable {
  case pain
  case buyer
  case willingnessToPay = "willingness_to_pay"
  case switching
  case retention
  case feasibility
  case usability
  case distribution
}

enum PMFUnknownSeverity: String, Equatable, Sendable, CaseIterable {
  case low
  case medium
  case high
  case critical

  var rank: Int {
    switch self {
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    case .critical: return 4
    }
  }
}

struct PMFProofEvidence: Equatable, Sendable, Identifiable {
  var id: String { artifactID }

  var kind: PMFProofEvidenceKind
  var summary: String
  var confidence: PMFProofConfidence
  var createdAt: Double
  var artifactID: String
  var sourceReferences: [PMFProofSourceReference]
}

enum PMFProofEvidenceKind: String, Equatable, Sendable, CaseIterable {
  case planEvaluation = "plan_evaluation"
  case scenarioRun = "scenario_run"
  case implementationUse = "implementation_use"
  case currentAlternative = "current_alternative"
  case payIntent = "pay_intent"
  case technicalProof = "technical_proof"
  case decision
}

enum PMFProofConfidence: String, Equatable, Sendable, CaseIterable {
  case low
  case medium
  case high
}

struct PMFProofAction: Equatable, Sendable {
  var kind: PMFProofActionKind
  var title: String
  var rationale: String
  var expectedTokenCostClass: PMFTokenCostClass
  var requiredContext: [PMFContextNeed]
  var targetUnknownID: String?
  var legacyReferences: [PMFProofSourceReference]
}

enum PMFProofActionKind: String, Equatable, Sendable, CaseIterable {
  case sharpenHypothesis = "sharpen_hypothesis"
  case runBuyerProof = "run_buyer_proof"
  case runSwitchingProof = "run_switching_proof"
  case buildFeasibilitySlice = "build_feasibility_slice"
  case runUseProof = "run_use_proof"
  case reviseProduct = "revise_product"
  case stopNoUsefulProof = "stop_no_useful_proof"
}

enum PMFTokenCostClass: String, Equatable, Sendable, CaseIterable {
  case low
  case medium
  case high
}

enum PMFContextNeed: String, Equatable, Sendable, CaseIterable {
  case hypothesis
  case topUnknowns = "top_unknowns"
  case recentEvidence = "recent_evidence"
  case legacyIDs = "legacy_ids"
  case repoSlice = "repo_slice"
  case proofInstructions = "proof_instructions"
}

struct PMFTokenPosture: Equatable, Sendable {
  var summary: String
  var expectedCostClass: PMFTokenCostClass
  var contextBudgetHint: String
}

struct PMFProofSourceReference: Equatable, Sendable, Hashable {
  var kind: PMFProofSourceKind
  var value: String
}

enum PMFProofSourceKind: String, Equatable, Sendable, Hashable, CaseIterable {
  case tournamentID
  case contenderID
  case contenderPlanID
  case experimentID
  case roundID
  case planEvaluationID
  case evidenceRunID
  case decisionID
  case painID
  case segmentID
  case workflowID
  case alternativeID
}

private struct PMFActiveSelection {
  var tournament: ProductTournament?
  var round: ProductTournamentRound?
  var contender: ProductTournamentContender?
}

private func selectActiveHypothesis(
  readModel: ProductTournamentReadModel,
  evidenceIndex: ProductTournamentEvidenceIndex
) -> PMFActiveSelection {
  guard let tournament = readModel.activeTournament() else {
    return PMFActiveSelection(tournament: nil, round: nil, contender: nil)
  }
  let activeRound = readModel.activeRound(in: tournament)
  let contenders = readModel.contenders(in: tournament)

  if let winner = contenders
    .filter({ $0.status == .winner })
    .sorted(by: mostRecentlyUpdatedFirst)
    .first
  {
    return PMFActiveSelection(tournament: tournament, round: activeRound, contender: winner)
  }

  if let narrowed = contenders
    .filter({ $0.status == .narrowed })
    .sorted(by: mostRecentlyUpdatedFirst)
    .first
  {
    return PMFActiveSelection(tournament: tournament, round: activeRound, contender: narrowed)
  }

  let activeRoundContenders =
    activeRound.map { readModel.contenders(in: $0) } ?? contenders
  if let active = (
    activeRoundContenders
      .filter { $0.status != .eliminated && $0.status != .archived }
      .sorted { lhs, rhs in
      let lhsScore = readinessScore(for: lhs, evidenceIndex: evidenceIndex)
      let rhsScore = readinessScore(for: rhs, evidenceIndex: evidenceIndex)
      if lhsScore == rhsScore { return mostRecentlyUpdatedFirst(lhs, rhs) }
      return lhsScore > rhsScore
    }
      .first
  )
  {
    return PMFActiveSelection(tournament: tournament, round: activeRound, contender: active)
  }

  return PMFActiveSelection(
    tournament: tournament,
    round: activeRound,
    contender: contenders
      .filter { $0.status != .eliminated && $0.status != .archived }
      .sorted(by: mostRecentlyUpdatedFirst)
      .first
  )
}

private func proofHypothesis(
  pain: PainHypothesis?,
  contender: ProductTournamentContender?,
  plan: ProductTournamentContenderPlan?,
  experiment: ProductTournamentExperiment?,
  readModel: ProductTournamentReadModel,
  config: ProductTournamentConfig
) -> PMFProofHypothesis {
  let segmentIDs = contender?.targetSegmentIDs ?? plan?.targetSegmentIDs ?? []
  let segments = segmentIDs.compactMap { readModel.segment(id: $0) }
  let buyer = segments.first { segment in
    segment.role.localizedCaseInsensitiveContains("buyer")
      || segment.name.localizedCaseInsensitiveContains("buyer")
      || segment.decisionCriteria.contains { !$0.isEmpty }
  }
  let targetUser = segments.first ?? config.userSegments.first
  let currentAlternative =
    segmentIDs
    .compactMap { readModel.segment(id: $0) }
    .flatMap(\.alternativeIDs)
    .compactMap { readModel.alternative(id: $0) }
    .first ?? config.alternatives.first

  let refs = legacyReferences(
    tournamentID: contender?.tournamentID,
    contenderID: contender?.id,
    contenderPlanID: plan?.id ?? contender?.contenderPlanID,
    experimentID: experiment?.id,
    painID: pain?.id,
    segmentID: targetUser?.id,
    alternativeID: currentAlternative?.id
  )

  return PMFProofHypothesis(
    pain: bounded(pain?.rawPain ?? config.rawPain, limit: 300),
    targetUser: bounded(targetUser.map { "\($0.name) (\($0.role))" } ?? "", limit: 180),
    buyer: bounded(buyer.map { "\($0.name) (\($0.role))" } ?? targetUser?.name ?? "", limit: 180),
    currentAlternative: bounded(currentAlternative?.title ?? "", limit: 180),
    promisedOutcome: bounded(
      plan?.promise ?? contender?.valueProposition ?? experiment?.implementationScope ?? "",
      limit: 260
    ),
    pricingOrValueClaim: bounded(
      [plan?.differentiator, contender?.valueProposition]
        .compactMap { $0 }
        .first { !$0.isEmpty } ?? "",
      limit: 220
    ),
    sourceReferences: refs
  )
}

private func proofUnknowns(
  selection: PMFActiveSelection,
  pain: PainHypothesis?,
  plan: ProductTournamentContenderPlan?,
  experiment: ProductTournamentExperiment?,
  readModel: ProductTournamentReadModel,
  config: ProductTournamentConfig,
  evidenceIndex: ProductTournamentEvidenceIndex
) -> [PMFUnknown] {
  var unknowns: [PMFUnknown] = []
  let baseRefs = legacyReferences(
    tournamentID: selection.tournament?.id,
    contenderID: selection.contender?.id,
    contenderPlanID: plan?.id ?? selection.contender?.contenderPlanID,
    experimentID: experiment?.id,
    roundID: selection.round?.id,
    painID: pain?.id
  )

  if let pain {
    unknowns += pain.unknowns.prefix(3).map { unknown in
      PMFUnknown(
        kind: .pain,
        title: bounded(unknown, limit: 140),
        currentSignal: bounded(pain.costOfInaction, limit: 180),
        proofDebt: 2,
        severity: .medium,
        sourceReferences: baseRefs
      )
    }
  }

  if let contender = selection.contender {
    let readiness = evidenceIndex.aggregate.planReadinessByContender.first {
      $0.contenderID == contender.id
    }
    if let readiness, !readiness.planProofDebt.isClear {
      let debt = readiness.planProofDebt
      if debt.buyerOrSponsorDeficit > 0 {
        unknowns.append(
          unknown(
            .buyer,
            "Buyer or sponsor has not been proven",
            signal: readiness.commercialProofSummary,
            debt: debt.buyerOrSponsorDeficit,
            severity: .high,
            refs: refsWith(baseRefs, .planEvaluationID, readiness.latestEvaluationID)
          ))
      }
      if debt.willingnessToPayDeficit > 0 {
        unknowns.append(
          unknown(
            .willingnessToPay,
            "Willingness to pay is below proof threshold",
            signal: readiness.commercialProofSummary,
            debt: debt.willingnessToPayDeficit,
            severity: .high,
            refs: refsWith(baseRefs, .planEvaluationID, readiness.latestEvaluationID)
          ))
      }
      if debt.evaluationDeficit + debt.personaDeficit > 0 {
        unknowns.append(
          unknown(
            .pain,
            "Plan proof coverage is incomplete",
            signal: readiness.nextProofTargetSummary,
            debt: debt.evaluationDeficit + debt.personaDeficit,
            severity: .medium,
            refs: refsWith(baseRefs, .planEvaluationID, readiness.latestEvaluationID)
          ))
      }
    } else if readiness == nil, selection.round?.kind == .productPlans {
      unknowns.append(
        unknown(
          .buyer,
          "Plan proof has not run for the active hypothesis",
          signal: "No plan evaluation evidence recorded yet.",
          debt: 4,
          severity: .high,
          refs: baseRefs
        ))
    }
  }

  if selection.round?.kind == .coreTechnology {
    let overview = ProductTournamentRoundTwoProofOverview.items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: 8
    )
    .first { $0.contenderID == selection.contender?.id }
    let debt = max(1, overview?.proofGaps.count ?? 1)
    unknowns.append(
      unknown(
        .feasibility,
        "Core feasibility proof is not complete",
        signal: overview?.detail ?? experiment?.implementationScope ?? "No feasibility evidence recorded yet.",
        debt: debt,
        severity: .high,
        refs: refsWith(baseRefs, .evidenceRunID, overview?.evidenceRunIDs.first)
      ))
  }

  if selection.round?.kind == .productImplementation || selection.contender?.status == .winner {
    let overview = ProductTournamentRoundThreeProductImplementationOverview.items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: 8
    )
    .first { $0.contenderID == selection.contender?.id }
    let useDebt = max(0, 2 - (overview?.implementationUseProofCount ?? 0))
    let switchDebt = max(0, 2 - (overview?.currentAlternativeProofCount ?? 0))
    let payDebt = max(0, 2 - (overview?.willingnessToPayProofCount ?? 0))
    if useDebt > 0 {
      unknowns.append(
        unknown(
          .usability,
          "Product-use proof is incomplete",
          signal: overview?.detail ?? "No completed implementation-use proof recorded yet.",
          debt: useDebt,
          severity: .high,
          refs: refsWith(baseRefs, .evidenceRunID, overview?.evidenceRunIDs.first)
        ))
    }
    if switchDebt > 0 {
      unknowns.append(
        unknown(
          .switching,
          "Current-alternative comparison is incomplete",
          signal: overview?.nextValidationTarget ?? "No switching proof recorded yet.",
          debt: switchDebt,
          severity: .medium,
          refs: refsWith(baseRefs, .evidenceRunID, overview?.evidenceRunIDs.first)
        ))
    }
    if payDebt > 0 {
      unknowns.append(
        unknown(
          .willingnessToPay,
          "Explicit pay or sponsorship proof is incomplete",
          signal: overview.map { "Willingness to pay \($0.willingnessToPayScore)/5" }
            ?? "No pay-intent proof recorded yet.",
          debt: payDebt,
          severity: .medium,
          refs: refsWith(baseRefs, .evidenceRunID, overview?.evidenceRunIDs.first)
        ))
    }
  }

  return unknowns
    .filter { !$0.title.isEmpty }
    .sorted { lhs, rhs in
      if lhs.severity == rhs.severity {
        if lhs.proofDebt == rhs.proofDebt { return lhs.title < rhs.title }
        return lhs.proofDebt > rhs.proofDebt
      }
      return lhs.severity.rank > rhs.severity.rank
    }
}

private func proofEvidence(
  selection: PMFActiveSelection,
  evidenceIndex: ProductTournamentEvidenceIndex,
  config: ProductTournamentConfig
) -> [PMFProofEvidence] {
  var evidence: [PMFProofEvidence] = []
  let contenderID = selection.contender?.id
  let experimentID = selection.contender?.experimentID

  evidence += evidenceIndex.planEvaluationSummaries
    .filter { contenderID == nil || $0.contenderID == contenderID }
    .map { summary in
      let kind: PMFProofEvidenceKind =
        (summary.willingnessToPayScore ?? 0) >= 3 ? .payIntent : .planEvaluation
      return PMFProofEvidence(
        kind: kind,
        summary: bounded(summary.summary, limit: 220),
        confidence: confidence(verdict: summary.verdict, completed: summary.isCompleted),
        createdAt: summary.endedAt,
        artifactID: summary.evaluationID,
        sourceReferences: legacyReferences(
          tournamentID: summary.tournamentID,
          contenderID: summary.contenderID,
          contenderPlanID: summary.contenderPlanID,
          experimentID: summary.experimentID,
          roundID: summary.roundID,
          planEvaluationID: summary.evaluationID,
          painID: summary.painID
        )
      )
    }

  evidence += evidenceIndex.summaries
    .filter { summary in
      (experimentID == nil || summary.experimentID == experimentID)
        && (contenderID == nil || summary.contenderID == nil || summary.contenderID == contenderID)
    }
    .map { summary in
      PMFProofEvidence(
        kind: evidenceKind(summary),
        summary: bounded(summary.summary, limit: 220),
        confidence: confidence(verdict: summary.verdict, completed: summary.isCompleted),
        createdAt: summary.endedAt,
        artifactID: summary.runID,
        sourceReferences: legacyReferences(
          tournamentID: summary.tournamentID,
          contenderID: summary.contenderID,
          contenderPlanID: summary.contenderPlanID,
          experimentID: summary.experimentID,
          roundID: summary.roundID,
          evidenceRunID: summary.runID,
          painID: summary.painID
        )
      )
    }

  if let experimentID {
    evidence += config.decisions
      .filter { $0.experimentID == experimentID }
      .map { decision in
        PMFProofEvidence(
          kind: .decision,
          summary: bounded("\(decision.decision.rawValue): \(decision.summary)", limit: 220),
          confidence: .medium,
          createdAt: decision.decidedAt,
          artifactID: decision.id,
          sourceReferences: legacyReferences(
            experimentID: decision.experimentID,
            decisionID: decision.id
          )
        )
      }
  }

  return evidence.sorted { lhs, rhs in
    if lhs.createdAt == rhs.createdAt { return lhs.artifactID < rhs.artifactID }
    return lhs.createdAt > rhs.createdAt
  }
}

private func proofAction(
  hypothesis: PMFProofHypothesis,
  unknowns: [PMFUnknown],
  selection: PMFActiveSelection
) -> PMFProofAction? {
  guard !hypothesis.isEmpty else {
    return PMFProofAction(
      kind: .sharpenHypothesis,
      title: "Sharpen the PMF hypothesis",
      rationale: "No active PMF hypothesis is available.",
      expectedTokenCostClass: .low,
      requiredContext: [.hypothesis, .legacyIDs],
      targetUnknownID: nil,
      legacyReferences: []
    )
  }
  guard let unknown = unknowns.first else {
    return nil
  }

  let actionKind: PMFProofActionKind
  let title: String
  let tokenCost: PMFTokenCostClass
  let context: [PMFContextNeed]
  switch unknown.kind {
  case .buyer, .willingnessToPay:
    actionKind = .runBuyerProof
    title = "Run buyer/pay proof"
    tokenCost = .low
    context = [.hypothesis, .topUnknowns, .recentEvidence, .legacyIDs]
  case .feasibility:
    actionKind = .buildFeasibilitySlice
    title = "Build the smallest feasibility slice"
    tokenCost = .high
    context = [.hypothesis, .topUnknowns, .repoSlice, .proofInstructions, .legacyIDs]
  case .switching:
    actionKind = .runSwitchingProof
    title = "Run switching proof"
    tokenCost = .medium
    context = [.hypothesis, .topUnknowns, .recentEvidence, .legacyIDs]
  case .usability, .retention:
    actionKind = .runUseProof
    title = "Run product-use proof"
    tokenCost = .medium
    context = [.hypothesis, .topUnknowns, .recentEvidence, .legacyIDs]
  case .pain, .distribution:
    actionKind = .sharpenHypothesis
    title = "Sharpen the proof hypothesis"
    tokenCost = .low
    context = [.hypothesis, .topUnknowns, .legacyIDs]
  }

  return PMFProofAction(
    kind: actionKind,
    title: title,
    rationale: unknown.title,
    expectedTokenCostClass: tokenCost,
    requiredContext: context,
    targetUnknownID: unknown.id,
    legacyReferences: uniqueReferences(
      unknown.sourceReferences
        + legacyReferences(
          tournamentID: selection.tournament?.id,
          contenderID: selection.contender?.id,
          roundID: selection.round?.id
        )
    )
  )
}

private func unknown(
  _ kind: PMFUnknownKind,
  _ title: String,
  signal: String,
  debt: Int,
  severity: PMFUnknownSeverity,
  refs: [PMFProofSourceReference]
) -> PMFUnknown {
  PMFUnknown(
    kind: kind,
    title: bounded(title, limit: 140),
    currentSignal: bounded(signal, limit: 220),
    proofDebt: max(1, debt),
    severity: severity,
    sourceReferences: uniqueReferences(refs)
  )
}

private func evidenceKind(_ summary: ProductTournamentEvidenceSummary) -> PMFProofEvidenceKind {
  if summary.completedUseProof {
    return .implementationUse
  }
  if summary.willingnessToPayScore != nil || !summary.sponsorshipIntent.isEmpty {
    return .payIntent
  }
  if !summary.currentAlternativeComparison.isEmpty {
    return .currentAlternative
  }
  if !summary.missingCapabilities.isEmpty {
    return .technicalProof
  }
  return .scenarioRun
}

private func confidence(
  verdict: ProductTournamentEvidenceVerdict,
  completed: Bool
) -> PMFProofConfidence {
  guard completed else { return .low }
  switch verdict {
  case .strongPull, .promising:
    return .high
  case .unclear:
    return .medium
  case .weak, .rejected:
    return .low
  }
}

private func readinessScore(
  for contender: ProductTournamentContender,
  evidenceIndex: ProductTournamentEvidenceIndex
) -> Double {
  if let planReadiness = evidenceIndex.aggregate.planReadinessByContender.first(where: {
    $0.contenderID == contender.id
  }) {
    return planReadiness.readinessScore
  }
  if let experimentID = contender.experimentID,
    let readiness = evidenceIndex.aggregate.tournamentReadinessByExperiment.first(where: {
      $0.experimentID == experimentID
    })
  {
    return readiness.readinessScore
  }
  return contender.status == .competing ? 1 : 0
}

private func mostRecentlyUpdatedFirst(
  _ lhs: ProductTournamentContender,
  _ rhs: ProductTournamentContender
) -> Bool {
  if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
  return lhs.updatedAt > rhs.updatedAt
}

private func refsWith(
  _ refs: [PMFProofSourceReference],
  _ kind: PMFProofSourceKind,
  _ value: String?
) -> [PMFProofSourceReference] {
  guard let value, !value.isEmpty else { return refs }
  return uniqueReferences(refs + [PMFProofSourceReference(kind: kind, value: value)])
}

private func legacyReferences(
  tournamentID: String? = nil,
  contenderID: String? = nil,
  contenderPlanID: String? = nil,
  experimentID: String? = nil,
  roundID: String? = nil,
  planEvaluationID: String? = nil,
  evidenceRunID: String? = nil,
  decisionID: String? = nil,
  painID: String? = nil,
  segmentID: String? = nil,
  workflowID: String? = nil,
  alternativeID: String? = nil
) -> [PMFProofSourceReference] {
  [
    (PMFProofSourceKind.tournamentID, tournamentID),
    (.contenderID, contenderID),
    (.contenderPlanID, contenderPlanID),
    (.experimentID, experimentID),
    (.roundID, roundID),
    (.planEvaluationID, planEvaluationID),
    (.evidenceRunID, evidenceRunID),
    (.decisionID, decisionID),
    (.painID, painID),
    (.segmentID, segmentID),
    (.workflowID, workflowID),
    (.alternativeID, alternativeID),
  ]
  .compactMap { kind, value -> PMFProofSourceReference? in
    guard let value, !value.isEmpty else { return nil }
    return PMFProofSourceReference(kind: kind, value: value)
  }
  .productTournamentProofUniqued()
}

private func uniqueReferences(
  _ refs: [PMFProofSourceReference]
) -> [PMFProofSourceReference] {
  refs.productTournamentProofUniqued()
}

private func bounded(_ value: String?, limit: Int) -> String {
  StringUtils.boundedText(value ?? "", limit: limit)
}

extension Array where Element == PMFProofSourceReference {
  fileprivate func productTournamentProofUniqued() -> [PMFProofSourceReference] {
    var seen: Set<PMFProofSourceReference> = []
    var result: [PMFProofSourceReference] = []
    for ref in self where !ref.value.isEmpty {
      if seen.insert(ref).inserted {
        result.append(ref)
      }
    }
    return result
  }
}
