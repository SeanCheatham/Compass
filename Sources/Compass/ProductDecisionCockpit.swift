import Foundation

struct ProductDecisionCockpit: Equatable, Sendable {
  var isEmpty: Bool
  var activePain: PainSummary?
  var activeMarket: MarketSummary?
  var activeTournament: TournamentSummary?
  var activeRound: RoundSummary?
  var contenders: [ContenderLane]
  var evidenceMatrix: EvidenceMatrix
  var nextMove: NextMoveSummary?
  var latestMovement: ProofMovementSummary?
  var auditReferences: [AuditReference]

  static func build(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> ProductDecisionCockpit {
    let readModel = ProductTournamentReadModel(config: config)
    guard let tournament = readModel.activeTournament() else {
      let fallbackPain = config.painHypotheses.sorted {
        if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
        return $0.updatedAt > $1.updatedAt
      }.first
      return ProductDecisionCockpit(
        isEmpty: true,
        activePain: fallbackPain.map {
          painSummary(for: $0, readModel: readModel, config: config)
        },
        activeMarket: ProductDecisionCockpitBuilder.marketSummary(
          for: config.markets.first,
          config: config
        ),
        activeTournament: nil,
        activeRound: nil,
        contenders: [],
        evidenceMatrix: EvidenceMatrix.empty,
        nextMove: nil,
        latestMovement: nil,
        auditReferences: fallbackPain.map {
          [AuditReference(kind: .pain, label: "Pain ID", value: $0.id)]
        } ?? []
      )
    }

    let pain = readModel.pain(for: tournament)
    let rounds = readModel.rounds(in: tournament)
    let activeRound = readModel.activeRound(in: tournament) ?? rounds.first
    let scoreboardItems = TournamentAutomationProofTargetScoreboard.items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: Int.max,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    let scoreboardRows = scoreboardItems.flatMap(\.rows)
    let rowsByContenderID = Dictionary(grouping: scoreboardRows.compactMap {
      row -> (String, TournamentAutomationProofTargetScoreboardRow)? in
      guard let contenderID = row.contenderID else { return nil }
      return (contenderID, row)
    }) { $0.0 }
      .mapValues { $0.map(\.1) }
    let nextStep = TournamentAutomationPlanner.nextStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    let roundTwoTarget = ProductTournamentRoundImplementationTargetResolver
      .defaultActiveRoundTwoTarget(in: config)
    let sortedContenders = sortedContenders(
      in: tournament,
      readModel: readModel,
      rowsByContenderID: rowsByContenderID
    )
    let lanes = sortedContenders.map { contender in
      contenderLane(
        for: contender,
        tournament: tournament,
        activeRound: activeRound,
        readModel: readModel,
        evidenceIndex: evidenceIndex,
        scoreboardRows: rowsByContenderID[contender.id] ?? [],
        roundTwoTarget: roundTwoTarget
      )
    }
    let matrix = EvidenceMatrix(
      dimensions: EvidenceDimension.defaultOrder,
      rows: lanes.map { lane in
        EvidenceMatrixRow(
          contenderID: lane.id,
          contenderTitle: lane.title,
          signals: lane.evidenceSignals
        )
      }
    )
    let latestMovement = latestMovementSummary(from: scoreboardRows)
    let allAuditReferences = uniqueAuditReferences(
      cockpitAuditReferences(
        tournament: tournament,
        pain: pain,
        activeRound: activeRound
      ) + lanes.flatMap(\.auditReferences) + (latestMovement?.auditReferences ?? [])
    )

    return ProductDecisionCockpit(
      isEmpty: false,
      activePain: pain.map { painSummary(for: $0, readModel: readModel, config: config) },
      activeMarket: ProductDecisionCockpitBuilder.marketSummary(
        for: pain.flatMap { matchingMarket(for: $0, in: config) } ?? config.markets.first,
        config: config
      ),
      activeTournament: TournamentSummary(
        id: tournament.id,
        title: bounded(tournament.title, limit: 120),
        premise: bounded(tournament.premise, limit: 220),
        status: tournament.status,
        statusLabel: tournamentStatusLabel(tournament.status),
        roundCount: rounds.count,
        contenderCount: sortedContenders.count
      ),
      activeRound: activeRound.map {
        roundSummary(for: $0, totalRoundCount: rounds.count)
      },
      contenders: lanes,
      evidenceMatrix: matrix,
      nextMove: nextMoveSummary(
        step: nextStep,
        scoreboardRows: scoreboardRows,
        readModel: readModel
      ),
      latestMovement: latestMovement,
      auditReferences: allAuditReferences
    )
  }
}

struct MarketSummary: Equatable, Sendable {
  var id: String
  var category: String
  var summary: String
  var buyerActor: String
  var incumbent: String
  var bestChannel: String
  var proofDebtSummary: String
  var proofDebtTotal: Int
}

struct PainSummary: Equatable, Sendable {
  var id: String
  var title: String
  var audience: String
  var currentWorkaround: String
  var costImpact: String
  var unresolvedUnknownCount: Int
  var unknowns: [String]
}

struct TournamentSummary: Equatable, Sendable {
  var id: String
  var title: String
  var premise: String
  var status: ProductTournamentStatus
  var statusLabel: String
  var roundCount: Int
  var contenderCount: Int
}

struct RoundSummary: Equatable, Sendable {
  var id: String
  var ordinal: Int
  var kind: ProductTournamentRoundKind
  var productTitle: String
  var gateDescription: String
  var status: ProductTournamentRoundStatus
  var statusLabel: String
}

struct ContenderLane: Equatable, Sendable, Identifiable {
  var id: String
  var title: String
  var promise: String
  var targetSegmentNames: [String]
  var currentAlternative: String
  var distribution: DistributionChannelSummary
  var tournamentPosition: String
  var status: ContenderLaneStatus
  var activeRoundState: RoundStateSummary
  var experimentSummary: String
  var proofDebt: ProofDebtSummary
  var evidenceSignals: [EvidenceSignal]
  var auditReferences: [AuditReference]
}

struct DistributionChannelSummary: Equatable, Sendable {
  var bestChannel: String
  var weakestChannel: String
  var latestVerdict: String
  var nextChannelProof: String
  var proofDebtSummary: String
}

enum ContenderLaneStatus: String, Equatable, Sendable {
  case competing
  case narrowed
  case needsRevision
  case eliminated
  case winner
  case archived

