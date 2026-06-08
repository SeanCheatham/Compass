import Foundation

enum ProductTournamentCommand: Equatable, Sendable {
  case recordPlanEvaluation(ProductTournamentPlanEvaluationRecord)
  case applyRoundTransition(tournamentID: String?, roundID: String?, contenderID: String?)
  case prepareImplementationTrack(experimentID: String)
  case saveScenarioDraft(ProductScenarioDraft)
  case runScenario(experimentID: String, scenarioID: String)
  case applyRollout(experimentID: String, action: ProductTournamentExperimentRolloutAction)
  case recordAutomationAudit(TournamentAutomationCycleAudit)
}

struct ProductTournamentCommandResult: Equatable, Sendable {
  var config: ProductTournamentConfig
  var evidenceIndex: ProductTournamentEvidenceIndex?
  var message: String
  var changedEntityIDs: [String]
}

struct ProductTournamentEngine {
  var workspace: CompassWorkspace

  func apply(
    _ command: ProductTournamentCommand,
    now: Date = Date()
  ) async throws -> ProductTournamentCommandResult {
    switch command {
    case .recordPlanEvaluation(let record):
      let stored = try workspace.writeProductTournamentPlanEvaluationRecord(record)
      let index = workspace.readProductTournamentEvidenceIndex()
      return ProductTournamentCommandResult(
        config: try workspace.readProductTournamentConfig(),
        evidenceIndex: index,
        message: "Recorded tournament plan evaluation \(stored.id).",
        changedEntityIDs: [stored.id]
      )

    case .applyRoundTransition(let tournamentID, let roundID, let contenderID):
      return try applyRoundTransition(
        tournamentID: tournamentID,
        roundID: roundID,
        contenderID: contenderID,
        now: now
      )

    case .prepareImplementationTrack(let experimentID):
      throw ProductTournamentEngineError.unsupportedCommand(
        "prepareImplementationTrack(\(experimentID)) needs an automation step context."
      )

    case .saveScenarioDraft(let draft):
      let next = try workspace.saveProductScenarioDraft(draft)
      return ProductTournamentCommandResult(
        config: next,
        evidenceIndex: workspace.readProductTournamentEvidenceIndex(),
        message: "Saved product tournament scenario \(draft.title).",
        changedEntityIDs: [draft.id ?? draft.title]
      )

    case .runScenario(let experimentID, let scenarioID):
      throw ProductTournamentEngineError.unsupportedCommand(
        "runScenario(\(experimentID), \(scenarioID)) needs a project runtime context."
      )

    case .applyRollout(let experimentID, let action):
      let config = try workspace.readProductTournamentConfig()
      let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
      let next = try ProductTournamentExperimentRolloutWorkflow.applying(
        action,
        experimentID: experimentID,
        to: config,
        evidenceIndex: evidenceIndex,
        now: now,
        decidedBy: "Product Tournament Engine"
      )
      try workspace.writeProductTournamentConfig(next)
      return ProductTournamentCommandResult(
        config: next,
        evidenceIndex: evidenceIndex,
        message: "\(action.rawValue) recorded for tournament experiment \(experimentID).",
        changedEntityIDs: [experimentID]
      )

    case .recordAutomationAudit(let audit):
      let config = try workspace.readProductTournamentConfig()
      let next = config.recordingTournamentAutomationCycleAudit(audit)
      try workspace.writeProductTournamentConfig(next)
      return ProductTournamentCommandResult(
        config: next,
        evidenceIndex: workspace.readProductTournamentEvidenceIndex(),
        message: audit.userMessage,
        changedEntityIDs: [audit.id] + audit.experimentIDs
      )
    }
  }

