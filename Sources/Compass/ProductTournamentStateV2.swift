import Foundation

struct ProductTournamentStateV2: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1

  var schemaVersion: Int
  var pain: TournamentPainV2?
  var segments: [TournamentSegmentV2]
  var alternatives: [TournamentAlternativeV2]
  var contenders: [TournamentContenderV2]
  var rounds: [TournamentRoundStateV2]
  var activeRoundID: String?
  var outcome: TournamentOutcomeV2?
  var decisionLog: [TournamentDecisionEventV2]

  static let empty = ProductTournamentStateV2(
    pain: nil,
    segments: [],
    alternatives: [],
    contenders: [],
    rounds: [],
    activeRoundID: nil,
    outcome: nil,
    decisionLog: []
  )

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    pain: TournamentPainV2?,
    segments: [TournamentSegmentV2],
    alternatives: [TournamentAlternativeV2],
    contenders: [TournamentContenderV2],
    rounds: [TournamentRoundStateV2],
    activeRoundID: String?,
    outcome: TournamentOutcomeV2?,
    decisionLog: [TournamentDecisionEventV2]
  ) {
    self.schemaVersion = schemaVersion
    self.pain = pain
    self.segments = segments
    self.alternatives = alternatives
    self.contenders = contenders
    self.rounds = rounds
    self.activeRoundID = activeRoundID
    self.outcome = outcome
    self.decisionLog = decisionLog
  }

  init(converting config: ProductTournamentConfig) {
    let readModel = ProductTournamentReadModel(config: config)
    let tournament = readModel.activeTournament() ?? config.tournaments.first
    let pain = tournament.flatMap { readModel.pain(for: $0) } ?? config.painHypotheses.first
    let painID = pain?.id ?? tournament?.painID
    let tournamentContenders = tournament.map { readModel.contenders(in: $0) }
      ?? config.tournamentContenders
    let tournamentRounds = tournament.map { readModel.rounds(in: $0) }
      ?? config.tournamentRounds

    self.init(
      pain: pain.map(TournamentPainV2.init),
      segments: config.userSegments
        .filter { painID == nil || $0.painID == painID }
        .map(TournamentSegmentV2.init),
      alternatives: config.alternatives
        .filter { painID == nil || $0.painID == painID }
        .map(TournamentAlternativeV2.init),
      contenders: tournamentContenders.map { contender in
        TournamentContenderV2(
          contender: contender,
          plan: readModel.plan(for: contender),
          implementationTrack: readModel.experiment(for: contender).map(
            TournamentImplementationTrackV2.init)
        )
      },
      rounds: tournamentRounds.map(TournamentRoundStateV2.init),
      activeRoundID: tournament.flatMap { readModel.activeRound(in: $0)?.id },
      outcome: Self.outcome(from: tournament, contenders: tournamentContenders),
      decisionLog: config.decisions.map(TournamentDecisionEventV2.init)
    )
  }

  func validate() throws {
    if let error = validationErrors().first {
      throw error
    }
  }

  func validationErrors() -> [ProductTournamentStateV2ValidationError] {
    var errors: [ProductTournamentStateV2ValidationError] = []
    errors += duplicateIDErrors(entity: "segment", values: segments.map(\.id))
    errors += duplicateIDErrors(entity: "alternative", values: alternatives.map(\.id))
    errors += duplicateIDErrors(entity: "contender", values: contenders.map(\.id))
    errors += duplicateIDErrors(entity: "round", values: rounds.map(\.id))
    errors += duplicateIDErrors(entity: "decision", values: decisionLog.map(\.id))

    let contenderIDs = Set(contenders.map(\.id))
    let roundIDs = Set(rounds.map(\.id))
    if let activeRoundID {
      if !roundIDs.contains(activeRoundID) {
        errors.append(.missingActiveRound(activeRoundID))
      }
    } else if outcome == nil && (!contenders.isEmpty || !rounds.isEmpty) {
      errors.append(.unresolvedTournamentWithoutActiveRound)
    }

    for round in rounds {
      for contenderID in round.contenderIDs where !contenderIDs.contains(contenderID) {
        errors.append(.unknownRoundContender(roundID: round.id, contenderID: contenderID))
      }
    }

    let winnerIDs = contenders.filter { $0.lifecycle == .winner }.map(\.id)
    if outcome == nil {
      errors += winnerIDs.map { .winnerWithoutOutcome($0) }
    }
    if let outcome, !contenderIDs.contains(outcome.winnerContenderID) {
      errors.append(.outcomeMissingWinner(outcome.winnerContenderID))
    }
    return errors
  }

  func applyingRoundOneTransition(
    contenderID: String,
    recommendation: ProductTournamentPlanRecommendation,
    now: Date = Date()
  ) throws -> ProductTournamentStateV2 {
    guard let activeRoundID else {
      throw ProductTournamentStateV2TransitionError.missingActiveRound
    }
    guard let activeRoundIndex = rounds.firstIndex(where: { $0.id == activeRoundID }) else {
      throw ProductTournamentStateV2TransitionError.unknownRound(activeRoundID)
    }
    guard rounds[activeRoundIndex].kind == .productPlans else {
      throw ProductTournamentStateV2TransitionError.unsupportedRound(rounds[activeRoundIndex].id)
    }
    guard let contenderIndex = contenders.firstIndex(where: { $0.id == contenderID }) else {
      throw ProductTournamentStateV2TransitionError.unknownContender(contenderID)
    }

    var next = self
    let timestamp = now.timeIntervalSince1970
    switch recommendation {
    case .advanceToFeasibility:
      guard
        let feasibilityRoundIndex = next.rounds.firstIndex(where: {
          $0.kind == .coreTechnology && $0.ordinal > next.rounds[activeRoundIndex].ordinal
        })
      else {
        throw ProductTournamentStateV2TransitionError.missingFeasibilityRound
      }
      next.rounds[activeRoundIndex].lifecycle = .completed
      next.rounds[feasibilityRoundIndex].lifecycle = .active
      next.rounds[feasibilityRoundIndex].contenderIDs = [contenderID]
      next.contenders[contenderIndex].lifecycle = .narrowed
      next.activeRoundID = next.rounds[feasibilityRoundIndex].id

    case .revisePlan:
      next.rounds[activeRoundIndex].lifecycle = .active
      next.contenders[contenderIndex].lifecycle = .needsRevision

    case .eliminate:
      next.contenders[contenderIndex].lifecycle = .eliminated
      for roundIndex in next.rounds.indices
      where next.rounds[roundIndex].ordinal > next.rounds[activeRoundIndex].ordinal {
        next.rounds[roundIndex].contenderIDs.removeAll { $0 == contenderID }
      }

    case .gatherEvidence:
      break
    }
    next.contenders[contenderIndex].updatedAt = timestamp
    try next.validate()
    return next
  }

  private static func outcome(
    from tournament: ProductTournament?,
    contenders: [ProductTournamentContender]
  ) -> TournamentOutcomeV2? {
    guard tournament?.status == .completed,
      let winner = contenders.first(where: { $0.status == .winner })
    else { return nil }
    return TournamentOutcomeV2(
      winnerContenderID: winner.id,
      summary: "\(winner.title) won the product tournament.",
      completedAt: max(tournament?.updatedAt ?? winner.updatedAt, winner.updatedAt)
    )
  }

  private func duplicateIDErrors(
    entity: String,
    values: [String]
  ) -> [ProductTournamentStateV2ValidationError] {
    var seen = Set<String>()
    return values.compactMap { id in
      seen.insert(id).inserted ? nil : .duplicateID(entity: entity, id: id)
    }
  }
}