  var label: String {
    switch self {
    case .competing: return "Competing"
    case .narrowed: return "Advanced"
    case .needsRevision: return "Revision needed"
    case .eliminated: return "Eliminated"
    case .winner: return "Winner"
    case .archived: return "Archived"
    }
  }
}

struct RoundStateSummary: Equatable, Sendable {
  var state: RoundState
  var title: String
  var detail: String
}

enum RoundState: String, Equatable, Sendable {
  case active
  case pending
  case completed
  case blocked
  case paused
  case eliminated
  case winner
}

enum EvidenceDimension: String, CaseIterable, Equatable, Sendable {
  case painFit
  case workflowLift
  case alternativeAdvantage
  case switchingReadiness
  case payIntent
  case productUseProof
  case personaBreadth

  static let defaultOrder: [EvidenceDimension] = [
    .painFit,
    .workflowLift,
    .alternativeAdvantage,
    .switchingReadiness,
    .payIntent,
    .productUseProof,
    .personaBreadth,
  ]

  var label: String {
    switch self {
    case .painFit: return "Pain fit"
    case .workflowLift: return "Workflow lift"
    case .alternativeAdvantage: return "Alternative advantage"
    case .switchingReadiness: return "Switching readiness"
    case .payIntent: return "Pay intent"
    case .productUseProof: return "Product use proof"
    case .personaBreadth: return "Persona breadth"
    }
  }
}

enum EvidenceStrength: String, Equatable, Sendable {
  case strong
  case progressing
  case missing
  case blocked
  case risk
  case neutral
}

struct EvidenceSignal: Equatable, Sendable, Identifiable {
  var id: String { dimension.rawValue }

  var dimension: EvidenceDimension
  var strength: EvidenceStrength
  var countLabel: String
  var primaryPhrase: String
  var supportingPhrase: String
  var sourceAuditReferences: [AuditReference]
}

struct EvidenceMatrix: Equatable, Sendable {
  static let empty = EvidenceMatrix(dimensions: EvidenceDimension.defaultOrder, rows: [])

  var dimensions: [EvidenceDimension]
  var rows: [EvidenceMatrixRow]

  var isEmpty: Bool { rows.isEmpty }
}

struct EvidenceMatrixRow: Equatable, Sendable, Identifiable {
  var id: String { contenderID }

  var contenderID: String
  var contenderTitle: String
  var signals: [EvidenceSignal]
}

struct ProofDebtSummary: Equatable, Sendable {
  var missingGates: [String]
  var completedCount: Int
  var requiredCount: Int
  var nextProofTarget: String
  var readinessState: String
  var blockingCount: Int
  var auditReferences: [AuditReference]

  var isClear: Bool { blockingCount == 0 }
}

struct NextMoveSummary: Equatable, Sendable {
  var actionTitle: String
  var why: String
  var expectedDecision: String
  var actionKind: ProductTournamentNextActionKind
  var targetContender: String?
  var targetPersona: String?
  var disabledReason: String?
  var auditReferences: [AuditReference]
}

struct ProofMovementSummary: Equatable, Sendable {
  var title: String
  var beforeCount: Int
  var afterCount: Int
  var delta: Int
  var detail: String
  var postResultState: String
  var auditReferences: [AuditReference]
}

struct AuditReference: Equatable, Hashable, Sendable {
  var kind: AuditReferenceKind
  var label: String
  var value: String
}

enum AuditReferenceKind: String, Equatable, Hashable, Sendable {
  case pain
  case tournament
  case round
  case contender
  case contenderPlan
  case experiment
  case scenario
  case cohort
  case evidenceRun
  case planEvaluation
  case automationAudit
  case branch
  case commit
  case model
  case promptVersion
}

private enum ProductDecisionCockpitBuilder {
  static func painSummary(
    for pain: PainHypothesis,
    readModel: ProductTournamentReadModel,
    config: ProductTournamentConfig
  ) -> PainSummary {
    let segments = config.userSegments
      .filter { $0.painID == pain.id }
      .map(\.name)
      .sorted()
    let workflows = config.currentWorkflows.filter { $0.painID == pain.id }
    let workaround =
      workflows.flatMap(\.workarounds).first
      ?? config.alternatives.first { $0.painID == pain.id }?.title
      ?? "Current workaround not captured yet"
    let cost =
      !pain.costOfInaction.isEmpty
      ? pain.costOfInaction
      : workflows.first?.estimatedCost ?? "Cost of inaction unknown"
    return PainSummary(
      id: pain.id,
      title: bounded(pain.title, limit: 120),
      audience: segments.isEmpty ? "Audience not selected yet" : segments.joined(separator: ", "),
      currentWorkaround: bounded(workaround, limit: 160),
      costImpact: bounded(cost, limit: 180),
      unresolvedUnknownCount: pain.unknowns.count,
      unknowns: pain.unknowns.map { bounded($0, limit: 160) }
    )
  }

  static func marketSummary(
    for market: ProductMarket?,
    config: ProductTournamentConfig
  ) -> MarketSummary? {
    guard let market else { return nil }
    let buyer =
      market.actors.first { $0.role == .economicBuyer }
      ?? market.actors.first { $0.role == .managerSponsor }
    let incumbent = market.incumbents.first
    let bestChannel = market.channels.sorted { lhs, rhs in
      if lhs.reachability == rhs.reachability { return lhs.costRisk < rhs.costRisk }
      return lhs.reachability > rhs.reachability
    }.first
    return MarketSummary(
      id: market.id,
      category: bounded(market.category, limit: 120),
      summary: bounded(market.summary, limit: 220),
      buyerActor: buyer.map { bounded("\($0.name) (\($0.role.rawValue))", limit: 120) }
        ?? "Buyer not identified",
      incumbent: incumbent.map { bounded($0.name, limit: 120) } ?? "Incumbent not identified",
      bestChannel: bestChannel.map {
        bounded("\($0.kind.rawValue): \($0.audience)", limit: 140)
      } ?? "Channel not identified",
      proofDebtSummary: market.marketProofDebt.summary,
      proofDebtTotal: market.marketProofDebt.total
    )
  }

  static func roundSummary(
    for round: ProductTournamentRound,
    totalRoundCount: Int
  ) -> RoundSummary {
    RoundSummary(
      id: round.id,
      ordinal: round.ordinal,
      kind: round.kind,
      productTitle: productRoundTitle(for: round),
      gateDescription: gateDescription(for: round),
      status: round.status,
      statusLabel: roundStatusLabel(round.status)
    )
  }

