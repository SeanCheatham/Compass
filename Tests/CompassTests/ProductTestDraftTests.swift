import Foundation
import Testing

@testable import Compass

struct ProductTestDraftTests {
  @Test func readyDraftSummarizesProductQuestionAndDecision() throws {
    var config = seededTestConfig()
    config.tournamentExperiments[0].currentSha = "ready-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = config.scenarios.first { $0.experimentID == experiment.id }!
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )
    let input = ProductTestDraftInput(
      id: scenario.id,
      experimentID: experiment.id,
      cohortID: config.scenarioCohorts[0].id,
      cohortTitle: config.scenarioCohorts[0].title,
      cohortEnabled: true,
      segmentID: scenario.segmentID,
      currentWorkflowID: scenario.currentWorkflowID,
      alternativeID: scenario.alternativeID,
      title: "Will the operator trust the workflow proof?",
      task: "Complete the weekly report workflow and compare it to the spreadsheet.",
      successSignal: "The operator can explain the saved step and trust the result.",
      targetCommitSha: "ready-sha",
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true
    )

    let draft = ProductTestDraft.build(
      input: input,
      config: config,
      nextMove: cockpit.nextMove,
      contractAvailable: true,
      blockedReason: nil
    )

    try #require(draft.productQuestion == "Will the operator trust the workflow proof?")
    try #require(draft.targetUser.contains("Hands-on operator"))
    try #require(draft.currentAlternative == "Manual workaround")
    try #require(draft.expectedDecision == "Advance to feasibility, revise the plan, or eliminate")
    try #require(draft.canRun)
    try #require(draft.validationItems.allSatisfy { $0.state == .ready })
    try #require(draft.previewLines.joined(separator: "\n").contains("It helps decide"))
    try #require(draft.auditReferences.contains { $0.kind == .scenario && $0.value == scenario.id })
    try #require(draft.auditReferences.contains { $0.kind == .commit && $0.value == "ready-sha" })
  }

  @Test func incompleteDraftReportsMissingProductTestPieces() throws {
    let config = seededTestConfig()
    let experiment = config.tournamentExperiments[0]
    let input = ProductTestDraftInput(
      id: nil,
      experimentID: experiment.id,
      cohortID: nil,
      cohortTitle: "",
      cohortEnabled: true,
      segmentID: "missing-segment",
      currentWorkflowID: "missing-workflow",
      alternativeID: nil,
      title: "",
      task: "Try it",
      successSignal: "",
      targetCommitSha: nil,
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true
    )

    let draft = ProductTestDraft.build(
      input: input,
      config: config,
      nextMove: nil,
      contractAvailable: false,
      blockedReason: nil
    )

    try #require(!draft.canRun)
    try #require(draft.productQuestion == "Product test question not selected")
    try #require(draft.validationItems.first { $0.title == "Target user" }?.state == .missing)
    try #require(draft.validationItems.first { $0.title == "Baseline workflow" }?.state == .missing)
    try #require(draft.validationItems.first { $0.title == "Product action" }?.state == .missing)
    try #require(draft.validationItems.first { $0.title == "Success signal" }?.state == .missing)
    try #require(draft.validationItems.first { $0.title == "Evidence target" }?.state == .missing)
    try #require(draft.validationItems.first { $0.title == "Commit and contract" }?.state == .missing)
  }

  @Test func blockedRoundTwoDraftShowsProductBlocker() throws {
    var config = seededTestConfig()
    config.tournamentExperiments[0].currentSha = "blocked-sha"
    let experiment = config.tournamentExperiments[0]
    let scenario = config.scenarios.first { $0.experimentID == experiment.id }!
    let input = ProductTestDraftInput(
      id: scenario.id,
      experimentID: experiment.id,
      cohortID: config.scenarioCohorts[0].id,
      cohortTitle: config.scenarioCohorts[0].title,
      cohortEnabled: true,
      segmentID: scenario.segmentID,
      currentWorkflowID: scenario.currentWorkflowID,
      alternativeID: scenario.alternativeID,
      title: scenario.title,
      task: scenario.task,
      successSignal: scenario.successSignal,
      targetCommitSha: "blocked-sha",
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true
    )

    let draft = ProductTestDraft.build(
      input: input,
      config: config,
      nextMove: ProductDecisionCockpit.build(
        config: config,
        evidenceIndex: .empty,
        isPersonaModelAvailable: false
      ).nextMove,
      contractAvailable: true,
      blockedReason: "Core-technology proof is locked to another contender."
    )

    let commitValidation = try #require(
      draft.validationItems.first { $0.title == "Commit and contract" }
    )
    try #require(!draft.canRun)
    try #require(commitValidation.state == .blocked)
    try #require(commitValidation.detail == "Core-technology proof is locked to another contender.")
  }
}

private func seededTestConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context.",
    now: Date(timeIntervalSince1970: 10)
  )
}