struct TournamentPainV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var title: String
  var rawPain: String
  var targetSituation: String
  var successSignals: [String]

  init(_ pain: PainHypothesis) {
    self.id = pain.id
    self.title = pain.title
    self.rawPain = pain.rawPain
    self.targetSituation = pain.targetSituation
    self.successSignals = pain.successSignals
  }
}

struct TournamentSegmentV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var name: String
  var role: String
  var currentWorkflowIDs: [String]
  var alternativeIDs: [String]
  var decisionCriteria: [String]

  init(_ segment: UserSegment) {
    self.id = segment.id
    self.name = segment.name
    self.role = segment.role
    self.currentWorkflowIDs = segment.currentWorkflowIDs
    self.alternativeIDs = segment.alternativeIDs
    self.decisionCriteria = segment.decisionCriteria
  }
}

struct TournamentAlternativeV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var title: String
  var kind: AlternativeKind
  var strengths: [String]
  var weaknesses: [String]
  var switchingCost: String

  init(_ alternative: Alternative) {
    self.id = alternative.id
    self.title = alternative.title
    self.kind = alternative.kind
    self.strengths = alternative.strengths
    self.weaknesses = alternative.weaknesses
    self.switchingCost = alternative.switchingCost
  }
}

struct TournamentContenderV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var title: String
  var plan: TournamentProductPlanV2
  var implementationTrack: TournamentImplementationTrackV2?
  var lifecycle: TournamentContenderLifecycleV2
  var targetSegmentIDs: [String]
  var updatedAt: Double

  init(
    contender: ProductTournamentContender,
    plan: ProductTournamentContenderPlan?,
    implementationTrack: TournamentImplementationTrackV2?
  ) {
    self.id = contender.id
    self.title = contender.title
    self.plan = TournamentProductPlanV2(contender: contender, plan: plan)
    self.implementationTrack = implementationTrack
    self.lifecycle = TournamentContenderLifecycleV2(contender.status)
    self.targetSegmentIDs = contender.targetSegmentIDs
    self.updatedAt = contender.updatedAt
  }
}

struct TournamentProductPlanV2: Codable, Equatable, Sendable {
  var id: String
  var title: String
  var promise: String
  var productPlan: String
  var valueProposition: String
  var primaryRisk: String
  var requiredProof: [String]