  static func sortedContenders(
    in tournament: ProductTournament,
    readModel: ProductTournamentReadModel,
    rowsByContenderID: [String: [TournamentAutomationProofTargetScoreboardRow]]
  ) -> [ProductTournamentContender] {
    readModel.contenders(in: tournament).sorted { lhs, rhs in
      let lhsPressure = rowsByContenderID[lhs.id]?.map(\.urgencyScore).max() ?? 0
      let rhsPressure = rowsByContenderID[rhs.id]?.map(\.urgencyScore).max() ?? 0
      if lhsPressure != rhsPressure { return lhsPressure > rhsPressure }
      let lhsStatus = contenderStatusRank(lhs.status)
      let rhsStatus = contenderStatusRank(rhs.status)
      if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
      if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
      return lhs.createdAt < rhs.createdAt
    }
  }

  static func contenderLane(
    for contender: ProductTournamentContender,
    tournament: ProductTournament,
    activeRound: ProductTournamentRound?,
    readModel: ProductTournamentReadModel,
    evidenceIndex: ProductTournamentEvidenceIndex,
    scoreboardRows: [TournamentAutomationProofTargetScoreboardRow],
    roundTwoTarget: ProductTournamentRoundImplementationTarget?
  ) -> ContenderLane {
    let plan = readModel.plan(for: contender)
    let experiment = readModel.experiment(for: contender)
    let targetSegments = targetSegmentNames(
      for: contender,
      plan: plan,
      readModel: readModel
    )
    let planReadiness = evidenceIndex.aggregate.planReadinessByContender
      .first { $0.contenderID == contender.id }
    let tournamentReadiness = experiment.flatMap {
      evidenceIndex.currentTournamentReadiness(for: $0)
    }
    let proofDebt = proofDebtSummary(
      contender: contender,
      activeRound: activeRound,
      planReadiness: planReadiness,
      tournamentReadiness: tournamentReadiness,
      scoreboardRows: scoreboardRows,
      roundTwoTarget: roundTwoTarget,
      readModel: readModel
    )
    let auditReferences = uniqueAuditReferences(
      contenderAuditReferences(contender: contender, plan: plan, experiment: experiment)
        + proofDebt.auditReferences
    )
    return ContenderLane(
      id: contender.id,
      title: bounded(contender.title, limit: 100),
      promise: bounded(plan?.promise ?? contender.valueProposition, limit: 180),
      targetSegmentNames: targetSegments,
      currentAlternative: currentAlternative(
        for: contender,
        plan: plan,
        readModel: readModel
      ),
      distribution: distributionSummary(
        for: contender,
        config: readModel.config,
        evidenceIndex: evidenceIndex
      ),
      tournamentPosition: tournamentPosition(
        contender: contender,
        tournament: tournament,
        activeRound: activeRound,
        readModel: readModel
      ),
      status: ContenderLaneStatus(contender.status),
      activeRoundState: roundState(
        contender: contender,
        tournament: tournament,
        activeRound: activeRound,
        roundTwoTarget: roundTwoTarget,
        readModel: readModel
      ),
      experimentSummary: bounded(
        experiment?.evidenceSummary ?? experiment?.implementationScope ?? "No evidence recorded yet.",
        limit: 180
      ),
      proofDebt: proofDebt,
      evidenceSignals: evidenceSignals(
        contender: contender,
        planReadiness: planReadiness,
        tournamentReadiness: tournamentReadiness,
        evidenceIndex: evidenceIndex,
        experiment: experiment,
        proofDebt: proofDebt
      ),
      auditReferences: auditReferences
    )
  }

  static func distributionSummary(
    for contender: ProductTournamentContender,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> DistributionChannelSummary {
    let experiments = config.distributionExperiments.filter { $0.contenderID == contender.id }
    let channelNames = Dictionary(
      uniqueKeysWithValues: config.markets.flatMap(\.channels).map {
        ($0.id, "\($0.kind.rawValue): \($0.audience)")
      }
    )
    let proof = evidenceIndex.aggregate.distributionChannelProofByContender.first {
      $0.contenderID == contender.id
    }
    let failed = evidenceIndex.distributionPressureSummaries
      .filter {
        $0.contenderID == contender.id
          && ($0.verdict == .wrongChannel || $0.verdict == .tooExpensive
            || $0.verdict == .ignored)
      }
      .sorted { lhs, rhs in
        if lhs.scores.average == rhs.scores.average { return lhs.createdAt > rhs.createdAt }
        return lhs.scores.average < rhs.scores.average
      }
      .first
    let draftedChannel =
      experiments.first.flatMap { channelNames[$0.channelID] }
      ?? experiments.first?.channelID
      ?? "No distribution experiment"
    let bestChannel =
      (proof?.bestChannelID).flatMap { channelNames[$0] }
      ?? proof?.bestChannelID
      ?? draftedChannel
    let weakestChannel =
      (failed?.channelID).flatMap { channelNames[$0] }
      ?? failed?.channelID
      ?? "No failed channel proof"
    let latestVerdict = proof?.latestVerdict?.rawValue ?? "No channel pressure"
    let nextProof =
      proof?.nextMove
      ?? (experiments.isEmpty
        ? "Create a distribution experiment before selecting a winner."
        : "Run distribution pressure for the drafted channel artifact.")
    return DistributionChannelSummary(
      bestChannel: bounded(bestChannel, limit: 140),
      weakestChannel: bounded(weakestChannel, limit: 140),
      latestVerdict: latestVerdict,
      nextChannelProof: bounded(nextProof, limit: 180),
      proofDebtSummary: proof?.proofDebt.summary ?? "attention 2, channel 2, buyer_reach 2, message 2"
    )
  }

  static func nextMoveSummary(
    step: TournamentAutomationStep?,
    scoreboardRows: [TournamentAutomationProofTargetScoreboardRow],
    readModel: ProductTournamentReadModel
  ) -> NextMoveSummary? {
    let sortedRows = scoreboardRows.sorted { $0.scoreboardSortsBefore($1) }
    let row =
      step.flatMap { selectedStep in
        sortedRows.first { $0.experimentID == selectedStep.experimentID }
      } ?? sortedRows.first
    let resolvedStep = step ?? row?.nextStep
    guard let resolvedStep else { return nil }
    let targetContender =
      resolvedStep.contenderID.flatMap { readModel.contender(id: $0)?.title }
      ?? row?.contenderTitle
    let actionTitle = productActionTitle(for: resolvedStep)
    let why = nextMoveWhy(row: row, step: resolvedStep)
    return NextMoveSummary(
      actionTitle: actionTitle,
      why: why,
      expectedDecision: expectedDecision(for: resolvedStep),
      actionKind: resolvedStep.action.kind,
      targetContender: targetContender.map { bounded($0, limit: 100) },
      targetPersona: resolvedStep.action.targetPersonaName.map { bounded($0, limit: 100) },
      disabledReason: resolvedStep.canExecute ? nil : disabledReason(for: resolvedStep),
      auditReferences: uniqueAuditReferences(
        stepAuditReferences(step: resolvedStep, row: row)
      )
    )
  }

  static func latestMovementSummary(
    from rows: [TournamentAutomationProofTargetScoreboardRow]
  ) -> ProofMovementSummary? {
    let match = rows.compactMap { row -> (
      TournamentAutomationProofTargetScoreboardRow,
      TournamentAutomationProofTargetDebtMovement
    )? in
      guard let movement = row.latestDebtMovement else { return nil }
      return (row, movement)
    }
    .sorted { lhs, rhs in
      if lhs.1.endedAt == rhs.1.endedAt {
        return lhs.0.scoreboardSortsBefore(rhs.0)
      }
      return lhs.1.endedAt > rhs.1.endedAt
    }
    .first
    guard let (row, movement) = match else { return nil }
    return ProofMovementSummary(
      title: "\(bounded(row.contenderTitle, limit: 100)): \(movement.movementLabel)",
      beforeCount: movement.startingProofDebtCount,
      afterCount: movement.endingProofDebtCount,
      delta: movement.proofDebtDelta,
      detail: movement.postResultStateSummary,
      postResultState: movement.postResultStateSummary,
      auditReferences: [
        AuditReference(kind: .automationAudit, label: "Automation audit ID", value: movement.auditID)
      ] + movement.evidenceRunIDs.map {
        AuditReference(kind: .evidenceRun, label: "Evidence run ID", value: $0)
      }
    )
  }
}

extension ProductDecisionCockpit {
  fileprivate static func painSummary(
    for pain: PainHypothesis,
    readModel: ProductTournamentReadModel,
    config: ProductTournamentConfig
  ) -> PainSummary {
    ProductDecisionCockpitBuilder.painSummary(for: pain, readModel: readModel, config: config)
  }

