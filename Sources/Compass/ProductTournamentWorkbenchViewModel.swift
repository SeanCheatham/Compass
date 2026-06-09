import Combine
import Foundation

struct ProductTournamentWorkbenchState {
  var tournamentsForBoard: [ProductTournament]
  var contendersForBoard: [ProductTournamentContender]
  var tournamentRoundsForBoard: [ProductTournamentRound]
  var experimentsForBoard: [ProductTournamentExperiment]
  var activeTournament: ProductTournament?
  var activePlanRound: ProductTournamentRound?
  var activeCoreTechnologyRound: ProductTournamentRound?
  var activeProductImplementationRound: ProductTournamentRound?
  var automationProofTargets: [TournamentAutomationProofTarget]
  var proofScoreboard: [TournamentAutomationProofTargetScoreboardItem]
  var automationStep: TournamentAutomationStep?
  var automationCyclePlan: TournamentAutomationCyclePlan
  var latestCycleFacts: TournamentAutomationCycleWorkbenchFacts?

  static func build(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    maxAutomationSteps: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> ProductTournamentWorkbenchState {
    let readModel = ProductTournamentReadModel(config: config)
    let activeTournament = readModel.activeTournament()
    let activeRound = activeTournament.flatMap { readModel.activeRound(in: $0) }
    let proofScoreboard = TournamentAutomationProofTargetScoreboard.items(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    let automationStep = TournamentAutomationPlanner.nextStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    return ProductTournamentWorkbenchState(
      tournamentsForBoard: config.tournaments.sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return tournamentStatusRank(lhs.status) < tournamentStatusRank(rhs.status)
      },
      contendersForBoard: config.tournamentContenders.sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return contenderStatusRank(lhs.status) < contenderStatusRank(rhs.status)
      },
      tournamentRoundsForBoard: config.tournamentRounds.sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.title < rhs.title }
        return lhs.ordinal < rhs.ordinal
      },
      experimentsForBoard: TournamentAutomationExperimentRanker.rankedExperiments(
        config: config,
        evidenceIndex: evidenceIndex
      ),
      activeTournament: activeTournament,
      activePlanRound: activeRoundForKind(
        .productPlans,
        requiringStatus: nil,
        activeRound: activeRound,
        activeTournament: activeTournament,
        readModel: readModel
      ) { $0.status != .completed },
      activeCoreTechnologyRound: activeRoundForKind(
        .coreTechnology,
        requiringStatus: .active,
        activeRound: activeRound,
        activeTournament: activeTournament,
        readModel: readModel
      ),
      activeProductImplementationRound: activeRoundForKind(
        .productImplementation,
        requiringStatus: .active,
        activeRound: activeRound,
        activeTournament: activeTournament,
        readModel: readModel
      ),
      automationProofTargets: TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex,
        isPersonaModelAvailable: isPersonaModelAvailable
      ),
      proofScoreboard: proofScoreboard,
      automationStep: automationStep,
      automationCyclePlan: TournamentAutomationPlanner.cyclePlan(
        config: config,
        evidenceIndex: evidenceIndex,
        maxSteps: maxAutomationSteps,
        isPersonaModelAvailable: isPersonaModelAvailable
      ),
      latestCycleFacts: TournamentAutomationCycleWorkbenchFacts.latest(
        config: config,
        evidenceIndex: evidenceIndex,
        currentStep: automationStep
      )
    )
  }

  private static func activeRoundForKind(
    _ kind: ProductTournamentRoundKind,
    requiringStatus status: ProductTournamentRoundStatus?,
    activeRound: ProductTournamentRound?,
    activeTournament: ProductTournament?,
    readModel: ProductTournamentReadModel,
    additionalFilter: (ProductTournamentRound) -> Bool = { _ in true }
  ) -> ProductTournamentRound? {
    if let activeRound,
      activeRound.kind == kind,
      status == nil || activeRound.status == status,
      additionalFilter(activeRound)
    {
      return activeRound
    }
    guard let activeTournament else { return nil }
    return readModel.rounds(in: activeTournament)
      .filter { round in
        round.kind == kind
          && (status == nil || round.status == status)
          && additionalFilter(round)
      }
      .first
  }

  private static func tournamentStatusRank(_ status: ProductTournamentStatus) -> Int {
    switch status {
    case .active: return 0
    case .drafting: return 1
    case .completed: return 2
    case .archived: return 3
    }
  }

  private static func contenderStatusRank(_ status: ProductTournamentContenderStatus) -> Int {
    switch status {
    case .winner: return 0
    case .narrowed: return 1
    case .competing: return 2
    case .needsRevision: return 3
    case .eliminated: return 4
    case .archived: return 5
    }
  }
}

@MainActor
final class ProductTournamentWorkbenchViewModel: ObservableObject {
  @Published private(set) var state: ProductTournamentWorkbenchState

  init(
    config: ProductTournamentConfig = .empty,
    evidenceIndex: ProductTournamentEvidenceIndex = .empty
  ) {
    self.state = ProductTournamentWorkbenchState.build(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  func reload(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) {
    state = ProductTournamentWorkbenchState.build(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  func saveScenarioDraft(
    _ draft: ProductScenarioDraft,
    in workspace: CompassWorkspace
  ) async throws -> ProductTournamentCommandResult {
    try await ProductTournamentEngine(workspace: workspace).apply(.saveScenarioDraft(draft))
  }

  func applyTransition(
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    in workspace: CompassWorkspace
  ) async throws -> ProductTournamentCommandResult {
    try await ProductTournamentEngine(workspace: workspace).apply(
      .applyRoundTransition(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID
      )
    )
  }
}