  private func applyRoundTransition(
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    now: Date
  ) throws -> ProductTournamentCommandResult {
    let config = try workspace.readProductTournamentConfig()
    let evidenceIndex = workspace.readProductTournamentEvidenceIndex()
    let readModel = ProductTournamentReadModel(config: config)
    guard let round = selectedRound(
      tournamentID: tournamentID,
      roundID: roundID,
      readModel: readModel
    ) else {
      throw ProductTournamentEngineError.missingRound(roundID ?? "active")
    }

    switch round.kind {
    case .productPlans:
      let proposal = try selectedPlanTransitionProposal(
        tournamentID: tournamentID,
        roundID: round.id,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentPlanTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      try workspace.writeProductTournamentConfig(outcome.config)
      return ProductTournamentCommandResult(
        config: outcome.config,
        evidenceIndex: evidenceIndex,
        message: outcome.userMessage,
        changedEntityIDs: outcome.affectedContenderIDs + [outcome.fromRoundID]
          + [outcome.toRoundID].compactMap { $0 }
      )

    case .coreTechnology:
      let proposal = try selectedRoundEvidenceTransitionProposal(
        tournamentID: tournamentID,
        roundID: round.id,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentRoundEvidenceTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      try workspace.writeProductTournamentConfig(outcome.config)
      return ProductTournamentCommandResult(
        config: outcome.config,
        evidenceIndex: evidenceIndex,
        message: outcome.userMessage,
        changedEntityIDs: outcome.affectedContenderIDs + [outcome.fromRoundID]
          + [outcome.toRoundID].compactMap { $0 }
      )

    case .productImplementation:
      let proposal = try selectedProductImplementationTransitionProposal(
        tournamentID: tournamentID,
        roundID: round.id,
        contenderID: contenderID,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let outcome = try ProductTournamentProductImplementationEvidenceTransitioner.apply(
        proposal: proposal,
        to: config,
        now: now
      )
      try workspace.writeProductTournamentConfig(outcome.config)
      return ProductTournamentCommandResult(
        config: outcome.config,
        evidenceIndex: evidenceIndex,
        message: outcome.userMessage,
        changedEntityIDs: outcome.affectedContenderIDs + [outcome.fromRoundID]
          + [outcome.toRoundID].compactMap { $0 }
      )
    }
  }

  private func selectedRound(
    tournamentID: String?,
    roundID: String?,
    readModel: ProductTournamentReadModel
  ) -> ProductTournamentRound? {
    if let roundID {
      return readModel.round(id: roundID)
    }
    guard let tournament = tournamentID.flatMap(readModel.tournament) ?? readModel.activeTournament()
    else { return nil }
    return readModel.activeRound(in: tournament)
  }

  private func selectedPlanTransitionProposal(
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentPlanTransitionProposal {
    let proposal = ProductTournamentPlanTransitioner.proposals(
      tournamentID: tournamentID,
      roundID: roundID,
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first { proposal in
      proposal.isActionable && (contenderID == nil || proposal.contenderID == contenderID)
    }
    guard let proposal else {
      throw ProductTournamentEngineError.missingActionableTransition(contenderID ?? "any")
    }
    return proposal
  }

  private func selectedRoundEvidenceTransitionProposal(
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentRoundEvidenceTransitionProposal {
    let proposal = ProductTournamentRoundEvidenceTransitioner.proposals(
      tournamentID: tournamentID,
      roundID: roundID,
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first { proposal in
      proposal.isActionable && (contenderID == nil || proposal.contenderID == contenderID)
    }
    guard let proposal else {
      throw ProductTournamentEngineError.missingActionableTransition(contenderID ?? "any")
    }
    return proposal
  }

  private func selectedProductImplementationTransitionProposal(
    tournamentID: String?,
    roundID: String?,
    contenderID: String?,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) throws -> ProductTournamentProductImplementationEvidenceTransitionProposal {
    let proposal = ProductTournamentProductImplementationEvidenceTransitioner.proposals(
      tournamentID: tournamentID,
      roundID: roundID,
      config: config,
      evidenceIndex: evidenceIndex
    )
    .first { proposal in
      proposal.isActionable && (contenderID == nil || proposal.contenderID == contenderID)
    }
    guard let proposal else {
      throw ProductTournamentEngineError.missingActionableTransition(contenderID ?? "any")
    }
    return proposal
  }
}

enum ProductTournamentEngineError: LocalizedError, Equatable {
  case missingRound(String)
  case missingActionableTransition(String)
  case unsupportedCommand(String)

  var errorDescription: String? {
    switch self {
    case .missingRound(let id):
      return "No tournament round was available for command scope \(id)."
    case .missingActionableTransition(let contenderID):
      return "No actionable tournament transition was available for contender \(contenderID)."
    case .unsupportedCommand(let detail):
      return "Tournament command is not supported yet: \(detail)"
    }
  }
}
