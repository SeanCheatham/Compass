import Foundation
import Testing

@testable import Compass

struct ProductTournamentArchitectureTests {
  @Test func simplifiedStateConvertsSeededConfigAndValidates() throws {
    let state = ProductTournamentStateV2(converting: seededConfig())

    try state.validate()
    try #require(state.pain?.rawPain.contains("weekly reporting") == true)
    try #require(state.contenders.count == 2)
    try #require(
      state.rounds.map(\.kind)
        == [.marketCompilation, .productPlans, .coreTechnology, .productImplementation])
    try #require(state.rounds.first?.lifecycle == .active)
    try #require(state.activeRoundID == state.rounds.first?.id)
    try #require(state.contenders.allSatisfy { $0.implementationTrack != nil })
  }

  @Test func simplifiedStateAppliesRoundOneAdvanceWithoutOldArrays() throws {
    let state = ProductTournamentStateV2(converting: roundOneActiveConfig())
    let contenderID = try #require(state.contenders.first?.id)

    let advanced = try state.applyingRoundOneTransition(
      contenderID: contenderID,
      recommendation: .advanceToFeasibility,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let planRound = try #require(advanced.rounds.first { $0.kind == .productPlans })
    let feasibilityRound = try #require(advanced.rounds.first { $0.kind == .coreTechnology })
    let contender = try #require(advanced.contenders.first { $0.id == contenderID })

    try #require(planRound.lifecycle == .completed)
    try #require(feasibilityRound.lifecycle == .active)
    try #require(feasibilityRound.contenderIDs == [contenderID])
    try #require(advanced.activeRoundID == feasibilityRound.id)
    try #require(contender.lifecycle == .narrowed)
  }

  @Test func simplifiedStateValidatorReportsDrift() throws {
    var state = ProductTournamentStateV2(converting: seededConfig())
    state.rounds[0].contenderIDs.append("missing-contender")
    state.contenders[0].lifecycle = .winner

    let errors = state.validationErrors()

    try #require(
      errors.contains(
        .unknownRoundContender(
          roundID: state.rounds[0].id,
          contenderID: "missing-contender"
        ))
    )
    try #require(errors.contains(.winnerWithoutOutcome(state.contenders[0].id)))
  }

  @Test func tournamentWorkspaceStoreRoundTripsStateAndPlanEvidence() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let store = workspace.tournamentStore
    let config = seededConfig()
    let state = ProductTournamentStateV2(converting: config)
    let record = try strongPlanEvaluationRecords(config: config).first
      .unwrap(or: TestHelperError.message("missing plan evaluation record"))

    try #require(try store.readState() == .empty)
    try store.writeState(state)
    try #require(try store.readState() == state)

    _ = try store.writePlanEvaluationRecord(record, now: Date(timeIntervalSince1970: 10))
    let index = try store.readEvidenceIndex()
    try #require(index.planEvaluationSummaries.map(\.evaluationID) == [record.id])

    var revisedState = state
    revisedState.activeRoundID = state.rounds.last?.id
    try store.writeState(revisedState)
    try #require(try store.readEvidenceIndex() == index)
  }

  @Test func tournamentWorkspaceStoreMalformedStateThrowsClearError() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let store = workspace.tournamentStore

    try FileManager.default.createDirectory(
      at: store.tournamentURL, withIntermediateDirectories: true)
    try "{".write(to: store.stateURL, atomically: true, encoding: .utf8)

    #expect(throws: TournamentWorkspaceStoreError.self) {
      _ = try store.readState()
    }
  }

  @Test func commandEngineAppliesRoundTransitionAndPersistsConfig() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let config = seededConfig()
    try workspace.writeProductTournamentConfig(config)
    for record in try strongPlanEvaluationRecords(config: config) {
      _ = try workspace.writeProductTournamentPlanEvaluationRecord(record)
    }

    let tournament = try #require(config.tournaments.first)
    let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
    let contender = try #require(config.tournamentContenders.first)
    let result = try await ProductTournamentEngine(workspace: workspace).apply(
      .applyRoundTransition(
        tournamentID: tournament.id,
        roundID: planRound.id,
        contenderID: contender.id
      ),
      now: Date(timeIntervalSince1970: 2_000)
    )
    let stored = try workspace.readProductTournamentConfig()
    let feasibilityRound = try #require(
      stored.tournamentRounds.first { $0.kind == .coreTechnology })

    try #require(stored == result.config)
    try #require(result.message.contains("Advanced"))
    try #require(stored.tournaments.first?.currentRoundID == feasibilityRound.id)
    try #require(feasibilityRound.contenderIDs == [contender.id])
    try #require(result.changedEntityIDs.contains(contender.id))
  }

  @Test func promptDigestKeepsTournamentContextAsPrimaryPlanningInput() throws {
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: seededConfig(),
      evidenceIndex: .empty
    )

    try #require(digest.contains("Product tournament context"))
    try #require(digest.contains("Product tournaments:"))
    try #require(digest.contains("Contender"))
    try #require(!digest.localizedCaseInsensitiveContains("open question"))
    try #require(!digest.localizedCaseInsensitiveContains("draft queue"))
  }
}

private func roundOneActiveConfig() -> ProductTournamentConfig {
  var config = seededConfig()
  guard
    let tournamentIndex = config.tournaments.indices.first,
    let marketRoundIndex = config.tournamentRounds.firstIndex(where: { $0.kind == .marketCompilation }),
    let planRoundIndex = config.tournamentRounds.firstIndex(where: { $0.kind == .productPlans })
  else { return config }
  config.tournaments[tournamentIndex].currentRoundID = config.tournamentRounds[planRoundIndex].id
  config.tournamentRounds[marketRoundIndex].status = .completed
  config.tournamentRounds[planRoundIndex].status = .active
  return config
}

private func seededConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func strongPlanEvaluationRecords(
  config: ProductTournamentConfig
) throws -> [ProductTournamentPlanEvaluationRecord] {
  let tournament = try #require(config.tournaments.first)
  let round = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
  let contender = try #require(config.tournamentContenders.first)
  let contenderPlan = try #require(
    config.contenderPlans.first { $0.id == contender.contenderPlanID })
  return config.userSegments.prefix(2).enumerated().map { index, segment in
    ProductTournamentPlanEvaluationRecord(
      id: "\(contender.id)-engine-\(index)",
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      contenderPlanID: contender.contenderPlanID,
      experimentID: contender.experimentID,
      painID: contenderPlan.painID,
      personaID: segment.id,
      personaName: segment.name,
      currentWorkflowID: segment.currentWorkflowIDs.first,
      alternativeID: segment.alternativeIDs.first,
      startedAt: Double(index),
      endedAt: Double(index + 1),
      scores: ProductTournamentEvidenceScores(
        painRecognition: 5,
        workflowImprovement: 5,
        alternativeAdvantage: 5,
        switchingReadiness: 5,
        continuedUsePull: 5,
        willingnessToPay: 4
      ),
      willingnessToPayScore: 4,
      estimatedMonthlyPriceCents: 9900,
      commercialProofSummary: "Buyer and operator both see clear ROI.",
      currentAlternativeComparison: "The plan clearly beats the current workaround.",
      verdict: .strongPull,
      summary: "The plan has strong pull.",
      rationale: ["Architecture test record."]
    )
  }
}

extension Optional {
  fileprivate func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
    guard let value = self else { throw error() }
    return value
  }
}
