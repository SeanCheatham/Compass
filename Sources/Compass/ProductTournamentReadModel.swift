import Foundation

struct TournamentContenderNode: Equatable, Sendable, Identifiable {
  var id: String { contender.id }

  var contender: ProductTournamentContender
  var plan: ProductTournamentContenderPlan
  var experiment: ProductTournamentExperiment?
}

struct ProductTournamentReadModel: Sendable {
  var config: ProductTournamentConfig

  private let tournamentsByID: [String: ProductTournament]
  private let painHypothesesByID: [String: PainHypothesis]
  private let segmentsByID: [String: UserSegment]
  private let workflowsByID: [String: CurrentWorkflow]
  private let alternativesByID: [String: Alternative]
  private let contenderPlansByID: [String: ProductTournamentContenderPlan]
  private let experimentsByID: [String: ProductTournamentExperiment]
  private let contendersByID: [String: ProductTournamentContender]
  private let roundsByID: [String: ProductTournamentRound]
  private let scenariosByID: [String: ProductScenario]
  private let cohortsByID: [String: ProductScenarioCohort]
  private let contendersByTournamentID: [String: [ProductTournamentContender]]
  private let roundsByTournamentID: [String: [ProductTournamentRound]]
  private let scenariosByExperimentID: [String: [ProductScenario]]
  private let cohortsByExperimentID: [String: [ProductScenarioCohort]]

  init(config: ProductTournamentConfig) {
    self.config = config
    self.tournamentsByID = Self.indexed(config.tournaments)
    self.painHypothesesByID = Self.indexed(config.painHypotheses)
    self.segmentsByID = Self.indexed(config.userSegments)
    self.workflowsByID = Self.indexed(config.currentWorkflows)
    self.alternativesByID = Self.indexed(config.alternatives)
    self.contenderPlansByID = Self.indexed(config.contenderPlans)
    self.experimentsByID = Self.indexed(config.tournamentExperiments)
    self.contendersByID = Self.indexed(config.tournamentContenders)
    self.roundsByID = Self.indexed(config.tournamentRounds)
    self.scenariosByID = Self.indexed(config.scenarios)
    self.cohortsByID = Self.indexed(config.scenarioCohorts)
    self.contendersByTournamentID = Dictionary(grouping: config.tournamentContenders) {
      $0.tournamentID
    }
    .mapValues(Self.stableContenderOrder)
    self.roundsByTournamentID = Dictionary(grouping: config.tournamentRounds) { $0.tournamentID }
      .mapValues(Self.stableRoundOrder)
    self.scenariosByExperimentID = Dictionary(grouping: config.scenarios) { $0.experimentID }
      .mapValues { $0.sorted { $0.id < $1.id } }
    self.cohortsByExperimentID = Dictionary(grouping: config.scenarioCohorts) { $0.experimentID }
      .mapValues { $0.sorted { $0.id < $1.id } }
  }

  func tournament(id: String) -> ProductTournament? {
    tournamentsByID[id]
  }

  func activeTournament() -> ProductTournament? {
    activeOrDraftingTournaments().first
  }

  func activeOrDraftingTournaments() -> [ProductTournament] {
    config.tournaments
      .filter { $0.status == .active || $0.status == .drafting }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status {
          if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
          return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.status == .active
      }
  }

  func pain(id: String) -> PainHypothesis? {
    painHypothesesByID[id]
  }

  func pain(for tournament: ProductTournament) -> PainHypothesis? {
    pain(id: tournament.painID)
  }

  func segment(id: String) -> UserSegment? {
    segmentsByID[id]
  }

  func workflow(id: String) -> CurrentWorkflow? {
    workflowsByID[id]
  }

  func alternative(id: String) -> Alternative? {
    alternativesByID[id]
  }

  func round(id: String) -> ProductTournamentRound? {
    roundsByID[id]
  }