  fileprivate static func roundSummary(
    for round: ProductTournamentRound,
    totalRoundCount: Int
  ) -> RoundSummary {
    ProductDecisionCockpitBuilder.roundSummary(for: round, totalRoundCount: totalRoundCount)
  }

  fileprivate static func sortedContenders(
    in tournament: ProductTournament,
    readModel: ProductTournamentReadModel,
    rowsByContenderID: [String: [TournamentAutomationProofTargetScoreboardRow]]
  ) -> [ProductTournamentContender] {
    ProductDecisionCockpitBuilder.sortedContenders(
      in: tournament,
      readModel: readModel,
      rowsByContenderID: rowsByContenderID
    )
  }

  fileprivate static func contenderLane(
    for contender: ProductTournamentContender,
    tournament: ProductTournament,
    activeRound: ProductTournamentRound?,
    readModel: ProductTournamentReadModel,
    evidenceIndex: ProductTournamentEvidenceIndex,
    scoreboardRows: [TournamentAutomationProofTargetScoreboardRow],
    roundTwoTarget: ProductTournamentRoundImplementationTarget?
  ) -> ContenderLane {
    ProductDecisionCockpitBuilder.contenderLane(
      for: contender,
      tournament: tournament,
      activeRound: activeRound,
      readModel: readModel,
      evidenceIndex: evidenceIndex,
      scoreboardRows: scoreboardRows,
      roundTwoTarget: roundTwoTarget
    )
  }

  fileprivate static func nextMoveSummary(
    step: TournamentAutomationStep?,
    scoreboardRows: [TournamentAutomationProofTargetScoreboardRow],
    readModel: ProductTournamentReadModel
  ) -> NextMoveSummary? {
    ProductDecisionCockpitBuilder.nextMoveSummary(
      step: step,
      scoreboardRows: scoreboardRows,
      readModel: readModel
    )
  }