  init(
    contender: ProductTournamentContender,
    plan: ProductTournamentContenderPlan?
  ) {
    self.id = plan?.id ?? contender.contenderPlanID
    self.title = plan?.title ?? contender.title
    self.promise = plan?.promise ?? contender.valueProposition
    self.productPlan = contender.productPlan
    self.valueProposition = contender.valueProposition
    self.primaryRisk = contender.primaryRisk
    self.requiredProof = plan?.requiredProof ?? []
  }
}

struct TournamentImplementationTrackV2: Codable, Equatable, Sendable {
  var experimentID: String
  var title: String
  var branchName: String
  var worktreeID: String
  var currentSha: String?
  var implementationScope: String
  var decision: ProductTournamentExperimentDecision

  init(_ experiment: ProductTournamentExperiment) {
    self.experimentID = experiment.id
    self.title = experiment.title
    self.branchName = experiment.branchName
    self.worktreeID = experiment.worktreeID
    self.currentSha = experiment.currentSha ?? experiment.baseSha
    self.implementationScope = experiment.implementationScope
    self.decision = experiment.decision
  }
}

enum TournamentContenderLifecycleV2: String, Codable, Equatable, Sendable {
  case competing
  case narrowed
  case needsRevision = "needs_revision"
  case eliminated
  case winner
  case archived

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

struct TournamentRoundStateV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var ordinal: Int
  var kind: ProductTournamentRoundKind
  var title: String
  var goal: String
  var evaluationFocus: [String]
  var contenderIDs: [String]
  var scenarioCohortIDs: [String]
  var lifecycle: TournamentRoundLifecycleV2

  init(_ round: ProductTournamentRound) {
    self.id = round.id
    self.ordinal = round.ordinal
    self.kind = round.kind
    self.title = round.title
    self.goal = round.goal
    self.evaluationFocus = round.evaluationFocus
    self.contenderIDs = round.contenderIDs
    self.scenarioCohortIDs = round.scenarioCohortIDs
    self.lifecycle = TournamentRoundLifecycleV2(round.status)
  }
}

enum TournamentRoundLifecycleV2: String, Codable, Equatable, Sendable {
  case planned
  case active
  case completed
  case skipped

  init(_ status: ProductTournamentRoundStatus) {
    switch status {
    case .planned:
      self = .planned
    case .active:
      self = .active
    case .completed:
      self = .completed
    case .skipped:
      self = .skipped
    }
  }
}

struct TournamentOutcomeV2: Codable, Equatable, Sendable {
  var winnerContenderID: String
  var summary: String
  var completedAt: Double
}

struct TournamentDecisionEventV2: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var experimentID: String
  var decision: ProductTournamentExperimentDecision
  var summary: String
  var evidenceRunIDs: [String]
  var decidedAt: Double
  var decidedBy: String

  init(_ decision: ProductTournamentDecision) {
    self.id = decision.id
    self.experimentID = decision.experimentID
    self.decision = decision.decision
    self.summary = decision.summary
    self.evidenceRunIDs = decision.evidenceRunIDs
    self.decidedAt = decision.decidedAt
    self.decidedBy = decision.decidedBy
  }
}

enum ProductTournamentStateV2ValidationError: LocalizedError, Equatable {
  case duplicateID(entity: String, id: String)
  case missingActiveRound(String)
  case unresolvedTournamentWithoutActiveRound
  case unknownRoundContender(roundID: String, contenderID: String)
  case winnerWithoutOutcome(String)
  case outcomeMissingWinner(String)

  var errorDescription: String? {
    switch self {
    case .duplicateID(let entity, let id):
      return "Duplicate tournament \(entity) ID \(id)."
    case .missingActiveRound(let id):
      return "Active tournament round \(id) is missing from tournament state."
    case .unresolvedTournamentWithoutActiveRound:
      return "Unresolved tournament state must include an active round."
    case .unknownRoundContender(let roundID, let contenderID):
      return "Tournament round \(roundID) references unknown contender \(contenderID)."
    case .winnerWithoutOutcome(let contenderID):
      return "Contender \(contenderID) is marked winner without a completed tournament outcome."
    case .outcomeMissingWinner(let contenderID):
      return "Tournament outcome references unknown winner contender \(contenderID)."
    }
  }
}

enum ProductTournamentStateV2TransitionError: LocalizedError, Equatable {
  case missingActiveRound
  case unknownRound(String)
  case unsupportedRound(String)
  case unknownContender(String)
  case missingFeasibilityRound

  var errorDescription: String? {
    switch self {
    case .missingActiveRound:
      return "Round 1 transition requires an active tournament round."
    case .unknownRound(let id):
      return "Tournament round \(id) was not found in simplified state."
    case .unsupportedRound(let id):
      return "Tournament round \(id) is not a Round 1 product-plan round."
    case .unknownContender(let id):
      return "Tournament contender \(id) was not found in simplified state."
    case .missingFeasibilityRound:
      return "Simplified tournament state has no Round 2 feasibility round."
    }
  }
}