  func rounds(in tournament: ProductTournament) -> [ProductTournamentRound] {
    orderedMembers(
      ids: tournament.roundIDs,
      indexed: roundsByID,
      fallback: roundsByTournamentID[tournament.id] ?? []
    )
    .sorted { lhs, rhs in
      if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
      return lhs.ordinal < rhs.ordinal
    }
  }

  func activeRound(in tournament: ProductTournament) -> ProductTournamentRound? {
    if let currentRoundID = tournament.currentRoundID,
      let round = round(id: currentRoundID),
      round.tournamentID == tournament.id,
      round.status == .active
    {
      return round
    }
    return rounds(in: tournament).first { $0.status == .active }
  }

  func contender(id: String) -> ProductTournamentContender? {
    contendersByID[id]
  }

  func contenders(in tournament: ProductTournament) -> [ProductTournamentContender] {
    orderedMembers(
      ids: tournament.contenderIDs,
      indexed: contendersByID,
      fallback: contendersByTournamentID[tournament.id] ?? []
    )
  }

  func contenders(in round: ProductTournamentRound) -> [ProductTournamentContender] {
    orderedMembers(
      ids: round.contenderIDs,
      indexed: contendersByID,
      fallback: (contendersByTournamentID[round.tournamentID] ?? []).filter {
        $0.tournamentID == round.tournamentID
      }
    )
  }

  func plan(id: String) -> ProductTournamentContenderPlan? {
    contenderPlansByID[id]
  }

  func plan(for contender: ProductTournamentContender) -> ProductTournamentContenderPlan? {
    plan(id: contender.contenderPlanID)
  }

  func experiment(id: String) -> ProductTournamentExperiment? {
    experimentsByID[id]
  }

  func experiment(for contender: ProductTournamentContender) -> ProductTournamentExperiment? {
    contender.experimentID.flatMap { experiment(id: $0) }
  }

  func contenderNode(for contender: ProductTournamentContender) -> TournamentContenderNode? {
    guard let plan = plan(for: contender) else { return nil }
    return TournamentContenderNode(
      contender: contender,
      plan: plan,
      experiment: experiment(for: contender)
    )
  }

  func contenderNodes(in tournament: ProductTournament) -> [TournamentContenderNode] {
    contenders(in: tournament).compactMap(contenderNode)
  }

  func scenario(id: String) -> ProductScenario? {
    scenariosByID[id]
  }

  func scenarios(for experiment: ProductTournamentExperiment) -> [ProductScenario] {
    scenariosByExperimentID[experiment.id] ?? []
  }

  func cohort(id: String) -> ProductScenarioCohort? {
    cohortsByID[id]
  }

  func cohorts(for experiment: ProductTournamentExperiment) -> [ProductScenarioCohort] {
    orderedMembers(
      ids: experiment.scenarioCohortIDs,
      indexed: cohortsByID,
      fallback: cohortsByExperimentID[experiment.id] ?? []
    )
  }

  private func orderedMembers<T>(
    ids: [String],
    indexed: [String: T],
    fallback: [T]
  ) -> [T] {
    ids.isEmpty ? fallback : ids.compactMap { indexed[$0] }
  }

  private static func stableContenderOrder(
    _ contenders: [ProductTournamentContender]
  ) -> [ProductTournamentContender] {
    contenders.sorted { lhs, rhs in
      if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
      return lhs.createdAt < rhs.createdAt
    }
  }

  private static func stableRoundOrder(
    _ rounds: [ProductTournamentRound]
  ) -> [ProductTournamentRound] {
    rounds.sorted { lhs, rhs in
      if lhs.ordinal == rhs.ordinal { return lhs.id < rhs.id }
      return lhs.ordinal < rhs.ordinal
    }
  }

  private static func indexed<Value: Identifiable>(_ values: [Value]) -> [String: Value]
  where Value.ID == String {
    values.reduce(into: [:]) { result, value in
      if result[value.id] == nil {
        result[value.id] = value
      }
    }
  }
}