  fileprivate static func latestMovementSummary(
    from rows: [TournamentAutomationProofTargetScoreboardRow]
  ) -> ProofMovementSummary? {
    ProductDecisionCockpitBuilder.latestMovementSummary(from: rows)
  }
}

private extension ContenderLaneStatus {
  init(_ status: ProductTournamentContenderStatus) {
    switch status {
    case .competing:
      self = .competing
    case .narrowed:
      self = .narrowed
    case .needsRevision:
      self = .needsRevision
    case .eliminated:
      self = .eliminated
    case .winner:
      self = .winner
    case .archived:
      self = .archived
    }
  }
}

private func evidenceSignals(
  contender: ProductTournamentContender,
  planReadiness: ProductTournamentPlanReadiness?,
  tournamentReadiness: ProductTournamentReadiness?,
  evidenceIndex: ProductTournamentEvidenceIndex,
  experiment: ProductTournamentExperiment?,
  proofDebt: ProofDebtSummary
) -> [EvidenceSignal] {
  let summaries = experiment.map { evidenceIndex.summaries(for: $0) } ?? []
  let completed = summaries.filter(\.isCompleted)
  let references = evidenceAuditReferences(
    planReadiness: planReadiness,
    tournamentReadiness: tournamentReadiness
  )
  return EvidenceDimension.defaultOrder.map { dimension in
    signal(
      dimension: dimension,
      planReadiness: planReadiness,
      tournamentReadiness: tournamentReadiness,
      completedSummaries: completed,
      proofDebt: proofDebt,
      references: references
    )
  }
}

private func signal(
  dimension: EvidenceDimension,
  planReadiness: ProductTournamentPlanReadiness?,
  tournamentReadiness: ProductTournamentReadiness?,
  completedSummaries: [ProductTournamentEvidenceSummary],
  proofDebt: ProofDebtSummary,
  references: [AuditReference]
) -> EvidenceSignal {
  switch dimension {
  case .painFit:
    return scoreSignal(
      dimension: dimension,
      values: completedSummaries.compactMap(\.scores.painRecognition),
      fallbackScore: planReadiness?.averageScore,
      noEvidencePhrase: "Pain proof missing",
      references: references
    )
  case .workflowLift:
    return scoreSignal(
      dimension: dimension,
      values: completedSummaries.compactMap(\.scores.workflowImprovement),
      noEvidencePhrase: "Workflow lift unproven",
      references: references
    )
  case .alternativeAdvantage:
    return scoreSignal(
      dimension: dimension,
      values: completedSummaries.compactMap(\.scores.alternativeAdvantage),
      noEvidencePhrase: "Alternative comparison missing",
      references: references
    )
  case .switchingReadiness:
    return scoreSignal(
      dimension: dimension,
      values: completedSummaries.compactMap(\.scores.switchingReadiness),
      noEvidencePhrase: "Switching readiness unproven",
      references: references
    )
  case .payIntent:
    return payIntentSignal(
      planReadiness: planReadiness,
      completedSummaries: completedSummaries,
      references: references
    )
  case .productUseProof:
    let completedCount = tournamentReadiness?.completedRunCount ?? 0
    let requiredCount = max(2, completedCount + (tournamentReadiness?.proofDebt.completedRunDeficit ?? 2))
    let strength: EvidenceStrength =
      completedCount >= requiredCount ? .strong : completedCount > 0 ? .progressing : .missing
    let label = "\(completedCount)/\(requiredCount)"
    return EvidenceSignal(
      dimension: .productUseProof,
      strength: proofDebt.readinessState.localizedCaseInsensitiveContains("locked")
        ? .blocked
        : strength,
      countLabel: label,
      primaryPhrase: completedCount > 0 ? "Product use proof \(label)" : "Product use proof missing",
      supportingPhrase: tournamentReadiness?.proofDebt.summary ?? proofDebt.nextProofTarget,
      sourceAuditReferences: references
    )
  case .personaBreadth:
    let count =
      tournamentReadiness?.distinctPersonaCount
      ?? planReadiness?.distinctPersonaCount
      ?? 0
    let deficit =
      tournamentReadiness?.proofDebt.personaDeficit
      ?? planReadiness?.planProofDebt.personaDeficit
      ?? 2
    let required = max(2, count + deficit)
    return EvidenceSignal(
      dimension: .personaBreadth,
      strength: count >= required ? .strong : count > 0 ? .progressing : .missing,
      countLabel: "\(count)/\(required)",
      primaryPhrase: count >= required ? "Persona breadth ready" : "Persona breadth missing",
      supportingPhrase: "\(count) distinct persona(s) covered",
      sourceAuditReferences: references
    )
  }
}

private func scoreSignal(
  dimension: EvidenceDimension,
  values: [Int],
  fallbackScore: Double? = nil,
  noEvidencePhrase: String,
  references: [AuditReference]
) -> EvidenceSignal {
  let average =
    values.isEmpty
    ? fallbackScore
    : values.map(Double.init).reduce(0, +) / Double(values.count)
  guard let average, average > 0 else {
    return EvidenceSignal(
      dimension: dimension,
      strength: .missing,
      countLabel: "missing",
      primaryPhrase: noEvidencePhrase,
      supportingPhrase: "No product signal recorded yet",
      sourceAuditReferences: references
    )
  }
  let rounded = (average * 10).rounded() / 10
  let strength = evidenceStrength(forAverage: rounded)
  return EvidenceSignal(
    dimension: dimension,
    strength: strength,
    countLabel: "\(formatScore(rounded))/5",
    primaryPhrase: "\(strengthLabel(strength)) \(dimension.label.lowercased())",
    supportingPhrase: "\(dimension.label) averages \(formatScore(rounded))/5",
    sourceAuditReferences: references
  )
}

private func payIntentSignal(
  planReadiness: ProductTournamentPlanReadiness?,
  completedSummaries: [ProductTournamentEvidenceSummary],
  references: [AuditReference]
) -> EvidenceSignal {
  let scores = completedSummaries.compactMap(\.scores.willingnessToPay)
  let average =
    !scores.isEmpty
    ? scores.map(Double.init).reduce(0, +) / Double(scores.count)
    : planReadiness?.averageWillingnessToPayScore
  guard let average, average > 0 else {
    let missing = planReadiness?.planProofDebt.willingnessToPayDeficit ?? 1
    return EvidenceSignal(
      dimension: .payIntent,
      strength: missing > 0 ? .missing : .neutral,
      countLabel: missing > 0 ? "missing" : "n/a",
      primaryPhrase: missing > 0 ? "Pay intent missing" : "Pay intent not required yet",
      supportingPhrase: planReadiness?.commercialProofSummary ?? "No buyer proof recorded yet",
      sourceAuditReferences: references
    )
  }
  let rounded = (average * 10).rounded() / 10
  let strength = evidenceStrength(forAverage: rounded)
  return EvidenceSignal(
    dimension: .payIntent,
    strength: strength,
    countLabel: "\(formatScore(rounded))/5",
    primaryPhrase: "\(strengthLabel(strength)) pay intent",
    supportingPhrase: planReadiness?.commercialProofSummary
      ?? "Buyer willingness averages \(formatScore(rounded))/5",
    sourceAuditReferences: references
  )
}

private func proofDebtSummary(
  contender: ProductTournamentContender,
  activeRound: ProductTournamentRound?,
  planReadiness: ProductTournamentPlanReadiness?,
  tournamentReadiness: ProductTournamentReadiness?,
  scoreboardRows: [TournamentAutomationProofTargetScoreboardRow],
  roundTwoTarget: ProductTournamentRoundImplementationTarget?,
  readModel: ProductTournamentReadModel
) -> ProofDebtSummary {
  if let roundTwoTarget,
    activeRound?.kind == .coreTechnology,
    roundTwoTarget.contenderID != contender.id
  {
    let targetTitle = readModel.contender(id: roundTwoTarget.contenderID)?.title ?? "another contender"
    return ProofDebtSummary(
      missingGates: ["Core-technology proof is locked to \(bounded(targetTitle, limit: 80))"],
      completedCount: 0,
      requiredCount: 1,
      nextProofTarget: "Wait for the active core-technology proof to finish",
      readinessState: "Core-technology proof locked",
      blockingCount: 1,
      auditReferences: [
        AuditReference(kind: .contender, label: "Locked contender ID", value: roundTwoTarget.contenderID),
        AuditReference(kind: .experiment, label: "Locked experiment ID", value: roundTwoTarget.experimentID),
      ]
    )
  }

  if let planReadiness,
    activeRound?.kind == .productPlans || !planReadiness.planProofDebt.isClear
  {
    return ProofDebtSummary(
      missingGates: planReadiness.planProofDebt.debtLabels.map { productProofDebtLabel($0) },
      completedCount: planReadiness.completedEvaluationCount,
      requiredCount: max(
        planReadiness.completedEvaluationCount + planReadiness.planProofDebt.evaluationDeficit,
        2
      ),
      nextProofTarget: bounded(planReadiness.nextProofTargetSummary, limit: 160),
      readinessState: planReadiness.planProofDebt.isClear
        ? "Ready for feasibility build"
        : "Plan proof missing",
      blockingCount: planReadiness.planProofDebt.blockingDebtCount,
      auditReferences: planReadinessAuditReferences(planReadiness)
    )
  }

  if activeRound?.kind == .productPlans, planReadiness == nil {
    let row = scoreboardRows.first
    return ProofDebtSummary(
      missingGates: ["Plan proof missing"],
      completedCount: 0,
      requiredCount: 2,
      nextProofTarget: "operator and economic-buyer plan evaluations",
      readinessState: "Plan proof missing",
      blockingCount: 4,
      auditReferences: row.map {
        rowAuditReferences(row: $0)
      } ?? []
    )
  }

  if let tournamentReadiness {
    return ProofDebtSummary(
      missingGates: tournamentReadiness.proofDebt.debtLabels.map { productProofDebtLabel($0) },
      completedCount: tournamentReadiness.completedRunCount,
      requiredCount: max(
        tournamentReadiness.completedRunCount
          + tournamentReadiness.proofDebt.completedRunDeficit,
        2
      ),
      nextProofTarget: tournamentReadiness.proofDebt.isClear
        ? "decision review"
        : productTournamentNextProofTarget(tournamentReadiness.proofDebt),
      readinessState: tournamentReadiness.proofDebt.isClear
        ? productReadinessState(tournamentReadiness.recommendation)
        : "Product proof missing",
      blockingCount: tournamentReadiness.proofDebt.blockingDebtCount,
      auditReferences: tournamentReadinessAuditReferences(tournamentReadiness)
    )
  }

  if let row = scoreboardRows.first {
    return ProofDebtSummary(
      missingGates: [bounded(row.debtSummary, limit: 140)],
      completedCount: 0,
      requiredCount: 1,
      nextProofTarget: bounded(row.targetLabel, limit: 140),
      readinessState: row.nextStatusLabel,
      blockingCount: 1,
      auditReferences: rowAuditReferences(row: row)
    )
  }

  return ProofDebtSummary(
    missingGates: ["Evidence not started"],
    completedCount: 0,
    requiredCount: 1,
    nextProofTarget: "first product proof",
    readinessState: "No proof yet",
    blockingCount: 1,
    auditReferences: []
  )
}

private func roundState(
  contender: ProductTournamentContender,
  tournament: ProductTournament,
  activeRound: ProductTournamentRound?,
  roundTwoTarget: ProductTournamentRoundImplementationTarget?,
  readModel: ProductTournamentReadModel
) -> RoundStateSummary {
  if contender.status == .winner {
    return RoundStateSummary(
      state: .winner,
      title: "Winner selected",
      detail: "This contender is the selected winner."
    )
  }
  if contender.status == .eliminated || contender.status == .archived {
    return RoundStateSummary(
      state: .eliminated,
      title: "No longer competing",
      detail: "\(bounded(contender.title, limit: 80)) is not in the active decision path."
    )
  }
  guard let activeRound else {
    return RoundStateSummary(
      state: .pending,
      title: "No active round",
      detail: "Tournament round is not selected yet."
    )
  }
  if let roundTwoTarget,
    activeRound.kind == .coreTechnology,
    roundTwoTarget.contenderID != contender.id
  {
    let targetTitle = readModel.contender(id: roundTwoTarget.contenderID)?.title ?? "another contender"
    return RoundStateSummary(
      state: .blocked,
      title: "Proof locked",
      detail: "Core-technology proof is locked to \(bounded(targetTitle, limit: 80))."
    )
  }
  let roundContenderIDs =
    activeRound.contenderIDs.isEmpty ? tournament.contenderIDs : activeRound.contenderIDs
  guard roundContenderIDs.contains(contender.id) else {
    return RoundStateSummary(
      state: .paused,
      title: "Outside active round",
      detail: "This contender is not part of \(productRoundTitle(for: activeRound))."
    )
  }
  switch activeRound.status {
  case .active:
    return RoundStateSummary(
      state: .active,
      title: "Active in \(productRoundTitle(for: activeRound))",
      detail: activeRound.goal
    )
  case .planned:
    return RoundStateSummary(
      state: .pending,
      title: "Queued for \(productRoundTitle(for: activeRound))",
      detail: activeRound.goal
    )
  case .completed:
    return RoundStateSummary(
      state: .completed,
      title: "\(productRoundTitle(for: activeRound)) complete",
      detail: activeRound.goal
    )
  case .skipped:
    return RoundStateSummary(
      state: .paused,
      title: "\(productRoundTitle(for: activeRound)) skipped",
      detail: activeRound.goal
    )
  }
}

private func targetSegmentNames(
  for contender: ProductTournamentContender,
  plan: ProductTournamentContenderPlan?,
  readModel: ProductTournamentReadModel
) -> [String] {
  let ids = contender.targetSegmentIDs.isEmpty ? plan?.targetSegmentIDs ?? [] : contender.targetSegmentIDs
  let names = ids.compactMap { readModel.segment(id: $0)?.name }
  return names.isEmpty ? ["Target segment not selected"] : names.sorted()
}

private func currentAlternative(
  for contender: ProductTournamentContender,
  plan: ProductTournamentContenderPlan?,
  readModel: ProductTournamentReadModel
) -> String {
  let ids = contender.targetSegmentIDs.isEmpty ? plan?.targetSegmentIDs ?? [] : contender.targetSegmentIDs
  for segmentID in ids {
    guard let segment = readModel.segment(id: segmentID) else { continue }
    for alternativeID in segment.alternativeIDs {
      if let alternative = readModel.alternative(id: alternativeID) {
        return bounded(alternative.title, limit: 120)
      }
    }
  }
  return "Current alternative not selected"
}

private func tournamentPosition(
  contender: ProductTournamentContender,
  tournament: ProductTournament,
  activeRound: ProductTournamentRound?,
  readModel: ProductTournamentReadModel
) -> String {
  let contenders: [ProductTournamentContender]
  if let activeRound {
    contenders = readModel.contenders(in: activeRound)
  } else {
    contenders = readModel.contenders(in: tournament)
  }
  let activeContenders = contenders.filter { contenderStatusRank($0.status) <= 3 }
  let positioned = activeContenders.isEmpty ? contenders : activeContenders
  let sorted = positioned.sorted {
    if $0.createdAt == $1.createdAt { return $0.id < $1.id }
    return $0.createdAt < $1.createdAt
  }
  guard let index = sorted.firstIndex(where: { $0.id == contender.id }) else {
    return "Outside the active contender set"
  }
  let roundLabel = activeRound.map(productRoundTitle) ?? "tournament"
  return "Contender \(index + 1) of \(sorted.count) in \(roundLabel)"
}

private func cockpitAuditReferences(
  tournament: ProductTournament,
  pain: PainHypothesis?,
  activeRound: ProductTournamentRound?
) -> [AuditReference] {
  var references = [
    AuditReference(kind: .tournament, label: "Tournament ID", value: tournament.id)
  ]
  if let pain {
    references.append(AuditReference(kind: .pain, label: "Pain ID", value: pain.id))
  }
  if let activeRound {
    references.append(AuditReference(kind: .round, label: "Round ID", value: activeRound.id))
  }
  return references
}

private func contenderAuditReferences(
  contender: ProductTournamentContender,
  plan: ProductTournamentContenderPlan?,
  experiment: ProductTournamentExperiment?
) -> [AuditReference] {
  var references = [
    AuditReference(kind: .contender, label: "Contender ID", value: contender.id)
  ]
  if let plan {
    references.append(AuditReference(kind: .contenderPlan, label: "Contender plan ID", value: plan.id))
  }
  if let experiment {
    references.append(AuditReference(kind: .experiment, label: "Experiment ID", value: experiment.id))
    references.append(AuditReference(kind: .branch, label: "Branch", value: experiment.branchName))
    if let baseSha = experiment.baseSha {
      references.append(AuditReference(kind: .commit, label: "Base commit", value: baseSha))
    }
    if let currentSha = experiment.currentSha {
      references.append(AuditReference(kind: .commit, label: "Current commit", value: currentSha))
    }
  }
  return references
}

private func stepAuditReferences(
  step: TournamentAutomationStep,
  row: TournamentAutomationProofTargetScoreboardRow?
) -> [AuditReference] {
  var references = [
    AuditReference(kind: .experiment, label: "Experiment ID", value: step.experimentID)
  ]
  if let tournamentID = step.tournamentID {
    references.append(AuditReference(kind: .tournament, label: "Tournament ID", value: tournamentID))
  }
  if let roundID = step.roundID {
    references.append(AuditReference(kind: .round, label: "Round ID", value: roundID))
  }
  if let contenderID = step.contenderID {
    references.append(AuditReference(kind: .contender, label: "Contender ID", value: contenderID))
  }
  if let cohortID = step.cohortID {
    references.append(AuditReference(kind: .cohort, label: "Cohort ID", value: cohortID))
  }
  if let scenarioID = step.targetScenarioID {
    references.append(AuditReference(kind: .scenario, label: "Scenario ID", value: scenarioID))
  }
  if let row {
    references += rowAuditReferences(row: row)
  }
  return references
}

private func rowAuditReferences(row: TournamentAutomationProofTargetScoreboardRow) -> [AuditReference] {
  var references: [AuditReference] = [
    AuditReference(kind: .experiment, label: "Experiment ID", value: row.experimentID)
  ]
  if let tournamentID = row.tournamentID {
    references.append(AuditReference(kind: .tournament, label: "Tournament ID", value: tournamentID))
  }
  if let roundID = row.roundID {
    references.append(AuditReference(kind: .round, label: "Round ID", value: roundID))
  }
  if let contenderID = row.contenderID {
    references.append(AuditReference(kind: .contender, label: "Contender ID", value: contenderID))
  }
  if let cohortID = row.cohortID {
    references.append(AuditReference(kind: .cohort, label: "Cohort ID", value: cohortID))
  }
  if let scenarioID = row.targetScenarioID {
    references.append(AuditReference(kind: .scenario, label: "Scenario ID", value: scenarioID))
  }
  if let movement = row.latestDebtMovement {
    references.append(
      AuditReference(kind: .automationAudit, label: "Automation audit ID", value: movement.auditID))
  }
  return references
}

private func planReadinessAuditReferences(
  _ readiness: ProductTournamentPlanReadiness
) -> [AuditReference] {
  var references: [AuditReference] = [
    AuditReference(kind: .contender, label: "Contender ID", value: readiness.contenderID),
    AuditReference(kind: .tournament, label: "Tournament ID", value: readiness.tournamentID),
    AuditReference(kind: .round, label: "Round ID", value: readiness.roundID),
  ]
  if let latest = readiness.latestEvaluationID {
    references.append(AuditReference(kind: .planEvaluation, label: "Latest plan evaluation ID", value: latest))
  }
  references += readiness.evaluationIDs.prefix(4).map {
    AuditReference(kind: .planEvaluation, label: "Plan evaluation ID", value: $0)
  }
  return uniqueAuditReferences(references)
}

private func tournamentReadinessAuditReferences(
  _ readiness: ProductTournamentReadiness
) -> [AuditReference] {
  var references: [AuditReference] = [
    AuditReference(kind: .experiment, label: "Experiment ID", value: readiness.experimentID)
  ]
  if let latest = readiness.latestRunID {
    references.append(AuditReference(kind: .evidenceRun, label: "Latest evidence run ID", value: latest))
  }
  references += readiness.evidenceRunIDs.prefix(4).map {
    AuditReference(kind: .evidenceRun, label: "Evidence run ID", value: $0)
  }
  return uniqueAuditReferences(references)
}

private func evidenceAuditReferences(
  planReadiness: ProductTournamentPlanReadiness?,
  tournamentReadiness: ProductTournamentReadiness?
) -> [AuditReference] {
  uniqueAuditReferences(
    (planReadiness.map(planReadinessAuditReferences) ?? [])
      + (tournamentReadiness.map(tournamentReadinessAuditReferences) ?? [])
  )
}

private func uniqueAuditReferences(_ references: [AuditReference]) -> [AuditReference] {
  var seen: Set<AuditReference> = []
  var result: [AuditReference] = []
  for reference in references where !reference.value.isEmpty {
    if seen.insert(reference).inserted {
      result.append(reference)
    }
  }
  return result
}

private func productRoundTitle(for round: ProductTournamentRound) -> String {
  switch round.kind {
  case .marketCompilation:
    return "Round \(round.ordinal): Market compilation"
  case .productPlans:
    return "Round \(round.ordinal): Plan proof"
  case .coreTechnology:
    return "Round \(round.ordinal): Core technology"
  case .productImplementation:
    return "Round \(round.ordinal): Product use"
  }
}

private func gateDescription(for round: ProductTournamentRound) -> String {
  if !round.evaluationFocus.isEmpty {
    return bounded(round.evaluationFocus.prefix(3).joined(separator: ", "), limit: 180)
  }
  return bounded(round.goal, limit: 180)
}

private func tournamentStatusLabel(_ status: ProductTournamentStatus) -> String {
  switch status {
  case .drafting: return "Drafting"
  case .active: return "Active"
  case .completed: return "Completed"
  case .archived: return "Archived"
  }
}

private func roundStatusLabel(_ status: ProductTournamentRoundStatus) -> String {
  switch status {
  case .planned: return "Planned"
  case .active: return "Active"
  case .completed: return "Completed"
  case .skipped: return "Skipped"
  }
}

private func productActionTitle(for step: TournamentAutomationStep) -> String {
  switch step.kind {
  case .applyDecision:
    return "Apply product decision"
  case .applyRoundTransition:
    if step.roundID != nil {
      return "Apply round decision"
    }
    return "Advance product contender"
  case .prepareWorktree:
    return "Prepare implementation track"
  case .runPlanProof:
    return step.action.requiredSimulationMode == .personaModel
      ? "Run persona plan proof"
      : "Run plan proof"
  case .runCohort:
    if step.action.targetDecision == .promote {
      return "Run validation proof"
    }
    if step.action.targetDecision == .kill {
      return "Run rejection proof"
    }
    return "Run product proof cohort"
  case .applyRevision:
    return "Apply product revision"
  case .blocked:
    return "Resolve proof blocker"
  }
}

private func nextMoveWhy(
  row: TournamentAutomationProofTargetScoreboardRow?,
  step: TournamentAutomationStep
) -> String {
  if let row {
    if row.debtSummary.localizedCaseInsensitiveContains("willingness")
      || row.debtSummary.localizedCaseInsensitiveContains("pay")
    {
      return "Buyer proof is the clearest missing signal for \(bounded(row.contenderTitle, limit: 80))."
    }
    return "\(bounded(row.contenderTitle, limit: 80)) needs \(bounded(row.targetLabel.lowercased(), limit: 120)) before the next decision."
  }
  switch step.kind {
  case .applyDecision:
    return "Current evidence is ready to update the tournament decision."
  case .applyRoundTransition:
    return "The active proof gate is ready for a round decision."
  case .prepareWorktree:
    return "The next proof needs an implementation track before users can test it."
  case .runPlanProof:
    return "The product plan needs simulated-user proof before feasibility work."
  case .runCohort:
    return "The product contender needs more user evidence against the current alternative."
  case .applyRevision:
    return "Evidence points to a revision before more proof is useful."
  case .blocked:
    return "A workflow blocker is preventing the next proof."
  }
}

private func expectedDecision(for step: TournamentAutomationStep) -> String {
  if let targetDecision = step.action.targetDecision {
    return "Decide whether to \(targetDecisionLabel(targetDecision))"
  }
  switch step.kind {
  case .applyDecision:
    return "Update the product decision"
  case .applyRoundTransition:
    return "Advance, revise, or eliminate the contender"
  case .prepareWorktree:
    return "Unlock product-use proof"
  case .runPlanProof:
    return "Advance to feasibility, revise the plan, or eliminate"
  case .runCohort:
    return "Continue, pivot, promote, or stop the contender"
  case .applyRevision:
    return "Retest the revised product direction"
  case .blocked:
    return "Clear the blocker before deciding"
  }
}

private func targetDecisionLabel(_ decision: ProductTournamentExperimentDecision) -> String {
  switch decision {
  case .notRun: return "start proof"
  case .keepGoing: return "continue"
  case .narrow: return "narrow"
  case .pivot: return "pivot"
  case .kill: return "eliminate"
  case .promote: return "promote"
  case .archived: return "archive"
  case .promoted: return "mark promoted"
  }
}

private func disabledReason(for step: TournamentAutomationStep) -> String {
  if let reason = step.blockedReason?.lowercased() {
    if reason.contains("persona") {
      return "Persona-model proof is not available for this run."
    }
    if reason.contains("contract") {
      return "The tournament experience contract is missing."
    }
    if reason.contains("enabled scenario") || reason.contains("scenario") {
      return "No enabled product-test scenario is ready."
    }
    if reason.contains("locked") {
      return "Core-technology proof is locked to another contender."
    }
  }
  return "The next proof is not executable yet."
}

private func productProofDebtLabel(_ raw: String) -> String {
  let lower = raw.lowercased()
  if lower.contains("buyer") || lower.contains("sponsor") {
    return "Buyer proof missing"
  }
  if lower.contains("willingness") || lower.contains("pay") {
    return "Pay intent weak"
  }
  if lower.contains("persona-model current-alternative") {
    return "Persona-model alternative proof missing"
  }
  if lower.contains("persona-model") {
    return "Persona-model proof missing"
  }
  if lower.contains("persona") {
    return "Persona breadth missing"
  }
  if lower.contains("completed run") {
    return "Completed product-use proof missing"
  }
  if lower.contains("evaluation") {
    return "Plan evaluation missing"
  }
  if lower.contains("failed") {
    return "Failed proof needs repair"
  }
  return bounded(raw, limit: 120)
}

private func productTournamentNextProofTarget(
  _ debt: ProductTournamentProofDebt
) -> String {
  if debt.failedRunCount > 0 {
    return "repair failed product-use proof"
  }
  if debt.completedRunDeficit > 0 {
    return "additional completed product-use proof"
  }
  if debt.personaDeficit > 0 {
    return "new distinct persona proof"
  }
  if debt.personaModelSimulatedUserDeficit > 0 {
    return "persona-model simulated-user proof"
  }
  if debt.personaModelCurrentAlternativeDeficit > 0 {
    return "persona-model current-alternative proof"
  }
  return "decision review"
}

private func productReadinessState(
  _ recommendation: ProductTournamentReadinessRecommendation
) -> String {
  switch recommendation {
  case .gatherEvidence:
    return "More proof needed"
  case .keepGoing:
    return "Ready to keep testing"
  case .narrow:
    return "Narrowing proof ready"
  case .pivot:
    return "Revision proof ready"
  case .kill:
    return "Elimination proof ready"
  case .promote:
    return "Promotion proof ready"
  }
}

private func evidenceStrength(forAverage average: Double) -> EvidenceStrength {
  if average >= 4.0 { return .strong }
  if average >= 3.0 { return .progressing }
  if average > 0 && average <= 2.2 { return .risk }
  return .missing
}

private func strengthLabel(_ strength: EvidenceStrength) -> String {
  switch strength {
  case .strong: return "Strong"
  case .progressing: return "Progressing"
  case .missing: return "Missing"
  case .blocked: return "Blocked"
  case .risk: return "Risky"
  case .neutral: return "Neutral"
  }
}

private func contenderStatusRank(_ status: ProductTournamentContenderStatus) -> Int {
  switch status {
  case .winner: return 0
  case .narrowed: return 1
  case .competing: return 2
  case .needsRevision: return 3
  case .eliminated: return 4
  case .archived: return 5
  }
}

private func matchingMarket(
  for pain: PainHypothesis,
  in config: ProductTournamentConfig
) -> ProductMarket? {
  config.markets.first { $0.painID == pain.id }
}

private func formatScore(_ value: Double) -> String {
  String(format: "%.1f", value)
}

private func bounded(_ text: String, limit: Int) -> String {
  StringUtils.boundedText(text, limit: limit)
}
