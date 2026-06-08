import AppKit
import SwiftUI

struct ProductTournamentWorkbenchTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedExperimentID: String?
  @State private var selectedRunID: String?
  @State private var selectedRecord: ProductTournamentEvidenceRecord?
  @State private var recordError: String?
  @State private var selectedProofScoreboardRowID: String?
  @State private var selectedProofScoreboardGroupAnchorRowID: String?
  @State private var selectedPlanEvaluationID: String?
  @State private var selectedPlanEvaluationRecord: ProductTournamentPlanEvaluationRecord?
  @State private var planEvaluationRecordError: String?
  @State private var gitPreview: ProductTournamentExperimentGitRolloutPreview?
  @State private var gitPreviewError: String?
  @State private var isLoadingGitPreview = false
  @State private var selectedScenarioID: String?
  @State private var scenarioTitle = ""
  @State private var scenarioCohortID = ""
  @State private var scenarioCohortTitle = ""
  @State private var scenarioCohortEnabled = true
  @State private var scenarioTask = ""
  @State private var scenarioSuccessSignal = ""
  @State private var scenarioSegmentID = ""
  @State private var scenarioWorkflowID = ""
  @State private var scenarioAlternativeID = ""
  @State private var scenarioTargetCommit = ""
  @State private var scenarioMaxTurns = 8
  @State private var scenarioTimeoutSeconds = 120.0
  @State private var scenarioEnabled = true
  @State private var isSavingScenario = false
  @State private var isRunningScenario = false
  @State private var isRunningPlanEvaluation = false
  @State private var runningPlanEvaluationContenderID: String?
  @State private var isApplyingPlanTransition = false
  @State private var isApplyingRoundEvidenceTransition = false
  @State private var isApplyingProductImplementationEvidenceTransition = false
  @State private var isRunningTournamentStep = false
  @State private var isRunningTournamentAutomationCycle = false
  @State private var pausePortfolioAfterCurrentBatch = false
  @State private var cancelledPortfolioLaneID: String?
  @State private var evidenceConcurrencyLimit = 2
  @State private var personaLLMConcurrencyLimit = 1
  @State private var simulationConcurrencyLimit = 2
  @State private var scenarioRunMessage: String?
  @State private var planEvaluationMessage: String?
  @State private var planTransitionMessage: String?
  @State private var roundEvidenceTransitionMessage: String?
  @State private var productImplementationEvidenceTransitionMessage: String?
  @State private var contractAvailable: Bool?

  private var config: ProductTournamentConfig { project.productTournamentConfig }
  private var evidenceIndex: ProductTournamentEvidenceIndex {
    project.productTournamentEvidenceIndex
  }
  private var workbenchState: ProductTournamentWorkbenchState {
    ProductTournamentWorkbenchState.build(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
  }

  private var productDecisionCockpit: ProductDecisionCockpit {
    ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
  }

  private var tournamentsForBoard: [ProductTournament] {
    workbenchState.tournamentsForBoard
  }

  private var contendersForBoard: [ProductTournamentContender] {
    workbenchState.contendersForBoard
  }

  private var tournamentRoundsForBoard: [ProductTournamentRound] {
    workbenchState.tournamentRoundsForBoard
  }

  private var activeTournamentForPlanEvaluation: ProductTournament? {
    workbenchState.activeTournament
  }

  private var activePlanRoundForEvaluation: ProductTournamentRound? {
    workbenchState.activePlanRound
  }

  private var activeTournamentForRoundEvidence: ProductTournament? {
    workbenchState.activeTournament
  }

  private var activeCoreTechnologyRoundForEvidence: ProductTournamentRound? {
    workbenchState.activeCoreTechnologyRound
  }

  private var activeProductImplementationRoundForEvidence: ProductTournamentRound? {
    workbenchState.activeProductImplementationRound
  }

  private var planEvaluationCanRun: Bool {
    activeTournamentForPlanEvaluation != nil
      && activePlanRoundForEvaluation != nil
      && !isRunningPlanEvaluation
      && !isApplyingPlanTransition
      && !isApplyingRoundEvidenceTransition
      && !isApplyingProductImplementationEvidenceTransition
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
  }

  private var personaPlanEvaluationCanRun: Bool {
    planEvaluationCanRun && FoundationModelsAvailability.isAvailable
  }

  private var activePlanRoundContenderIDs: Set<String> {
    guard let tournament = activeTournamentForPlanEvaluation,
      let round = activePlanRoundForEvaluation
    else { return [] }
    return Set(round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs)
  }

  private func planReadiness(
    for contender: ProductTournamentContender
  ) -> ProductTournamentPlanReadiness? {
    evidenceIndex.aggregate.planReadinessByContender.first { $0.contenderID == contender.id }
  }

  private func planEvaluationCanRun(
    for contender: ProductTournamentContender
  ) -> Bool {
    planEvaluationCanRun
      && activePlanRoundContenderIDs.contains(contender.id)
      && planProofIsActionable(for: contender)
      && (contender.status == .competing || contender.status == .narrowed
        || contender.status == .needsRevision)
  }

  private func personaPlanEvaluationCanRun(
    for contender: ProductTournamentContender
  ) -> Bool {
    planEvaluationCanRun(for: contender) && FoundationModelsAvailability.isAvailable
  }

  private func planProofIsActionable(
    for contender: ProductTournamentContender
  ) -> Bool {
    guard let readiness = planReadiness(for: contender) else {
      return activePlanRoundContenderIDs.contains(contender.id)
    }
    return readiness.planProofDebt.hasActionableFocusedProof
  }

  private func planProofActionTitle(
    readiness: ProductTournamentPlanReadiness?
  ) -> String {
    readiness?.planProofDebt.focusedActionTitle ?? "Run Plan Proof"
  }

  private func planProofTargetSummary(
    for contender: ProductTournamentContender,
    readiness: ProductTournamentPlanReadiness?
  ) -> String {
    if let readiness {
      return readiness.nextProofTargetSummary
    }
    if activePlanRoundContenderIDs.contains(contender.id) {
      return "operator and economic-buyer plan evaluations"
    }
    return "not in the active plan round"
  }

  private func planProofTargetHelp(
    for contender: ProductTournamentContender,
    readiness: ProductTournamentPlanReadiness?
  ) -> String {
    let target = planProofTargetSummary(for: contender, readiness: readiness)
    if readiness?.planProofDebt.hasActionableFocusedProof == false {
      return "\(contender.title) is ready for the Round 2 feasibility transition."
    }
    return "Run Round 1 simulated-user proof for \(contender.title): \(target)."
  }

  private var planTransitionProposal: ProductTournamentPlanTransitionProposal? {
    ProductTournamentPlanTransitioner.bestProposal(
      tournamentID: activeTournamentForPlanEvaluation?.id,
      roundID: activePlanRoundForEvaluation?.id,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var planTransitionCanApply: Bool {
    planTransitionProposal != nil
      && !isApplyingPlanTransition
      && !isApplyingRoundEvidenceTransition
      && !isApplyingProductImplementationEvidenceTransition
      && !isRunningPlanEvaluation
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
  }

  private var roundEvidenceTransitionProposal: ProductTournamentRoundEvidenceTransitionProposal? {
    ProductTournamentRoundEvidenceTransitioner.bestProposal(
      tournamentID: activeTournamentForRoundEvidence?.id,
      roundID: activeCoreTechnologyRoundForEvidence?.id,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var roundEvidenceTransitionCanApply: Bool {
    roundEvidenceTransitionProposal != nil
      && !isApplyingRoundEvidenceTransition
      && !isApplyingProductImplementationEvidenceTransition
      && !isApplyingPlanTransition
      && !isRunningPlanEvaluation
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
  }

  private var productImplementationEvidenceTransitionProposal:
    ProductTournamentProductImplementationEvidenceTransitionProposal?
  {
    ProductTournamentProductImplementationEvidenceTransitioner.bestProposal(
      tournamentID: activeTournamentForRoundEvidence?.id,
      roundID: activeProductImplementationRoundForEvidence?.id,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var roundThreeProductImplementationOverview:
    [ProductTournamentRoundThreeProductImplementationOverviewItem]
  {
    ProductTournamentRoundThreeProductImplementationOverview.items(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var roundThreeImplementationRevisionValidationOverview:
    [ProductTournamentRoundThreeImplementationRevisionValidationOverviewItem]
  {
    ProductTournamentRoundThreeImplementationRevisionValidationOverview.items(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var productImplementationEvidenceTransitionCanApply: Bool {
    productImplementationEvidenceTransitionProposal != nil
      && !isApplyingProductImplementationEvidenceTransition
      && !isApplyingRoundEvidenceTransition
      && !isApplyingPlanTransition
      && !isRunningPlanEvaluation
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
  }

  private var feasibilityHandoffs: [ProductTournamentFeasibilityHandoff] {
    ProductTournamentFeasibilityAdvisor.handoffs(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var roundTwoProofOverview: [ProductTournamentRoundTwoProofOverviewItem] {
    ProductTournamentRoundTwoProofOverview.items(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var defaultRoundTwoImplementationTarget: ProductTournamentRoundImplementationTarget? {
    ProductTournamentRoundImplementationTargetResolver.defaultActiveRoundTwoTarget(in: config)
  }

  private var selectedRoundTwoImplementationTarget: ProductTournamentRoundImplementationTarget? {
    guard let experimentID = selectedExperiment?.id ?? selectedExperimentID else {
      return defaultRoundTwoImplementationTarget
    }
    return ProductTournamentRoundImplementationTargetResolver.roundTwoTarget(
      forExperimentInTargetTournament: experimentID,
      in: config
    )
  }

  private var selectedRoundTwoTargetHandoff: ProductTournamentFeasibilityHandoff? {
    guard let target = selectedRoundTwoImplementationTarget else { return nil }
    return feasibilityHandoffs.first {
      $0.tournamentID == target.tournamentID
        && $0.roundID == target.roundID
        && $0.contenderID == target.contenderID
        && $0.experimentID == target.experimentID
    }
  }

  private var selectedExperimentMatchesRoundTwoTarget: Bool {
    guard
      let experimentID = selectedExperiment?.id,
      let target = selectedRoundTwoImplementationTarget
    else { return true }
    return target.experimentID == experimentID
  }

  private var selectedRoundTwoBlockedMessage: String? {
    guard let experimentID = selectedExperiment?.id else { return nil }
    return roundTwoLaunchBlockedMessage(experimentID: experimentID)
  }

  private var selectedExperiment: ProductTournamentExperiment? {
    guard let selectedExperimentID else { return config.tournamentExperiments.first }
    return config.tournamentExperiments.first { $0.id == selectedExperimentID }
      ?? config.tournamentExperiments.first
  }

  private var selectedCockpitContenderID: String? {
    if let contenderID = selectedProofScoreboardRow?.contenderID {
      return contenderID
    }
    guard let selectedExperimentID else { return nil }
    return config.tournamentContenders.first { $0.experimentID == selectedExperimentID }?.id
  }

  private var runsForSelectedExperiment: [ProductTournamentEvidenceSummary] {
    guard let selectedExperiment else { return [] }
    return evidenceIndex.summaries(for: selectedExperiment)
  }

  private var selectedTournamentReadiness: ProductTournamentReadiness? {
    guard let selectedExperiment else { return nil }
    return evidenceIndex.currentTournamentReadiness(for: selectedExperiment)
  }

  private var selectedStaleEvidenceCount: Int {
    guard let selectedExperiment else { return 0 }
    return evidenceIndex.staleSummaryCount(for: selectedExperiment)
  }

  private var selectedTournamentDecisionProposal: ProductTournamentDecisionProposal? {
    guard let experimentID = selectedExperiment?.id else { return nil }
    return ProductTournamentDecisionAdvisor.proposal(
      experimentID: experimentID,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var selectedTournamentNextAction: ProductTournamentNextAction? {
    guard let selectedExperiment else { return nil }
    return ProductTournamentNextActionAdvisor.nextAction(
      for: selectedExperiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var selectedSuggestedCohortReadiness: ProductTournamentCohortRunReadiness? {
    guard let selectedExperiment,
      let action = selectedTournamentNextAction
    else { return nil }
    return ProductTournamentNextActionAdvisor.cohortRunReadiness(
      for: action,
      experiment: selectedExperiment,
      config: config
    )
  }

  private var suggestedCohortCanRun: Bool {
    contractAvailable == true
      && selectedSuggestedCohortReadiness?.canRun == true
      && selectedExperimentMatchesRoundTwoTarget
  }

  private var scenariosForSelectedExperiment: [ProductScenario] {
    guard let experimentID = selectedExperiment?.id else { return [] }
    return config.scenarios
      .filter { $0.experimentID == experimentID }
      .sorted { lhs, rhs in
        if lhs.updatedAt == rhs.updatedAt { return lhs.title < rhs.title }
        return lhs.updatedAt > rhs.updatedAt
      }
  }

  private var cohortsForSelectedExperiment: [ProductScenarioCohort] {
    guard let experimentID = selectedExperiment?.id else { return [] }
    return config.scenarioCohorts
      .filter { $0.experimentID == experimentID }
      .sorted { $0.title < $1.title }
  }

  private var planEvaluationsForBoard: [ProductTournamentPlanEvaluationSummary] {
    let tournamentIDs = Set(config.tournaments.map(\.id))
    return evidenceIndex.planEvaluationSummaries.filter { summary in
      tournamentIDs.isEmpty || tournamentIDs.contains(summary.tournamentID)
    }
  }

  private var roundOnePlanProofDeltaOverview: [TournamentPlanProofDeltaOverviewItem] {
    TournamentPlanProofDeltaOverview.items(config: config, evidenceIndex: evidenceIndex)
  }

  private var experimentsForBoard: [ProductTournamentExperiment] {
    workbenchState.experimentsForBoard
  }

  private var tournamentAutomationProofTargets: [TournamentAutomationProofTarget] {
    workbenchState.automationProofTargets
  }

  private var tournamentAutomationProofTargetScoreboard:
    [TournamentAutomationProofTargetScoreboardItem]
  {
    workbenchState.proofScoreboard
  }

  private var tournamentAutomationRationaleSignals: [TournamentAutomationRationaleSignal] {
    TournamentAutomationRationaleSignalAdvisor.signals(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationTargetedProofOutcomeSignals:
    [TournamentAutomationTargetedProofOutcomeSignal]
  {
    TournamentAutomationTargetedProofOutcomeAdvisor.signals(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationRevisionBriefs: [TournamentAutomationRevisionBrief] {
    TournamentAutomationRevisionBriefAdvisor.briefs(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationEvidenceTensions: [TournamentAutomationEvidenceTension] {
    TournamentAutomationEvidenceTensionAdvisor.tensions(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationDecisionCandidates: [TournamentAutomationDecisionCandidate] {
    TournamentAutomationDecisionCandidateAdvisor.candidates(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationStep: TournamentAutomationStep? {
    workbenchState.automationStep
  }

  private var tournamentAutomationCyclePlan: TournamentAutomationCyclePlan {
    workbenchState.automationCyclePlan
  }

  private var tournamentLaneStates: [ProductTournamentLaneState] {
    workbenchState.laneStates
  }

  private var tournamentPortfolioSchedule: TournamentPortfolioSchedule {
    workbenchState.portfolioSchedule
  }

  private var tournamentJudgingBarriers: [ProductTournamentJudgingBarrier] {
    workbenchState.judgingBarriers
  }

  private var tournamentRolloutFlags: CompassRuntimeFeatureFlags {
    workbenchState.rolloutFlags
  }

  private var tournamentAutomationCanRun: Bool {
    tournamentAutomationStep?.canExecute == true
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
      && tournamentAutomationStepMatchesRoundTwoTarget
  }

  private var tournamentAutomationCycleCanRun: Bool {
    tournamentAutomationCyclePlan.canRun
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
      && tournamentAutomationStepMatchesRoundTwoTarget
  }

  private var tournamentAutomationStepMatchesRoundTwoTarget: Bool {
    guard let step = tournamentAutomationStep else { return true }
    return roundTwoLaunchBlockedMessage(experimentID: step.experimentID) == nil
  }

  private var tournamentAutomationRoundTwoBlockedMessage: String? {
    guard let step = tournamentAutomationStep else { return nil }
    return roundTwoLaunchBlockedMessage(experimentID: step.experimentID)
  }

  private var nextMovePanelDisabledReason: String? {
    if let tournamentAutomationRoundTwoBlockedMessage {
      return ProductPresentationLanguage.disabledReasonLabel(tournamentAutomationRoundTwoBlockedMessage)
        ?? tournamentAutomationRoundTwoBlockedMessage
    }
    return productDecisionCockpit.nextMove?.disabledReason
  }

  private var latestTournamentAutomationCycleFacts: TournamentAutomationCycleWorkbenchFacts? {
    workbenchState.latestCycleFacts
  }

  private var selectedProofScoreboardRow: TournamentAutomationProofTargetScoreboardRow? {
    guard let selectedProofScoreboardRowID else { return nil }
    return
      tournamentAutomationProofTargetScoreboard
      .flatMap(\.rows)
      .first { $0.selectionID == selectedProofScoreboardRowID }
  }

  private var actedRevisionValidationRunContext:
    TournamentAutomationActedRevisionValidationRunContext?
  {
    TournamentAutomationCycleWorkbenchFacts.actedRevisionValidationRunContext(
      config: config,
      evidenceIndex: evidenceIndex,
      currentStep: tournamentAutomationStep,
      scoreboardItems: tournamentAutomationProofTargetScoreboard
    )
  }

  private var selectedProofActedRevisionValidationRunContext:
    TournamentAutomationActedRevisionValidationRunContext?
  {
    guard
      let row = selectedProofScoreboardRow,
      let context = actedRevisionValidationRunContext,
      context.matches(row)
    else { return nil }
    return context
  }

  private var selectedRunActedRevisionValidationRunContext:
    TournamentAutomationActedRevisionValidationRunContext?
  {
    guard
      let record = selectedRecord,
      let context = actedRevisionValidationRunContext,
      context.matches(record)
    else { return nil }
    return context
  }

  private func isSelectedProofScoreboardGroup(
    _ group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> Bool {
    group.containsRow(selectionID: selectedProofScoreboardGroupAnchorRowID)
  }

  private var tournamentAutomationCohortMode: ProductTournamentSimulationMode {
    tournamentAutomationStep?.action.requiredSimulationMode
      ?? TournamentAutomationPlanner.cohortSimulationMode(
        isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
      )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      tournamentBody
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: experimentSelectionTaskID) {
      let preferredExperimentID =
        defaultRoundTwoImplementationTarget?.experimentID ?? config.tournamentExperiments.first?.id
      if selectedExperimentID == nil
        || !config.tournamentExperiments.contains(where: { $0.id == selectedExperimentID })
        || (defaultRoundTwoImplementationTarget != nil
          && selectedExperimentID != defaultRoundTwoImplementationTarget?.experimentID)
      {
        selectedExperimentID = preferredExperimentID
      }
      if selectedRunID == nil
        || !runsForSelectedExperiment.contains(where: { $0.runID == selectedRunID })
      {
        selectedRunID = runsForSelectedExperiment.first?.runID
      }
      loadSelectedRecord()
      loadScenarioDraft()
    }
    .task(id: gitPreviewTaskID) {
      await loadGitPreview()
    }
    .task(id: contractStatusTaskID) {
      await loadContractStatus()
    }
    .task(id: planEvaluationSelectionTaskID) {
      if selectedPlanEvaluationID == nil
        || !planEvaluationsForBoard.contains(where: { $0.evaluationID == selectedPlanEvaluationID })
      {
        selectedPlanEvaluationID = planEvaluationsForBoard.first?.evaluationID
      }
      loadSelectedPlanEvaluationRecord()
    }
    .onChange(of: selectedExperimentID) { _, _ in
      if selectedProofScoreboardRow?.experimentID != selectedExperimentID {
        selectedProofScoreboardRowID = nil
        selectedProofScoreboardGroupAnchorRowID = nil
      }
      if selectedRunID == nil
        || !runsForSelectedExperiment.contains(where: { $0.runID == selectedRunID })
      {
        selectedRunID = runsForSelectedExperiment.first?.runID
      }
      loadSelectedRecord()
      if selectedScenarioID == nil
        || !scenariosForSelectedExperiment.contains(where: { $0.id == selectedScenarioID })
      {
        selectedScenarioID = scenariosForSelectedExperiment.first?.id
      }
      loadScenarioDraft()
      scenarioRunMessage = nil
      Task { await loadGitPreview() }
      Task { await loadContractStatus() }
    }
    .onChange(of: selectedRunID) { _, _ in
      loadSelectedRecord()
    }
    .onChange(of: selectedPlanEvaluationID) { _, _ in
      loadSelectedPlanEvaluationRecord()
    }
    .onChange(of: selectedScenarioID) { _, _ in
      loadScenarioDraft()
      scenarioRunMessage = nil
    }
  }

  private var gitPreviewTaskID: String {
    let experiment = selectedExperiment
    return [
      selectedExperimentID ?? "",
      experiment?.decision.rawValue ?? "",
      experiment?.currentSha ?? "",
      "\(config.decisions.count)",
    ].joined(separator: "|")
  }

  private var experimentSelectionTaskID: String {
    let target = defaultRoundTwoImplementationTarget
    return [
      config.tournamentExperiments.map(\.id).joined(separator: ","),
      target?.tournamentID ?? "",
      target?.roundID ?? "",
      target?.contenderID ?? "",
      target?.experimentID ?? "",
    ].joined(separator: "|")
  }

  private var contractStatusTaskID: String {
    let experiment = selectedExperiment
    return [
      selectedExperimentID ?? "",
      experiment?.currentSha ?? "",
      "\(config.scenarios.count)",
    ].joined(separator: "|")
  }

  private var planEvaluationSelectionTaskID: String {
    planEvaluationsForBoard.map(\.evaluationID).joined(separator: "|")
  }

  @ViewBuilder
  private var tournamentBody: some View {
    if config.isEmpty {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          PlanRunContextSection(project: project)
          ContentUnavailableView(
            "No Product Tournament State",
            systemImage: "trophy",
            description: Text("Enter a user pain or run Discover to seed product tournament state.")
          )
          .frame(maxWidth: .infinity, minHeight: 240)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ProductTournamentMapView(
              cockpit: productDecisionCockpit,
              selectedContenderID: selectedCockpitContenderID,
              onSelectContender: selectCockpitContender
            )
            if let marketCockpit = productDecisionCockpit.marketCockpit {
              MarketDecisionPanel(cockpit: marketCockpit)
            }
            ProductNextMovePanel(
              nextMove: productDecisionCockpit.nextMove,
              latestMovement: productDecisionCockpit.latestMovement,
              canRunPrimaryAction: tournamentAutomationCanRun,
              isRunningPrimaryAction: isRunningTournamentStep,
              primaryDisabledReason: nextMovePanelDisabledReason,
              onRunPrimaryAction: {
                Task { await runTournamentAutomationStep() }
              },
              onViewAudit: selectNextMoveAudit
            )
            ProductEvidenceMatrixView(
              cockpit: productDecisionCockpit,
              selectedContenderID: selectedCockpitContenderID,
              onSelectEvidence: selectCockpitEvidence
            )
            ProductAuditDetailView(
              title: "Cockpit Audit",
              references: productDecisionCockpit.auditReferences
            )
            PlanRunContextSection(project: project)
          }
          .padding(.trailing, 4)
        }
        .frame(minHeight: 360, idealHeight: 440, maxHeight: 620)

        detailedWorkbenchDisclosure
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var detailedWorkbenchDisclosure: some View {
    DisclosureGroup {
      workbenchColumns
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } label: {
      Label("Detailed Workbench", systemImage: ProductIconRole.audit.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(10)
    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
    )
  }

  private var workbenchColumns: some View {
    HStack(alignment: .top, spacing: 12) {
      painMap
        .frame(width: 300)
      Divider()
      contenderAndExperimentBoard
        .frame(minWidth: 360, idealWidth: 460, maxWidth: 560)
      Divider()
      evidenceAndDecisionPane
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var header: some View {
    HStack {
      SectionHeader("Product Tournament", systemImage: "trophy")
      Spacer()
      Button {
        Task { await project.reloadProductTournamentEvidenceIndex() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .help("Reload tournament evidence")
    }
  }

  private var painMap: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        WorkbenchSection("Tournament", systemImage: "trophy") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentsForBoard.isEmpty {
              WorkbenchEmptyLine("No tournament seeded yet.")
            } else {
              ForEach(tournamentsForBoard) { tournament in
                tournamentRow(tournament)
              }
            }
          }
        }

        WorkbenchSection("Pain Map", systemImage: "person.crop.circle.badge.exclamationmark") {
          VStack(alignment: .leading, spacing: 8) {
            if config.painHypotheses.isEmpty {
              WorkbenchEmptyLine("No pain hypotheses yet.")
            } else {
              ForEach(config.painHypotheses) { pain in
                WorkbenchValueBlock(
                  title: pain.title,
                  subtitle: pain.status.rawValue,
                  detail: pain.rawPain
                )
                if !pain.unknowns.isEmpty {
                  WorkbenchFact(
                    label: "Unknowns", value: pain.unknowns.prefix(3).joined(separator: "; "))
                }
              }
            }
          }
        }

        WorkbenchSection("Segments", systemImage: "person.2") {
          VStack(alignment: .leading, spacing: 8) {
            if config.userSegments.isEmpty {
              WorkbenchEmptyLine("No target segments yet.")
            } else {
              ForEach(config.userSegments) { segment in
                WorkbenchValueBlock(
                  title: segment.name,
                  subtitle: segment.role,
                  detail: segment.skepticism
                )
              }
            }
          }
        }

        WorkbenchSection("Current Workflow", systemImage: "arrow.triangle.branch") {
          VStack(alignment: .leading, spacing: 8) {
            if config.currentWorkflows.isEmpty {
              WorkbenchEmptyLine("No current workflow mapped.")
            } else {
              ForEach(config.currentWorkflows) { workflow in
                WorkbenchValueBlock(
                  title: workflow.title,
                  subtitle: workflow.estimatedCost,
                  detail: workflow.failureModes.prefix(2).joined(separator: "; ")
                )
              }
            }
          }
        }

        WorkbenchSection("Alternatives", systemImage: "arrow.left.arrow.right") {
          VStack(alignment: .leading, spacing: 8) {
            if config.alternatives.isEmpty {
              WorkbenchEmptyLine("No current alternatives captured.")
            } else {
              ForEach(config.alternatives) { alternative in
                WorkbenchValueBlock(
                  title: alternative.title,
                  subtitle: alternative.kind.rawValue,
                  detail: alternative.switchingCost
                )
              }
            }
          }
        }
      }
      .padding(.trailing, 4)
    }
  }

  private func tournamentRow(_ tournament: ProductTournament) -> some View {
    let currentRound = tournament.currentRoundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID }
    }
    let currentRoundLabel =
      currentRound.map {
        "Round \($0.ordinal): \($0.kind.title)"
      } ?? "No active round"
    return VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(tournament.title)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
        Spacer()
        WorkbenchStatusPill(text: tournament.status.rawValue)
      }
      WorkbenchFact(label: "Current", value: currentRoundLabel)
      WorkbenchFact(label: "Contenders", value: "\(tournament.contenderIDs.count)")
      WorkbenchFact(label: "Rounds", value: "\(tournament.roundIDs.count)")
      Text(tournament.premise)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  private var contenderAndExperimentBoard: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        WorkbenchSection("Contender Plans", systemImage: "rectangle.3.group") {
          VStack(alignment: .leading, spacing: 8) {
            if contendersForBoard.isEmpty {
              WorkbenchEmptyLine("No product contenders yet.")
            } else {
              ForEach(contendersForBoard) { contender in
                contenderRow(contender)
              }
            }
          }
        }

        if !roundOnePlanProofDeltaOverview.isEmpty {
          WorkbenchSection("Round 1 Proof Deltas", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(roundOnePlanProofDeltaOverview) { item in
                planProofDeltaOverviewRow(item)
              }
            }
          }
        }

        WorkbenchSection("Rounds", systemImage: "list.number") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Button {
                Task { await runPlanEvaluationRound(contenderID: nil, mode: .modelFree) }
              } label: {
                Label(
                  isRunningPlanEvaluation ? "Running Round 1" : "Run Round 1",
                  systemImage: "person.2.wave.2"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!planEvaluationCanRun)
              .help(
                "Run model-free simulated-user evaluation for the plan-only round. Missing buyer/sponsor proof is targeted automatically."
              )

              Button {
                Task { await runPlanEvaluationRound(contenderID: nil, mode: .personaModel) }
              } label: {
                Label(
                  isRunningPlanEvaluation ? "Running Persona" : "Persona Round 1",
                  systemImage: "sparkles"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!personaPlanEvaluationCanRun)
              .help(
                FoundationModelsAvailability.isAvailable
                  ? "Run Foundation Models persona evaluation for the plan-only round."
                  : "Foundation Models is unavailable for persona-model plan evaluation."
              )

              Button {
                Task { await applyPlanTransition() }
              } label: {
                Label(
                  isApplyingPlanTransition ? "Applying" : "Apply Round 1",
                  systemImage: "arrow.turn.down.right"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!planTransitionCanApply)
              .help(planTransitionProposal?.detail ?? "No actionable Round 1 recommendation yet.")

              if let planEvaluationMessage {
                Text(planEvaluationMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              if let planTransitionMessage {
                Text(planTransitionMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            if tournamentRoundsForBoard.isEmpty {
              WorkbenchEmptyLine("No tournament rounds yet.")
            } else {
              ForEach(tournamentRoundsForBoard) { round in
                tournamentRoundRow(round)
              }
            }
          }
        }

        WorkbenchSection("Round 2 Feasibility", systemImage: "wrench.and.screwdriver") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Button {
                Task { await applyRoundEvidenceTransition() }
              } label: {
                Label(
                  isApplyingRoundEvidenceTransition ? "Applying" : "Apply Round 2",
                  systemImage: "arrow.turn.down.right"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!roundEvidenceTransitionCanApply)
              .help(
                roundEvidenceTransitionProposal?.detail
                  ?? "No actionable Round 2 evidence recommendation yet."
              )

              if let roundEvidenceTransitionMessage {
                Text(roundEvidenceTransitionMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            if feasibilityHandoffs.isEmpty {
              WorkbenchEmptyLine("No narrowed contender is active in Round 2 yet.")
            } else {
              if !roundTwoProofOverview.isEmpty {
                Text("Core Technology Proof")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
              }
              ForEach(roundTwoProofOverview.prefix(3)) { item in
                roundTwoProofOverviewRow(item)
              }
              ForEach(feasibilityHandoffs.prefix(3)) { handoff in
                feasibilityHandoffRow(handoff)
              }
            }
          }
        }

        WorkbenchSection("Round 3 Product Implementation", systemImage: "crown") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Button {
                Task { await applyProductImplementationEvidenceTransition() }
              } label: {
                Label(
                  isApplyingProductImplementationEvidenceTransition ? "Applying" : "Apply Round 3",
                  systemImage: "checkmark.seal"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!productImplementationEvidenceTransitionCanApply)
              .help(
                productImplementationEvidenceTransitionProposal?.detail
                  ?? "No actionable Round 3 product implementation recommendation yet."
              )

              if let productImplementationEvidenceTransitionMessage {
                Text(productImplementationEvidenceTransitionMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            if !roundThreeProductImplementationOverview.isEmpty {
              Text("Product Implementation Winner Proof")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ForEach(roundThreeProductImplementationOverview.prefix(3)) { item in
                roundThreeProductImplementationOverviewRow(item)
              }
              if !roundThreeImplementationRevisionValidationOverview.isEmpty {
                Text("Implementation Revision Validation")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                ForEach(roundThreeImplementationRevisionValidationOverview.prefix(5)) { item in
                  roundThreeImplementationRevisionValidationRow(item)
                }
              }
              if let proposal = productImplementationEvidenceTransitionProposal {
                WorkbenchValueBlock(
                  title: proposal.title,
                  subtitle:
                    "\(proposal.contenderTitle) - \(proposal.scoreLabel)/100 - \(proposal.recommendation.rawValue)",
                  detail: proposal.detail
                )
              }
            } else {
              WorkbenchEmptyLine(
                "No contender is active in Round 3 product implementation evidence yet.")
            }
          }
        }

        WorkbenchSection("Contender Plans", systemImage: "lightbulb") {
          VStack(alignment: .leading, spacing: 8) {
            if config.contenderPlans.isEmpty {
              WorkbenchEmptyLine("No contender plans yet.")
            } else {
              ForEach(ProductTournamentContenderPlanStatus.allCases, id: \.rawValue) { status in
                let contenderPlans = config.contenderPlans.filter { $0.status == status }
                if !contenderPlans.isEmpty {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(status.rawValue)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                    ForEach(contenderPlans) { contenderPlan in
                      WorkbenchValueBlock(
                        title: contenderPlan.title,
                        subtitle: "pain \(contenderPlan.painID)",
                        detail: contenderPlan.promise
                      )
                    }
                  }
                }
              }
            }
          }
        }

        WorkbenchSection(
          "Implementation Tracks", systemImage: "point.3.connected.trianglepath.dotted"
        ) {
          VStack(alignment: .leading, spacing: 8) {
            if config.tournamentExperiments.isEmpty {
              WorkbenchEmptyLine("No contender implementation branches yet.")
            } else {
              ForEach(experimentsForBoard) { experiment in
                experimentRow(experiment)
              }
            }
          }
        }

        WorkbenchSection("Proof Scoreboard", systemImage: "chart.bar.doc.horizontal") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationProofTargetScoreboard.isEmpty {
              WorkbenchEmptyLine("No round-level proof target pressure queued.")
            } else {
              ForEach(tournamentAutomationProofTargetScoreboard.prefix(3)) { item in
                proofTargetScoreboardRow(item)
              }
            }
          }
        }

        WorkbenchSection("Proof Targets", systemImage: "target") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationProofTargets.isEmpty {
              WorkbenchEmptyLine("No tournament proof debt queued.")
            } else {
              ForEach(tournamentAutomationProofTargets.prefix(4)) { target in
                proofTargetRow(target)
              }
            }
          }
        }

        WorkbenchSection("Targeted Proof Outcomes", systemImage: "arrow.triangle.branch") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationTargetedProofOutcomeSignals.isEmpty {
              WorkbenchEmptyLine("No targeted tournament proof outcomes queued.")
            } else {
              ForEach(tournamentAutomationTargetedProofOutcomeSignals.prefix(4)) { signal in
                targetedProofOutcomeRow(signal)
              }
            }
          }
        }

        WorkbenchSection("Simulated User Rationale Signals", systemImage: "person.2.wave.2") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationRationaleSignals.isEmpty {
              WorkbenchEmptyLine("No repeated simulated-user rationale signals detected.")
            } else {
              ForEach(tournamentAutomationRationaleSignals.prefix(4)) { signal in
                rationaleSignalRow(signal)
              }
            }
          }
        }

        WorkbenchSection("Revision Briefs", systemImage: "hammer") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationRevisionBriefs.isEmpty {
              WorkbenchEmptyLine("No contender revision briefs queued.")
            } else {
              ForEach(tournamentAutomationRevisionBriefs.prefix(4)) { brief in
                revisionBriefRow(brief)
              }
            }
          }
        }

        WorkbenchSection("Evidence Tensions", systemImage: "exclamationmark.triangle") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationEvidenceTensions.isEmpty {
              WorkbenchEmptyLine("No split tournament evidence detected.")
            } else {
              ForEach(tournamentAutomationEvidenceTensions.prefix(4)) { tension in
                evidenceTensionRow(tension)
              }
            }
          }
        }

        WorkbenchSection("Decision Candidates", systemImage: "checkmark.seal") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationDecisionCandidates.isEmpty {
              WorkbenchEmptyLine("No tournament lift/cut decisions queued.")
            } else {
              ForEach(tournamentAutomationDecisionCandidates.prefix(4)) { candidate in
                decisionCandidateRow(candidate)
              }
            }
          }
        }
      }
      .padding(.trailing, 4)
    }
  }

  private func contenderRow(_ contender: ProductTournamentContender) -> some View {
    let experiment = contender.experimentID.flatMap { experimentID in
      config.tournamentExperiments.first { $0.id == experimentID }
    }
    let planReadiness = planReadiness(for: contender)
    let nextProofTarget = planProofTargetSummary(for: contender, readiness: planReadiness)
    let latestPlanProofDelta = TournamentAutomationPlanProofAuditDeltaFinder.latest(
      for: contender,
      in: config
    )
    return VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(contender.title)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
        Spacer()
        WorkbenchStatusPill(text: contender.status.rawValue)
      }
      WorkbenchFact(label: "Hypothesis", value: contender.contenderPlanID)
      WorkbenchFact(label: "Track", value: contender.experimentID ?? "plan only")
      if let experiment {
        WorkbenchFact(label: "Decision", value: experiment.decision.rawValue)
      }
      if let planReadiness {
        WorkbenchFact(
          label: "Plan",
          value:
            "\(planReadiness.scoreLabel)/100, \(planReadiness.recommendation.title), pay \(scoreLabel(planReadiness.averageWillingnessToPayScore))/5"
        )
        WorkbenchFact(label: "Plan proof", value: planReadiness.planProofDebt.summary)
        WorkbenchFact(label: "Commercial proof", value: planReadiness.commercialProofSummary)
        WorkbenchFact(label: "Next proof", value: nextProofTarget)
        WorkbenchFact(
          label: "Plan modes",
          value:
            "persona-model \(planReadiness.personaModelEvaluationCount), model-free \(planReadiness.modelFreeEvaluationCount)"
        )
        WorkbenchFact(
          label: "Buyer signals",
          value: "\(planReadiness.buyerOrSponsorPersonaCount)"
        )
        if let price = planReadiness.estimatedMonthlyPriceCents {
          WorkbenchFact(label: "Price", value: priceLabel(cents: price))
        }
      } else {
        WorkbenchFact(label: "Plan", value: "not evaluated")
        WorkbenchFact(label: "Commercial proof", value: "no willingness-to-pay proof yet")
        WorkbenchFact(label: "Next proof", value: nextProofTarget)
      }
      WorkbenchFact(
        label: "Segments",
        value: contender.targetSegmentIDs.isEmpty
          ? "none"
          : contender.targetSegmentIDs.joined(separator: ", ")
      )
      Text(contender.valueProposition)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text("Risk: \(contender.primaryRisk)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      if activePlanRoundContenderIDs.contains(contender.id) {
        HStack {
          Button {
            Task { await runPlanEvaluationRound(contenderID: contender.id, mode: .modelFree) }
          } label: {
            Label(
              runningPlanEvaluationContenderID == contender.id
                ? "Running Proof" : planProofActionTitle(readiness: planReadiness),
              systemImage: "target"
            )
          }
          .buttonStyle(.bordered)
          .disabled(!planEvaluationCanRun(for: contender))
          .help(planProofTargetHelp(for: contender, readiness: planReadiness))
          Button {
            Task { await runPlanEvaluationRound(contenderID: contender.id, mode: .personaModel) }
          } label: {
            Label("Persona Proof", systemImage: "sparkles")
          }
          .buttonStyle(.bordered)
          .disabled(!personaPlanEvaluationCanRun(for: contender))
          .help(
            FoundationModelsAvailability.isAvailable
              ? "Run Foundation Models persona proof for \(contender.title)."
              : "Foundation Models is unavailable for persona-model plan proof."
          )
          if let latestPlanProofDelta {
            Label(
              latestPlanProofDelta.displaySummary,
              systemImage: latestPlanProofDelta.displaySystemImage
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(latestPlanProofDelta.helpSummary)
          }
          Spacer()
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .contentShape(Rectangle())
    .onTapGesture {
      if let experimentID = contender.experimentID {
        selectedExperimentID = experimentID
      }
      if let latestEvaluationID = planReadiness?.latestEvaluationID {
        selectedPlanEvaluationID = latestEvaluationID
      }
    }
    .help(contender.productPlan)
  }

  private func planProofDeltaOverviewRow(
    _ item: TournamentPlanProofDeltaOverviewItem
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: item.displaySystemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16, alignment: .center)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(item.contenderTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: item.status.rawValue)
        }
        Text(item.displaySubtitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(item.displayDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityIdentifier(item.workbenchAccessibilityID)
    .help(item.helpSummary)
  }

  private func tournamentRoundRow(_ round: ProductTournamentRound) -> some View {
    let planEvaluations = evidenceIndex.planEvaluationSummaries.filter { $0.roundID == round.id }
    let scenarioRuns = evidenceIndex.summaries.filter { $0.roundID == round.id }
    return VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(round.title)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
        Spacer()
        WorkbenchStatusPill(text: round.status.rawValue)
      }
      WorkbenchFact(label: "Kind", value: round.kind.title)
      WorkbenchFact(
        label: "Product",
        value: round.requiresBuiltProduct ? "built product required" : "plan-only review"
      )
      WorkbenchFact(label: "Contenders", value: "\(round.contenderIDs.count)")
      if round.kind == .productPlans {
        WorkbenchFact(label: "Evaluations", value: "\(planEvaluations.count)")
      } else {
        WorkbenchFact(label: "Evidence runs", value: "\(scenarioRuns.count)")
      }
      if !round.scenarioCohortIDs.isEmpty {
        WorkbenchFact(label: "Cohorts", value: round.scenarioCohortIDs.joined(separator: ", "))
      }
      if !round.evaluationFocus.isEmpty {
        WorkbenchFact(
          label: "Focus", value: round.evaluationFocus.prefix(4).joined(separator: "; "))
      }
      Text(round.goal)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  private func feasibilityHandoffRow(_ handoff: ProductTournamentFeasibilityHandoff) -> some View {
    Button {
      selectedExperimentID = handoff.experimentID
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(handoff.contenderTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: "Round 2")
        }
        WorkbenchFact(label: "Track", value: handoff.experimentID)
        WorkbenchFact(label: "Branch", value: handoff.branchName)
        WorkbenchFact(label: "Plan", value: "\(handoff.scoreLabel)/100")
        if !handoff.scenarioCohortIDs.isEmpty {
          WorkbenchFact(label: "Cohorts", value: handoff.scenarioCohortIDs.joined(separator: ", "))
        }
        WorkbenchFact(
          label: "Acceptance",
          value: handoff.acceptanceSignals.prefix(3).joined(separator: "; ")
        )
        if let expectedEvidenceSignal = handoff.implementationBrief.expectedEvidenceSignal {
          WorkbenchFact(label: "Evidence signal", value: expectedEvidenceSignal)
        }
        if let killCriteria = handoff.implementationBrief.killCriteria {
          WorkbenchFact(label: "Kill criteria", value: killCriteria)
        }
        Text(handoff.coreTechnologyProof)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Text("Risk: \(handoff.riskFocus)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(handoff.feasibilityGoal)
  }

  private func roundTwoProofOverviewRow(
    _ item: ProductTournamentRoundTwoProofOverviewItem
  ) -> some View {
    Button {
      selectedExperimentID = item.experimentID
    } label: {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: item.displaySystemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 16, alignment: .center)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.contenderTitle)
              .font(.callout.weight(.semibold))
              .lineLimit(2)
            Spacer()
            WorkbenchStatusPill(text: item.recommendation.title)
          }
          Text(item.displaySubtitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
          WorkbenchFact(label: "Track", value: item.experimentID)
          WorkbenchFact(label: "Proof", value: item.coreTechnologyProof)
          if let validationSummary = item.proofGapValidationSummary {
            WorkbenchFact(label: "Validation", value: validationSummary)
              .help(item.proofGapValidationDetail ?? validationSummary)
          }
          Text(item.displayDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(item.workbenchAccessibilityID)
    .help(item.helpSummary)
  }

  private func roundThreeProductImplementationOverviewRow(
    _ item: ProductTournamentRoundThreeProductImplementationOverviewItem
  ) -> some View {
    Button {
      selectedExperimentID = item.experimentID
    } label: {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: item.displaySystemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 16, alignment: .center)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.contenderTitle)
              .font(.callout.weight(.semibold))
              .lineLimit(2)
            Spacer()
            WorkbenchStatusPill(text: item.recommendation.title)
          }
          Text(item.displaySubtitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
          WorkbenchFact(label: "Track", value: item.experimentID)
          WorkbenchFact(label: "Implementation", value: item.implementationScope)
          WorkbenchFact(label: "Alternative proof", value: "\(item.currentAlternativeProofCount)")
          WorkbenchFact(label: "Pay proof", value: "\(item.willingnessToPayProofCount)")
          if !item.proofGaps.isEmpty {
            WorkbenchFact(
              label: "Proof gaps", value: item.proofGaps.prefix(2).joined(separator: "; "))
          }
          if let validationSummary = item.implementationRevisionValidationSummary {
            WorkbenchFact(label: "Validation", value: validationSummary)
              .help(item.implementationRevisionValidationDetail ?? validationSummary)
          }
          Text(item.displayDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(item.workbenchAccessibilityID)
    .help(item.helpSummary)
  }

  private func roundThreeImplementationRevisionValidationRow(
    _ item: ProductTournamentRoundThreeImplementationRevisionValidationOverviewItem
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        selectedExperimentID = item.experimentID
        if let revisionScenarioID = item.revisionScenarioID {
          selectedScenarioID = revisionScenarioID
        }
      } label: {
        HStack(alignment: .top, spacing: 9) {
          Image(systemName: item.displaySystemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, alignment: .center)
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(item.contenderTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
              Spacer()
              WorkbenchStatusPill(text: item.outcome.title)
            }
            Text(item.displaySubtitle)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(2)
            WorkbenchFact(label: "Track", value: item.experimentID)
            WorkbenchFact(label: "Audit", value: item.revisionAuditID)
            if let revisionScenarioID = item.revisionScenarioID {
              WorkbenchFact(label: "Scenario", value: revisionScenarioID)
            }
            WorkbenchFact(label: "Validation", value: item.validationSummary)
            WorkbenchFact(label: "Next", value: item.nextStepSummary)
              .help(item.nextStepDetail)
            WorkbenchFact(label: "Persisted gaps", value: item.persistedGapSummary)
            WorkbenchFact(label: "Resolved gaps", value: item.resolvedGapSummary)
            Text(item.displayDetail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(3)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .buttonStyle(.plain)

      if let nextStep = item.nextStep {
        Button {
          Task { await runTournamentAutomationStep(nextStep) }
        } label: {
          Label(
            isRunningTournamentStep ? "Running Step" : "Run Next Step",
            systemImage: item.nextStepSystemImage
          )
        }
        .buttonStyle(.bordered)
        .disabled(isRunningTournamentStep || !nextStep.canExecute)
        .accessibilityIdentifier(item.runNextStepAccessibilityID)
        .help(
          nextStep.canExecute ? item.nextStepDetail : nextStep.blockedReason ?? item.nextStepDetail)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityIdentifier(item.workbenchAccessibilityID)
    .help(item.helpSummary)
  }

  private func experimentRow(_ experiment: ProductTournamentExperiment) -> some View {
    let implementationBrief = ProductTournamentImplementationTrackBrief(experiment: experiment)
    let signal = TournamentAutomationExperimentRanker.signal(
      for: experiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let roundTwoTarget = ProductTournamentRoundImplementationTargetResolver.roundTwoTarget(
      forExperimentInTargetTournament: experiment.id,
      in: config
    )
    return Button {
      selectedExperimentID = experiment.id
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(experiment.title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Spacer()
          WorkbenchStatusPill(text: experiment.decision.rawValue)
        }
        WorkbenchFact(label: "Readiness", value: signal.readinessLabel)
        WorkbenchFact(label: "Next", value: signal.nextActionLabel)
        WorkbenchFact(label: "Branch", value: experiment.branchName)
        WorkbenchFact(label: "Worktree", value: experiment.worktreeID)
        if implementationBrief.isCandidateDerived {
          WorkbenchFact(label: "Origin", value: "Discover candidate track")
        }
        WorkbenchFact(
          label: "Commit", value: experiment.currentSha ?? experiment.baseSha ?? "not created")
        if let expectedEvidenceSignal = implementationBrief.expectedEvidenceSignal {
          WorkbenchFact(label: "Evidence signal", value: expectedEvidenceSignal)
        }
        if let killCriteria = implementationBrief.killCriteria {
          WorkbenchFact(label: "Kill criteria", value: killCriteria)
        }
        if let roundTwoTarget {
          WorkbenchFact(
            label: "Round 2",
            value: roundTwoTarget.experimentID == experiment.id
              ? "selected implementation target"
              : "evidence locked to \(roundTwoTargetExperimentTitle(roundTwoTarget))"
          )
        }
        Text(implementationBrief.scopeSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selectedExperimentID == experiment.id
          ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
    .buttonStyle(.plain)
  }

  private func proofTargetScoreboardRow(
    _ item: TournamentAutomationProofTargetScoreboardItem
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(item.displayTitle)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
        Spacer()
        WorkbenchStatusPill(text: item.displaySubtitle)
      }
      WorkbenchFact(label: "Round", value: item.roundID ?? "unscoped")
      if let tournamentID = item.tournamentID {
        WorkbenchFact(label: "Tournament", value: tournamentID)
      }
      WorkbenchFact(label: "Pressure", value: item.readinessSummary)
        .accessibilityIdentifier(item.readinessSummaryAccessibilityID)
        .help(item.contextLine)
      WorkbenchStatusFact(
        label: "Top action",
        value: item.topActionSummary,
        statusText: item.topActionStatusLabel,
        statusSystemImage: item.topActionStatusSystemImage,
        statusAccessibilityID: item.topActionStatusAccessibilityID
      )
      .help(item.topActionDetail)
      WorkbenchFact(label: "Targets", value: item.displayDetail)
      ForEach(item.displayReadinessGroups()) { group in
        VStack(alignment: .leading, spacing: 5) {
          proofTargetScoreboardGroupHeader(item: item, group: group)
          proofTargetScoreboardGroupResult(item: item, group: group)
          ForEach(group.rows) { row in
            Button {
              selectProofScoreboardRow(row)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  WorkbenchFact(label: row.contenderTitle, value: row.displaySummary)
                  if selectedProofScoreboardRowID == row.selectionID {
                    WorkbenchStatusPill(text: "selected")
                  }
                }
                WorkbenchFact(label: "Latest delta", value: row.latestDebtMovementSummary)
                  .help(row.helpSummary)
                WorkbenchStatusFact(
                  label: "Last / Next",
                  value: row.runPairSummary,
                  statusText: row.nextStatusLabel,
                  statusSystemImage: row.nextStatusSystemImage,
                  statusAccessibilityID: row.nextStatusAccessibilityID
                )
                .help(row.helpSummary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(row.workbenchAccessibilityID)
            .help(row.helpSummary)
          }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(
          "\(item.workbenchAccessibilityID)-group-\(group.accessibilitySuffix)"
        )
      }
      if let topActionRow = item.topActionRow, let topStep = topActionRow.nextStep {
        let roundTwoBlockedMessage =
          roundTwoLaunchBlockedMessage(experimentID: topStep.experimentID)
        let helpText =
          roundTwoBlockedMessage
          ?? (topStep.canExecute
            ? item.topActionDetail
            : topStep.blockedReason ?? item.topActionDetail)
        let isDisabled =
          isRunningTournamentStep || isRunningTournamentAutomationCycle || isRunningScenario
          || !topStep.canExecute || roundTwoBlockedMessage != nil
        Button {
          Task { await runTournamentAutomationStep(topStep) }
        } label: {
          Label(
            isRunningTournamentStep ? "Running Proof" : item.topActionButtonTitle,
            systemImage: topActionRow.nextStepSystemImage
          )
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .accessibilityIdentifier(item.runTopStepAccessibilityID)
        .help(helpText)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityIdentifier(item.workbenchAccessibilityID)
    .help(item.contextLine)
  }

  @ViewBuilder
  private func proofTargetScoreboardGroupHeader(
    item: TournamentAutomationProofTargetScoreboardItem,
    group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(group.bucket)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Spacer()
      WorkbenchStatusPill(text: "\(group.count)")
      if isSelectedProofScoreboardGroup(group) {
        WorkbenchStatusPill(text: "selected group")
          .accessibilityIdentifier(item.readinessGroupSelectionAccessibilityID(group))
      }
      if let actionRow = group.primaryActionRow, let actionStep = group.primaryActionStep {
        let roundTwoBlockedMessage =
          roundTwoLaunchBlockedMessage(experimentID: actionStep.experimentID)
        let helpText =
          roundTwoBlockedMessage
          ?? (actionStep.canExecute
            ? group.actionHelpSummary
            : actionStep.blockedReason ?? group.actionHelpSummary)
        let isDisabled =
          isRunningTournamentStep || isRunningTournamentAutomationCycle || isRunningScenario
          || !actionStep.canExecute || roundTwoBlockedMessage != nil
        Button {
          selectProofScoreboardGroup(group, preferredRow: actionRow)
          Task {
            await runTournamentAutomationStep(
              actionStep,
              groupAnchorRowID: actionRow.selectionID,
              actedPressureGroupSummary: group.actionAuditSummary(anchorRow: actionRow)
            )
          }
        } label: {
          Label(
            isRunningTournamentStep ? "Running" : group.actionButtonTitle,
            systemImage: group.actionSystemImage
          )
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .accessibilityIdentifier(item.readinessGroupActionAccessibilityID(group))
        .help(helpText)
      } else if group.primaryRow != nil {
        Button {
          selectProofScoreboardGroup(group)
        } label: {
          Label(group.actionButtonTitle, systemImage: group.actionSystemImage)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(item.readinessGroupActionAccessibilityID(group))
        .help(group.actionHelpSummary)
      }
    }
  }

  @ViewBuilder
  private func proofTargetScoreboardGroupResult(
    item: TournamentAutomationProofTargetScoreboardItem,
    group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> some View {
    if group.latestMovement != nil {
      WorkbenchStatusFact(
        label: "Group result",
        value: group.latestMovementSummary,
        statusText: group.latestMovementStatusLabel,
        statusSystemImage: group.latestMovementSystemImage,
        statusAccessibilityID: item.readinessGroupResultAccessibilityID(group)
      )
      .help(group.latestMovementHelpSummary)
    }
  }

  private func proofTargetRow(_ target: TournamentAutomationProofTarget) -> some View {
    Button {
      selectedExperimentID = target.experimentID
      if let targetScenarioID = target.targetScenarioID {
        selectedScenarioID = targetScenarioID
      }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(target.displayTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: "\(target.readinessScore)/100")
        }
        WorkbenchFact(label: "Experiment", value: target.experimentID)
        WorkbenchFact(label: "Target", value: target.displaySubtitle)
        WorkbenchFact(label: "Debt", value: target.debtSummary)
        if let tournamentPositionSummary = target.tournamentPositionSummary {
          WorkbenchFact(label: "Tournament position", value: tournamentPositionSummary)
        }
        if let nextActionTitle = target.nextActionTitle {
          WorkbenchFact(label: "Next", value: nextActionTitle)
        }
        if let tournamentID = target.tournamentID {
          WorkbenchFact(label: "Tournament", value: tournamentID)
        }
        if let contenderID = target.contenderID {
          WorkbenchFact(label: "Contender", value: contenderID)
        }
        if let roundID = target.roundID {
          WorkbenchFact(label: "Round", value: roundID)
        }
        if let targetScenarioID = target.targetScenarioID {
          WorkbenchFact(label: "Scenario", value: targetScenarioID)
        } else if let cohortID = target.cohortID {
          WorkbenchFact(label: "Cohort", value: cohortID)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(target.displayDetail)
  }

  private func targetedProofOutcomeRow(
    _ signal: TournamentAutomationTargetedProofOutcomeSignal
  ) -> some View {
    Button {
      selectedExperimentID = signal.experimentID
      if let targetScenarioID = signal.targetScenarioID {
        selectedScenarioID = targetScenarioID
      }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(signal.title)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: "\(signal.priority)")
        }
        WorkbenchFact(label: "Experiment", value: signal.experimentID)
        WorkbenchFact(label: "Outcome", value: signal.displaySubtitle)
        if !signal.runIDs.isEmpty {
          WorkbenchFact(label: "Runs", value: signal.runIDs.prefix(3).joined(separator: ", "))
        }
        if let targetScenarioID = signal.targetScenarioID {
          WorkbenchFact(label: "Scenario", value: targetScenarioID)
        } else if let targetPersonaName = signal.targetPersonaName {
          WorkbenchFact(label: "Target", value: targetPersonaName)
        }
        Text(signal.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(signal.auditSummary)
  }

  private func rationaleSignalRow(_ signal: TournamentAutomationRationaleSignal) -> some View {
    Button {
      selectedExperimentID = signal.experimentID
      if let targetScenarioID = signal.targetScenarioID {
        selectedScenarioID = targetScenarioID
      }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(
            signal.targetPersonaName.map { "simulated-user rationale: \($0)" }
              ?? "simulated-user rationale signal"
          )
          .font(.callout.weight(.semibold))
          .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: "\(signal.count)x")
        }
        WorkbenchFact(label: "Experiment", value: signal.experimentID)
        WorkbenchFact(label: "Rationale", value: signal.rationale)
        if !signal.runIDs.isEmpty {
          WorkbenchFact(label: "Runs", value: signal.runIDs.prefix(3).joined(separator: ", "))
        }
        if let targetPersonaName = signal.targetPersonaName {
          WorkbenchFact(label: "Target", value: targetPersonaName)
        }
        if let targetDecision = signal.targetDecision {
          WorkbenchFact(label: "Decision", value: targetDecision.rawValue)
        }
        if let targetScenarioID = signal.targetScenarioID {
          WorkbenchFact(label: "Scenario", value: targetScenarioID)
        }
        if let targetCohortID = signal.targetCohortID {
          WorkbenchFact(label: "Cohort", value: targetCohortID)
        }
        Text(signal.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(signal.auditSummary)
  }

  private func revisionBriefRow(_ brief: TournamentAutomationRevisionBrief) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        selectedExperimentID = brief.experimentID
        if let targetScenarioID = brief.targetScenarioID {
          selectedScenarioID = targetScenarioID
        }
      } label: {
        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(brief.title)
              .font(.callout.weight(.semibold))
              .lineLimit(2)
            Spacer()
            WorkbenchStatusPill(text: "\(brief.priority)")
          }
          WorkbenchFact(label: "Experiment", value: brief.experimentID)
          WorkbenchFact(label: "Source", value: brief.displaySubtitle)
          if let validationContextSummary = brief.validationContextSummary {
            WorkbenchFact(label: "Validation", value: validationContextSummary)
              .help(brief.validationContextDetail ?? validationContextSummary)
          }
          WorkbenchFact(label: "Implementation", value: brief.implementationChange)
          WorkbenchFact(label: "Scenario", value: brief.scenarioChange)
          WorkbenchFact(label: "Proof", value: brief.proofPlan)
          if let targetPersonaName = brief.targetPersonaName {
            WorkbenchFact(label: "Target", value: targetPersonaName)
          }
          if let targetScenarioID = brief.targetScenarioID {
            WorkbenchFact(label: "Target scenario", value: targetScenarioID)
          }
        }
      }
      .buttonStyle(.plain)

      Button {
        Task { await applyRevisionBrief(brief) }
      } label: {
        Label("Apply Scenario", systemImage: "wand.and.stars")
      }
      .buttonStyle(.bordered)
      .disabled(isSavingScenario)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .help(brief.displayDetail)
  }

  private func evidenceTensionRow(_ tension: TournamentAutomationEvidenceTension) -> some View {
    Button {
      selectedExperimentID = tension.experimentID
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(tension.displayTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          Spacer()
          WorkbenchStatusPill(text: "\(tension.readinessScore)/100")
        }
        WorkbenchFact(label: "Experiment", value: tension.experimentID)
        WorkbenchFact(label: "Split", value: tension.displaySubtitle)
        if let targetPersonaName = tension.targetPersonaName {
          WorkbenchFact(label: "Target", value: targetPersonaName)
        }
        if let targetScenarioID = tension.targetScenarioID {
          WorkbenchFact(label: "Scenario", value: targetScenarioID)
        }
        WorkbenchFact(
          label: "Pull",
          value: tension.positiveEvidenceRunIDs.isEmpty
            ? "none"
            : tension.positiveEvidenceRunIDs.prefix(3).joined(separator: ", ")
        )
        WorkbenchFact(
          label: "Reject",
          value: tension.negativeEvidenceRunIDs.isEmpty
            ? "none"
            : tension.negativeEvidenceRunIDs.prefix(3).joined(separator: ", ")
        )
        Text(tension.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(tension.displayDetail)
  }

  private func decisionCandidateRow(_ candidate: TournamentAutomationDecisionCandidate) -> some View
  {
    Button {
      selectedExperimentID = candidate.experimentID
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(candidate.displayTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Spacer()
          WorkbenchStatusPill(text: candidate.pressure.title)
        }
        WorkbenchFact(label: "Experiment", value: candidate.experimentID)
        WorkbenchFact(label: "Readiness", value: "\(candidate.readinessScore)/100")
        WorkbenchFact(
          label: "Evidence",
          value: candidate.evidenceRunIDs.isEmpty
            ? "none"
            : candidate.evidenceRunIDs.prefix(3).joined(separator: ", ")
        )
        Text(candidate.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(candidate.displayDetail)
  }

  private var evidenceAndDecisionPane: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        tournamentAutomation
        tournamentPortfolioPreview
        selectedProofScoreboardDetail
        aggregateEvidence
        planEvaluationEvidence
        selectedPlanEvaluationDetail
        selectedExperimentActions
        scenarioAuthoring
        evidenceRuns
        selectedEvidenceDetail
        decisionTimeline
      }
      .padding(.trailing, 8)
    }
  }

  private var tournamentAutomation: some View {
    WorkbenchSection("Tournament Automation", systemImage: "sparkles") {
      VStack(alignment: .leading, spacing: 8) {
        if let step = tournamentAutomationStep {
          WorkbenchFact(label: "Experiment", value: step.experimentTitle)
          WorkbenchFact(
            label: "Step",
            value: "\(step.queueTitle), \(step.action.kind.rawValue)"
          )
          if let decisionIntentSummary = step.decisionIntentSummary {
            WorkbenchFact(label: "Intent", value: decisionIntentSummary)
          }
          WorkbenchFact(label: "Cycle", value: tournamentAutomationCyclePlan.summary)
          WorkbenchFact(label: "Queue", value: tournamentAutomationCyclePlan.queueSummary)
          if step.kind == .runPlanProof {
            WorkbenchFact(label: "Mode", value: "Model-free plan proof")
          } else if step.kind == .prepareWorktree {
            WorkbenchFact(label: "Mode", value: "Prepare implementation worktree")
          } else if step.kind == .runCohort {
            WorkbenchFact(
              label: "Mode",
              value: "\(tournamentAutomationCohortMode.tournamentAutomationLabel) cohort"
            )
          } else if step.kind == .applyRoundTransition {
            WorkbenchFact(label: "Mode", value: "Apply round transition")
            WorkbenchFact(
              label: "Transition",
              value: transitionScopeLabel(for: step)
            )
          }
          if let tournamentAutomationRoundTwoBlockedMessage {
            WorkbenchFact(label: "Round 2", value: tournamentAutomationRoundTwoBlockedMessage)
          }
          if let latestTournamentAutomationCycleFacts {
            WorkbenchFact(
              label: "Last Cycle",
              value: latestTournamentAutomationCycleFacts.latestCycleSummary
            )
            .help(latestTournamentAutomationCycleFacts.latestCycleHelp)
            if let latestPreparationSummary =
              latestTournamentAutomationCycleFacts.latestPreparationSummary
            {
              WorkbenchFact(label: "Last Prep", value: latestPreparationSummary)
                .help(
                  latestTournamentAutomationCycleFacts.latestPreparationHelp
                    ?? latestPreparationSummary
                )
            }
            WorkbenchFact(
              label: "Last Evidence",
              value: latestTournamentAutomationCycleFacts.latestEvidenceSummary
            )
            .help(
              latestTournamentAutomationCycleFacts.latestEvidenceHelp
                ?? "No tournament evidence run has been recorded in recent cycle audits."
            )
            if let latestActedPressureGroupSummary =
              latestTournamentAutomationCycleFacts.latestActedPressureGroupSummary
            {
              WorkbenchFact(label: "Last Group", value: latestActedPressureGroupSummary)
                .help(
                  latestTournamentAutomationCycleFacts.latestActedPressureGroupHelp
                    ?? latestActedPressureGroupSummary
                )
            }
            if let latestActedPressureGroupOutcomeSummary =
              latestTournamentAutomationCycleFacts.latestActedPressureGroupOutcomeSummary
            {
              WorkbenchFact(label: "Group Outcome", value: latestActedPressureGroupOutcomeSummary)
                .help(
                  latestTournamentAutomationCycleFacts.latestActedPressureGroupOutcomeHelp
                    ?? latestActedPressureGroupOutcomeSummary
                )
            }
            if let latestActedPressureGroupLearningSummary =
              latestTournamentAutomationCycleFacts.latestActedPressureGroupLearningSummary
            {
              WorkbenchFact(
                label: "Group Learning",
                value: latestActedPressureGroupLearningSummary
              )
              .help(
                latestTournamentAutomationCycleFacts.latestActedPressureGroupLearningHelp
                  ?? latestActedPressureGroupLearningSummary
              )
            }
            if let latestActedRevisionValidationSummary =
              latestTournamentAutomationCycleFacts.latestActedRevisionValidationSummary
            {
              WorkbenchFact(label: "Revision", value: latestActedRevisionValidationSummary)
                .help(
                  latestTournamentAutomationCycleFacts.latestActedRevisionValidationHelp
                    ?? latestActedRevisionValidationSummary
                )
            }
            if let latestActedRevisionValidationRunSummary =
              latestTournamentAutomationCycleFacts.latestActedRevisionValidationRunSummary
            {
              WorkbenchFact(
                label: "Revision Check",
                value: latestActedRevisionValidationRunSummary
              )
              .help(
                latestTournamentAutomationCycleFacts.latestActedRevisionValidationRunHelp
                  ?? latestActedRevisionValidationRunSummary
              )
            }
            if let postPreparationEvidenceSummary =
              latestTournamentAutomationCycleFacts.postPreparationEvidenceSummary
            {
              WorkbenchFact(label: "Post Prep", value: postPreparationEvidenceSummary)
                .help(
                  latestTournamentAutomationCycleFacts.postPreparationEvidenceHelp
                    ?? postPreparationEvidenceSummary
                )
            }
            if let validationSummary =
              latestTournamentAutomationCycleFacts.latestRoundTwoProofGapValidationSummary
            {
              WorkbenchFact(label: "Round 2 Validation", value: validationSummary)
                .help(
                  latestTournamentAutomationCycleFacts.latestRoundTwoProofGapValidationHelp
                    ?? validationSummary
                )
            }
            if let validationSummary =
              latestTournamentAutomationCycleFacts
              .latestRoundThreeImplementationRevisionValidationSummary
            {
              WorkbenchFact(label: "Round 3 Validation", value: validationSummary)
                .help(
                  latestTournamentAutomationCycleFacts
                    .latestRoundThreeImplementationRevisionValidationHelp
                    ?? validationSummary
                )
            }
          }
          Text(step.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            Button {
              Task { await runTournamentAutomationStep() }
            } label: {
              Label(
                isRunningTournamentStep ? "Running Step" : "Run Step",
                systemImage: "play.fill"
              )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!tournamentAutomationCanRun)

            Button {
              Task { await runTournamentAutomationCycle() }
            } label: {
              Label(
                isRunningTournamentAutomationCycle ? "Running Cycle" : "Run Cycle",
                systemImage: "forward.frame.fill"
              )
            }
            .buttonStyle(.bordered)
            .disabled(!tournamentAutomationCycleCanRun)
          }
        } else {
          WorkbenchEmptyLine("No tournament automation action queued.")
        }
      }
    }
  }

  private var tournamentPortfolioPreview: some View {
    WorkbenchSection("Portfolio Lanes", systemImage: "rectangle.3.group.bubble.left") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          WorkbenchStatusPill(
            text: tournamentRolloutFlags.tournamentSchedulerPreview ? "Preview on" : "Sequential"
          )
          WorkbenchStatusPill(
            text: tournamentRolloutFlags.tournamentParallelEvidence ? "Evidence parallel" : "Evidence serial"
          )
          WorkbenchStatusPill(
            text: tournamentRolloutFlags.tournamentParallelDevelop ? "Develop parallel" : "Develop serial"
          )
        }

        if tournamentLaneStates.isEmpty {
          WorkbenchEmptyLine("No active product lanes.")
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(tournamentLaneStates.prefix(4)) { lane in
              laneBoardRow(lane)
            }
          }
        }

        Divider()

        WorkbenchFact(label: "Selected", value: tournamentPortfolioSchedule.selectedSummary)
        WorkbenchFact(label: "Deferred", value: tournamentPortfolioSchedule.deferredSummary)
        if let barrier = tournamentJudgingBarriers.first {
          WorkbenchFact(label: "Barrier", value: barrier.summary)
        } else {
          WorkbenchFact(label: "Barrier", value: "No judging barrier active.")
        }
        WorkbenchFact(
          label: "In Flight",
          value:
            tournamentRolloutFlags.tournamentParallelEvidence
            ? "\(tournamentPortfolioSchedule.parallelizableEvidenceWork.count) evidence-ready task(s)"
            : "Parallel evidence disabled"
        )

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Button {
              Task { await runTournamentAutomationStep() }
            } label: {
              Label("Run Lane", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!tournamentAutomationCanRun)

            Button {
              Task { await runTournamentAutomationCycle() }
            } label: {
              Label("Run Portfolio", systemImage: "forward.frame.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!tournamentAutomationCycleCanRun || pausePortfolioAfterCurrentBatch)

            Toggle("Pause after batch", isOn: $pausePortfolioAfterCurrentBatch)
              .toggleStyle(.checkbox)
          }
          HStack(spacing: 8) {
            Button {
              cancelledPortfolioLaneID = tournamentLaneStates.first?.id
            } label: {
              Label("Cancel Lane", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(tournamentLaneStates.isEmpty)

            Button {
              cancelledPortfolioLaneID = "all"
              pausePortfolioAfterCurrentBatch = true
            } label: {
              Label("Cancel All", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)

            if let cancelledPortfolioLaneID {
              WorkbenchStatusPill(text: "cancel \(cancelledPortfolioLaneID)")
            }
          }

          Stepper("Evidence \(evidenceConcurrencyLimit)", value: $evidenceConcurrencyLimit, in: 1...8)
          Stepper("LLM \(personaLLMConcurrencyLimit)", value: $personaLLMConcurrencyLimit, in: 1...4)
          Stepper("Simulation \(simulationConcurrencyLimit)", value: $simulationConcurrencyLimit, in: 1...8)
        }
        .font(.caption)
      }
    }
  }

  private func laneBoardRow(_ lane: ProductTournamentLaneState) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(lane.contenderTitle ?? lane.experimentTitle)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer()
        WorkbenchStatusPill(text: lane.status.label)
      }
      WorkbenchFact(label: "Branch", value: lane.branchName)
      WorkbenchFact(label: "Worktree", value: lane.worktreeID)
      WorkbenchFact(label: "Evidence", value: lane.latestEvidenceIDs.joined(separator: ", "))
      WorkbenchFact(label: "Debt", value: lane.proofDebtSummary)
      if let blockedReason = lane.blockedReason {
        WorkbenchFact(label: "Blocked", value: blockedReason)
      }
      if let stepID = lane.activeStepID {
        WorkbenchFact(label: "Next", value: stepID)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var selectedProofScoreboardDetail: some View {
    if let row = selectedProofScoreboardRow {
      WorkbenchSection("Selected Proof Target", systemImage: "scope") {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.contenderTitle)
              .font(.callout.weight(.semibold))
              .lineLimit(2)
            Spacer()
            WorkbenchStatusPill(text: "\(row.readinessScore)/100")
          }
          WorkbenchFact(label: "Experiment", value: row.experimentID)
          if let contenderID = row.contenderID {
            WorkbenchFact(label: "Contender", value: contenderID)
          }
          if let roundID = row.roundID {
            WorkbenchFact(label: "Round", value: roundID)
          }
          if let targetScenarioID = row.targetScenarioID {
            WorkbenchFact(label: "Scenario", value: targetScenarioID)
          } else if let cohortID = row.cohortID {
            WorkbenchFact(label: "Cohort", value: cohortID)
          }
          if let targetPersonaName = row.targetPersonaName {
            WorkbenchFact(label: "Persona", value: targetPersonaName)
          }
          if let targetDecision = row.targetDecision {
            WorkbenchFact(label: "Decision", value: targetDecision.rawValue)
          }
          WorkbenchFact(label: "Last / Next", value: row.runPairSummary)
          WorkbenchFact(label: "Latest delta", value: row.latestDebtMovementSummary)
            .help(row.helpSummary)
          if let revisionCheck = selectedProofActedRevisionValidationRunContext {
            WorkbenchFact(label: "Revision Check", value: revisionCheck.summary)
              .help(revisionCheck.help)
          }
          selectedProofMovementStrip(for: row)
          if let latestDebtMovement = row.latestDebtMovement {
            WorkbenchFact(label: "Audit", value: latestDebtMovement.auditID)
            if !latestDebtMovement.evidenceRunIDs.isEmpty {
              WorkbenchFact(
                label: "Outcome IDs",
                value: latestDebtMovement.evidenceRunIDs.prefix(4).joined(separator: ", ")
              )
            }
          }
          Text(row.nextStepDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let nextStep = row.nextStep {
            let roundTwoBlockedMessage =
              roundTwoLaunchBlockedMessage(experimentID: nextStep.experimentID)
            let helpText =
              roundTwoBlockedMessage
              ?? (nextStep.canExecute
                ? row.nextStepDetail
                : nextStep.blockedReason ?? row.nextStepDetail)
            let isDisabled =
              isRunningTournamentStep || isRunningTournamentAutomationCycle || isRunningScenario
              || !nextStep.canExecute || roundTwoBlockedMessage != nil
            Button {
              Task { await runTournamentAutomationStep(nextStep) }
            } label: {
              Label(
                isRunningTournamentStep ? "Running Proof" : row.selectedActionButtonTitle,
                systemImage: row.nextStepSystemImage
              )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
            .accessibilityIdentifier(row.runSelectedStepAccessibilityID)
            .help(helpText)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func selectedProofMovementStrip(
    for row: TournamentAutomationProofTargetScoreboardRow
  ) -> some View {
    if let movement = row.latestDebtMovement {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("Proof Movement")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          WorkbenchStatusPill(text: movement.movementLabel)
        }
        HStack(spacing: 6) {
          WorkbenchMetric(
            label: "Start",
            value: movement.startCountLabel,
            systemImage: "flag"
          )
          WorkbenchMetric(
            label: "End",
            value: movement.endCountLabel,
            systemImage: "checkered.flag"
          )
          WorkbenchMetric(
            label: "Delta",
            value: movement.deltaLabel,
            systemImage: movement.movementSystemImage
          )
        }
        WorkbenchStatusFact(
          label: "After result",
          value: row.postMovementNextSummary,
          statusText: row.nextStatusLabel,
          statusSystemImage: row.nextStatusSystemImage
        )
        .help(row.postMovementNextDetail)
      }
      .accessibilityIdentifier(row.proofMovementAccessibilityID)
      .help(movement.resultStripSummary)
    }
  }

  @ViewBuilder
  private var scenarioAuthoring: some View {
    if let experiment = selectedExperiment {
      WorkbenchSection("Product Test Builder", systemImage: "target") {
        ProductTestBuilderView(
          draft: productTestDraft(for: experiment)
        ) {
          if !scenariosForSelectedExperiment.isEmpty {
            Picker("Scenario", selection: scenarioSelectionBinding) {
              ForEach(scenariosForSelectedExperiment) { scenario in
                Text(scenario.title).tag(scenario.id)
              }
            }
            .pickerStyle(.menu)
          }

          TextField("Product question", text: $scenarioTitle)
            .textFieldStyle(.roundedBorder)
          HStack(spacing: 8) {
            Picker("Target user", selection: $scenarioSegmentID) {
              ForEach(config.userSegments) { segment in
                Text(segment.name).tag(segment.id)
              }
            }
            Picker("Workflow", selection: $scenarioWorkflowID) {
              ForEach(config.currentWorkflows) { workflow in
                Text(workflow.title).tag(workflow.id)
              }
            }
            Picker("Alternative", selection: $scenarioAlternativeID) {
              Text("None").tag("")
              ForEach(config.alternatives) { alternative in
                Text(alternative.title).tag(alternative.id)
              }
            }
          }
          .pickerStyle(.menu)
          TextEditor(text: $scenarioTask)
            .font(.caption)
            .frame(minHeight: 58, maxHeight: 76)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
          TextField("Success signal", text: $scenarioSuccessSignal)
            .textFieldStyle(.roundedBorder)
        } runControls: {
          if let scenarioRunMessage {
            Text(scenarioRunMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          HStack(spacing: 8) {
            Button {
              Task { await saveScenarioDraft() }
            } label: {
              Label(
                isSavingScenario ? "Saving" : "Save Test", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(isSavingScenario || !scenarioDraftCanSave)

            Button {
              Task { await runScenarioModelFree() }
            } label: {
              Label(isRunningScenario ? "Running" : "Run Test", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunningScenario || !scenarioCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? "Run this product test with a model-free simulated user."
            )

            Button {
              Task { await runScenarioPersonaModel() }
            } label: {
              Label(
                isRunningScenario ? "Running" : "Persona Test",
                systemImage: "brain.head.profile"
              )
            }
            .buttonStyle(.bordered)
            .disabled(isRunningScenario || !personaScenarioCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? (FoundationModelsAvailability.isAvailable
                  ? "Run with a persona-model simulated user"
                  : ProductTournamentPersonaActionModelError.unavailable.localizedDescription)
            )
          }
          HStack(spacing: 8) {
            Button {
              Task { await runScenarioCohortModelFree() }
            } label: {
              Label(
                isRunningScenario ? "Running" : "Run Cohort",
                systemImage: "play.rectangle.on.rectangle"
              )
            }
            .buttonStyle(.bordered)
            .disabled(isRunningScenario || !scenarioCohortCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? "Run the selected scenario cohort with model-free simulated users."
            )

            Button {
              Task { await runScenarioCohortPersonaModel() }
            } label: {
              Label(
                isRunningScenario ? "Running" : "Persona Cohort",
                systemImage: "person.2.wave.2"
              )
            }
            .buttonStyle(.bordered)
            .disabled(isRunningScenario || !personaCohortCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? (FoundationModelsAvailability.isAvailable
                  ? "Run the cohort with persona-model simulated users"
                  : ProductTournamentPersonaActionModelError.unavailable.localizedDescription)
            )
          }
        } auditContent: {
          HStack(spacing: 8) {
            TextField("Cohort title", text: $scenarioCohortTitle)
              .textFieldStyle(.roundedBorder)
            Toggle("Cohort enabled", isOn: $scenarioCohortEnabled)
              .toggleStyle(.checkbox)
          }
          HStack(spacing: 10) {
            Stepper("Turns \(scenarioMaxTurns)", value: $scenarioMaxTurns, in: 1...20)
              .frame(width: 130, alignment: .leading)
            Stepper(
              "Timeout \(Int(scenarioTimeoutSeconds))s", value: $scenarioTimeoutSeconds,
              in: 5...1200, step: 5
            )
            .frame(width: 170, alignment: .leading)
            Toggle("Enabled", isOn: $scenarioEnabled)
              .toggleStyle(.checkbox)
          }
          WorkbenchFact(
            label: "Target",
            value: scenarioTargetCommit.isEmpty
              ? (experiment.currentSha ?? experiment.baseSha ?? "no commit")
              : scenarioTargetCommit
          )
          roundTwoImplementationTargetNotice
          if let contractAvailable {
            Label(
              contractAvailable
                ? "Tournament experience contract available"
                : "Tournament experience contract missing",
              systemImage: contractAvailable ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(contractAvailable ? Color.secondary : Color.orange)
          } else {
            WorkbenchEmptyLine("Checking tournament experience contract...")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var roundTwoImplementationTargetNotice: some View {
    if let target = selectedRoundTwoImplementationTarget {
      let isSelectedTarget = selectedExperiment?.id == target.experimentID
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 8) {
          Label(
            isSelectedTarget ? "Round 2 target selected" : "Round 2 target locked",
            systemImage: isSelectedTarget ? "scope" : "lock"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelectedTarget ? Color.secondary : Color.orange)
          Spacer()
          if !isSelectedTarget {
            Button {
              selectRoundTwoImplementationTarget(target)
            } label: {
              Label("Select Target", systemImage: "scope")
            }
            .buttonStyle(.bordered)
          }
        }
        WorkbenchFact(
          label: "Track",
          value: "\(roundTwoTargetExperimentTitle(target)) (\(target.experimentID))"
        )
        WorkbenchFact(
          label: "Contender",
          value: "\(roundTwoTargetContenderTitle(target)) (\(target.contenderID))"
        )
        if let handoff = selectedRoundTwoTargetHandoff {
          WorkbenchFact(label: "Proof", value: handoff.coreTechnologyProof)
          WorkbenchFact(
            label: "Acceptance",
            value: handoff.acceptanceSignals.prefix(3).joined(separator: "; ")
          )
          if let expectedEvidenceSignal = handoff.implementationBrief.expectedEvidenceSignal {
            WorkbenchFact(label: "Evidence signal", value: expectedEvidenceSignal)
          }
          if let killCriteria = handoff.implementationBrief.killCriteria {
            WorkbenchFact(label: "Kill criteria", value: killCriteria)
          }
        } else {
          WorkbenchFact(label: "Round", value: target.roundID)
        }
        if !isSelectedTarget, let selectedExperiment {
          Text(
            "Scenario evidence for \(selectedExperiment.title) is paused while this Round 2 proof targets \(roundTwoTargetExperimentTitle(target))."
          )
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        (isSelectedTarget ? Color.secondary.opacity(0.08) : Color.orange.opacity(0.10)),
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
  }

  private func selectRoundTwoImplementationTarget(
    _ target: ProductTournamentRoundImplementationTarget
  ) {
    selectedExperimentID = target.experimentID
    selectedScenarioID =
      config.scenarios
      .filter { $0.experimentID == target.experimentID }
      .sorted { lhs, rhs in
        if lhs.updatedAt == rhs.updatedAt { return lhs.title < rhs.title }
        return lhs.updatedAt > rhs.updatedAt
      }
      .first?.id
    scenarioRunMessage = nil
  }

  private var scenarioSelectionBinding: Binding<String> {
    Binding(
      get: { selectedScenarioID ?? scenariosForSelectedExperiment.first?.id ?? "" },
      set: { selectedScenarioID = $0.isEmpty ? nil : $0 }
    )
  }

  private func productTestDraft(for experiment: ProductTournamentExperiment) -> ProductTestDraft {
    ProductTestDraft.build(
      input: ProductTestDraftInput(
        id: selectedScenarioID,
        experimentID: experiment.id,
        cohortID: scenarioCohortID.isEmpty ? nil : scenarioCohortID,
        cohortTitle: scenarioCohortTitle,
        cohortEnabled: scenarioCohortEnabled,
        segmentID: scenarioSegmentID,
        currentWorkflowID: scenarioWorkflowID,
        alternativeID: scenarioAlternativeID.isEmpty ? nil : scenarioAlternativeID,
        title: scenarioTitle,
        task: scenarioTask,
        successSignal: scenarioSuccessSignal,
        targetCommitSha: scenarioTargetCommit.isEmpty
          ? (experiment.currentSha ?? experiment.baseSha)
          : scenarioTargetCommit,
        maxTurns: scenarioMaxTurns,
        appCommandTimeoutSeconds: scenarioTimeoutSeconds,
        enabled: scenarioEnabled
      ),
      config: config,
      nextMove: productDecisionCockpit.nextMove,
      contractAvailable: contractAvailable,
      blockedReason: selectedRoundTwoBlockedMessage
    )
  }

  private var scenarioDraftCanSave: Bool {
    selectedExperiment != nil
      && !scenarioTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !scenarioCohortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !scenarioTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !scenarioSuccessSignal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !scenarioSegmentID.isEmpty
      && !scenarioWorkflowID.isEmpty
  }

  private var scenarioCanRun: Bool {
    scenarioDraftCanSave
      && selectedScenarioID != nil
      && scenarioEnabled
      && scenarioCohortEnabled
      && contractAvailable == true
      && selectedExperimentMatchesRoundTwoTarget
      && !(scenarioTargetCommit.isEmpty && selectedExperiment?.currentSha == nil
        && selectedExperiment?.baseSha == nil)
  }

  private var personaScenarioCanRun: Bool {
    scenarioCanRun && FoundationModelsAvailability.isAvailable
  }

  private var scenarioCohortCanRun: Bool {
    scenarioDraftCanSave
      && !scenarioCohortID.isEmpty
      && scenarioCohortEnabled
      && contractAvailable == true
      && selectedExperimentMatchesRoundTwoTarget
      && !(scenarioTargetCommit.isEmpty && selectedExperiment?.currentSha == nil
        && selectedExperiment?.baseSha == nil)
  }

  private var personaCohortCanRun: Bool {
    scenarioCohortCanRun && FoundationModelsAvailability.isAvailable
  }

  private var aggregateEvidence: some View {
    WorkbenchSection("Evidence View", systemImage: "chart.bar.xaxis") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          WorkbenchMetric(
            label: "Runs", value: "\(evidenceIndex.summaries.count)", systemImage: "number")
          if let readiness = selectedTournamentReadiness {
            WorkbenchMetric(
              label: "Readiness", value: readiness.scoreLabel,
              systemImage: "chart.line.uptrend.xyaxis")
          }
          WorkbenchMetric(
            label: "Failures",
            value: "\(evidenceIndex.aggregate.failuresByKind.values.reduce(0, +))",
            systemImage: "exclamationmark.triangle"
          )
          WorkbenchMetric(
            label: "Verdicts",
            value: "\(evidenceIndex.aggregate.verdictCounts.count)",
            systemImage: "checklist"
          )
        }
        if let readiness = selectedTournamentReadiness {
          WorkbenchFact(
            label: "Readiness",
            value:
              "\(readiness.recommendation.title), \(readiness.completedRunCount)/\(readiness.runCount) completed, \(readiness.distinctPersonaCount) persona(s)"
          )
          if !readiness.proofDebt.isClear {
            WorkbenchFact(label: "Proof debt", value: readiness.proofDebt.summary)
          }
          ForEach(Array(readiness.rationale.prefix(3).enumerated()), id: \.offset) { _, rationale in
            WorkbenchFact(label: "Why", value: rationale)
          }
        }
        if selectedStaleEvidenceCount > 0 {
          WorkbenchFact(
            label: "Stale evidence",
            value: "\(selectedStaleEvidenceCount) run(s) from older experiment commits ignored"
          )
        }
        if let nextAction = selectedTournamentNextAction {
          WorkbenchFact(label: "Next action", value: nextAction.title)
          WorkbenchFact(
            label: "Action",
            value: "\(nextAction.kind.rawValue), priority \(nextAction.priority)"
          )
          if let targetDecision = nextAction.targetDecision {
            WorkbenchFact(label: "Target decision", value: targetDecision.rawValue)
          }
          if let targetPersonaName = nextAction.targetPersonaName {
            let targetValue =
              nextAction.targetPersonaID.map {
                "\(targetPersonaName) (\($0))"
              } ?? targetPersonaName
            WorkbenchFact(label: "Target simulated user", value: targetValue)
          }
          if let readiness = selectedSuggestedCohortReadiness {
            WorkbenchFact(
              label: "Cohort",
              value:
                "\(readiness.cohortTitle) (\(readiness.enabledScenarioCount) enabled scenario(s))"
            )
            if let blockedReason = readiness.blockedReason {
              WorkbenchFact(label: "Blocked", value: blockedReason)
            }
          }
          if let selectedRoundTwoBlockedMessage {
            WorkbenchFact(label: "Round 2", value: selectedRoundTwoBlockedMessage)
          }
          Text(nextAction.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if nextAction.cohortID != nil {
            HStack(spacing: 8) {
              Button {
                Task { await runSuggestedCohort(mode: .modelFree) }
              } label: {
                Label("Run Suggested Cohort", systemImage: "play.rectangle.on.rectangle")
              }
              .buttonStyle(.bordered)
              .disabled(isRunningScenario || !suggestedCohortCanRun)
              .help(
                selectedRoundTwoBlockedMessage
                  ?? "Run the suggested cohort with model-free simulated users."
              )

              Button {
                Task { await runSuggestedCohort(mode: .personaModel) }
              } label: {
                Label("Persona-Model Suggested Cohort", systemImage: "person.2.wave.2")
              }
              .buttonStyle(.bordered)
              .disabled(
                isRunningScenario || !suggestedCohortCanRun
                  || !FoundationModelsAvailability.isAvailable
              )
              .help(
                selectedRoundTwoBlockedMessage
                  ?? (FoundationModelsAvailability.isAvailable
                    ? "Run the suggested cohort with persona-model simulated users."
                    : ProductTournamentPersonaActionModelError.unavailable.localizedDescription)
              )
            }
          }
        }
        if let objection = evidenceIndex.aggregate.repeatedObjections.first {
          WorkbenchFact(
            label: "Repeated objection", value: "\(objection.objection) (\(objection.count)x)")
        }
        if let rationale = evidenceIndex.aggregate.personaRationaleSignals.first {
          WorkbenchFact(
            label: "simulated-user rationale",
            value: "\(rationale.rationale) (\(rationale.count)x)"
          )
        }
        if let outcome = evidenceIndex.aggregate.decisionIntentOutcomes.first {
          WorkbenchFact(
            label: "Targeted proof",
            value:
              "\(outcome.targetDecision.rawValue) \(outcome.outcome.rawValue) (\(outcome.count)x)"
          )
        }
        if let missing = evidenceIndex.aggregate.missingCapabilityFrequency.first {
          WorkbenchFact(
            label: "Missing capability", value: "\(missing.capabilityID) (\(missing.count)x)")
        }
        if let comparison = evidenceIndex.aggregate.currentAlternativeComparisons.first {
          WorkbenchFact(
            label: "Alternative", value: "\(comparison.comparison) [\(comparison.verdict.rawValue)]"
          )
        }
        if evidenceIndex.malformedRecordCount > 0 {
          Label(
            "\(evidenceIndex.malformedRecordCount) malformed record(s) skipped",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
    }
  }

  private var planEvaluationEvidence: some View {
    WorkbenchSection("Plan Evaluations", systemImage: "doc.text.magnifyingglass") {
      VStack(alignment: .leading, spacing: 8) {
        if planEvaluationsForBoard.isEmpty {
          WorkbenchEmptyLine("No Round 1 plan evaluations recorded yet.")
        } else {
          ForEach(planEvaluationsForBoard.prefix(8)) { summary in
            planEvaluationRow(summary)
          }
        }
      }
    }
  }

  private func planEvaluationRow(
    _ summary: ProductTournamentPlanEvaluationSummary
  ) -> some View {
    Button {
      selectedPlanEvaluationID = summary.evaluationID
      if let experimentID = summary.experimentID {
        selectedExperimentID = experimentID
      }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(summary.personaName)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Spacer()
          WorkbenchStatusPill(text: summary.verdict.rawValue)
        }
        WorkbenchFact(label: "Contender", value: summary.contenderID)
        WorkbenchFact(label: "Round", value: summary.roundID)
        WorkbenchFact(
          label: "Scores",
          value:
            "pain \(score(summary.scores.painRecognition)), workflow \(score(summary.scores.workflowImprovement)), pay \(score(summary.scores.willingnessToPay ?? summary.willingnessToPayScore))"
        )
        if let estimatedMonthlyPriceCents = summary.estimatedMonthlyPriceCents {
          WorkbenchFact(label: "Price", value: priceLabel(cents: estimatedMonthlyPriceCents))
        }
        if let commercialProofSummary = summary.commercialProofSummary {
          WorkbenchFact(label: "Commercial proof", value: commercialProofSummary)
        }
        if let objection = summary.objections.first {
          WorkbenchFact(label: "Objection", value: objection)
        }
        Text(summary.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selectedPlanEvaluationID == summary.evaluationID
          ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
    .buttonStyle(.plain)
    .help(
      summary.currentAlternativeComparison.isEmpty
        ? summary.summary : summary.currentAlternativeComparison)
  }

  @ViewBuilder
  private var selectedPlanEvaluationDetail: some View {
    if let record = selectedPlanEvaluationRecord {
      WorkbenchSection("Selected Plan Evaluation", systemImage: "doc.richtext") {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            WorkbenchMetric(
              label: "Pain", value: score(record.scores.painRecognition), systemImage: "scope")
            WorkbenchMetric(
              label: "Workflow", value: score(record.scores.workflowImprovement),
              systemImage: "flowchart")
            WorkbenchMetric(
              label: "Pay",
              value: score(record.scores.willingnessToPay ?? record.willingnessToPayScore),
              systemImage: "dollarsign.circle"
            )
          }
          HStack(spacing: 6) {
            WorkbenchMetric(
              label: "Alternative", value: score(record.scores.alternativeAdvantage),
              systemImage: "arrow.left.arrow.right")
            WorkbenchMetric(
              label: "Switch", value: score(record.scores.switchingReadiness),
              systemImage: "arrow.triangle.2.circlepath")
            WorkbenchMetric(
              label: "Pull", value: score(record.scores.continuedUsePull),
              systemImage: "repeat")
          }
          WorkbenchFact(label: "Evaluation", value: record.id)
          WorkbenchFact(label: "Persona", value: "\(record.personaName) (\(record.personaID))")
          WorkbenchFact(label: "Tournament", value: record.tournamentID)
          WorkbenchFact(label: "Round", value: record.roundID)
          WorkbenchFact(label: "Contender", value: record.contenderID)
          WorkbenchFact(label: "Hypothesis", value: record.contenderPlanID)
          if let experimentID = record.experimentID {
            WorkbenchFact(label: "Track", value: experimentID)
          }
          WorkbenchFact(label: "Mode", value: record.mode.rawValue)
          WorkbenchFact(label: "Model", value: record.model)
          planEvaluationDetailList(label: "Prompt Versions", values: record.promptVersions)
          if let estimatedMonthlyPriceCents = record.estimatedMonthlyPriceCents {
            WorkbenchFact(label: "Price", value: priceLabel(cents: estimatedMonthlyPriceCents))
          }
          if let commercialProofSummary = record.commercialProofSummary {
            WorkbenchFact(label: "Commercial proof", value: commercialProofSummary)
          }
          if !record.currentAlternativeComparison.isEmpty {
            WorkbenchFact(label: "Alternative", value: record.currentAlternativeComparison)
          }
          planEvaluationDetailList(label: "Strengths", values: record.planStrengths)
          planEvaluationDetailList(label: "Risks", values: record.planRisks)
          planEvaluationDetailList(label: "Objections", values: record.objections)
          planEvaluationDetailList(label: "Missing", values: record.missingCapabilities)
          planEvaluationDetailList(label: "Rationale", values: record.rationale)
          Text(record.summary)
            .font(.callout)
            .textSelection(.enabled)
        }
      }
    } else if let planEvaluationRecordError {
      ContentUnavailableView(
        "Plan Evaluation Unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(planEvaluationRecordError)
      )
    }
  }

  @ViewBuilder
  private func planEvaluationDetailList(label: String, values: [String]) -> some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(Array(values.prefix(5).enumerated()), id: \.offset) { _, value in
          Text("- \(value)")
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  @ViewBuilder
  private var selectedExperimentActions: some View {
    if let experiment = selectedExperiment {
      WorkbenchSection("Promotion And Archive", systemImage: "arrow.up.forward.circle") {
        VStack(alignment: .leading, spacing: 8) {
          Text(experiment.evidenceSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          if let proposal = selectedTournamentDecisionProposal {
            WorkbenchFact(
              label: "Tournament advice",
              value:
                "\(proposal.currentDecision.rawValue) -> \(proposal.update.decision.rawValue)"
            )
            Text(proposal.update.summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button {
              Task {
                await project.applyProductTournamentDecisionRecommendation(
                  experimentID: experiment.id
                )
              }
            } label: {
              Label("Apply Tournament Advice", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
          }
          gitRolloutPreviewBlock(for: experiment)
          HStack(spacing: 8) {
            rolloutButton(.promoteOrConfirm, experiment: experiment)
            rolloutButton(.killOrArchive, experiment: experiment)
          }
        }
      }
    }
  }

  private func rolloutButton(
    _ action: ProductTournamentExperimentRolloutAction,
    experiment: ProductTournamentExperiment
  ) -> some View {
    Button {
      Task {
        await project.applyProductTournamentExperimentRolloutAction(
          action, experimentID: experiment.id)
      }
    } label: {
      Label(
        action.title(from: experiment.decision),
        systemImage: action == .promoteOrConfirm ? "arrow.up.forward" : "archivebox")
    }
    .buttonStyle(.bordered)
    .disabled(!ProductTournamentExperimentRolloutWorkflow.canApply(action, to: experiment))
  }

  @ViewBuilder
  private func gitRolloutPreviewBlock(for experiment: ProductTournamentExperiment) -> some View {
    if experiment.decision == .promote || experiment.decision == .kill {
      VStack(alignment: .leading, spacing: 6) {
        if isLoadingGitPreview {
          WorkbenchEmptyLine("Loading branch delta...")
        } else if let gitPreview {
          WorkbenchFact(
            label: "Accepted",
            value: "\(gitPreview.acceptedBranchName) @ \(short(gitPreview.acceptedBeforeSha))")
          WorkbenchFact(
            label: "Experiment",
            value: "\(gitPreview.experimentBranchName) @ \(short(gitPreview.actualExperimentSha))")
          WorkbenchFact(label: "Operation", value: gitPreview.kind.rawValue)
          if !gitPreview.experimentStateMatchesBranch {
            Label(
              "Recorded experiment sha is stale; refresh before rollout.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          }
          if let archiveBranchName = gitPreview.archiveBranchName, experiment.decision == .kill {
            WorkbenchFact(label: "Archive", value: archiveBranchName)
          }
          if !gitPreview.commitSubjects.isEmpty {
            WorkbenchFact(
              label: "Commits", value: gitPreview.commitSubjects.prefix(3).joined(separator: "; "))
          }
          if !gitPreview.changedFiles.isEmpty {
            WorkbenchFact(
              label: "Files", value: gitPreview.changedFiles.prefix(6).joined(separator: "; "))
          }
        } else if let gitPreviewError {
          Label(gitPreviewError, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          WorkbenchEmptyLine("Branch delta will appear before final rollout.")
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private var evidenceRuns: some View {
    WorkbenchSection("Scenario Runs", systemImage: "list.bullet.rectangle") {
      VStack(alignment: .leading, spacing: 8) {
        if runsForSelectedExperiment.isEmpty {
          WorkbenchEmptyLine("No evidence runs for this experiment commit.")
        } else {
          ForEach(runsForSelectedExperiment) { summary in
            Button {
              selectedRunID = summary.runID
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(summary.runID)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                  Spacer()
                  WorkbenchStatusPill(text: summary.verdict.rawValue)
                }
                Text("\(summary.scenarioID) / \(summary.personaID)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                if let roundID = summary.roundID, let contenderID = summary.contenderID {
                  Text("Tournament \(roundID) / \(contenderID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                if let decisionIntent = summary.decisionIntent {
                  Text(evidenceIntentSummary(summary, intent: decisionIntent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Text("Target \(summary.branchName) @ \(short(summary.commitSha))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                WorkbenchFact(
                  label: "Completed use",
                  value: summary.completedUseProof ? "yes" : "no"
                )
                .accessibilityIdentifier("scenario-run-completed-use-\(summary.runID)")
                Text(summary.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                selectedRunID == summary.runID
                  ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var selectedEvidenceDetail: some View {
    if let record = selectedRecord {
      WorkbenchSection("Selected Run", systemImage: "doc.text.magnifyingglass") {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            WorkbenchMetric(
              label: "Pain", value: score(record.scores.painRecognition), systemImage: "scope")
            WorkbenchMetric(
              label: "Workflow", value: score(record.scores.workflowImprovement),
              systemImage: "flowchart")
            WorkbenchMetric(
              label: "Switch", value: score(record.scores.switchingReadiness),
              systemImage: "arrow.triangle.2.circlepath")
          }
          WorkbenchFact(label: "Scenario", value: record.scenarioID)
          WorkbenchFact(label: "Persona", value: record.personaID)
          WorkbenchFact(label: "Mode", value: record.mode.rawValue)
          WorkbenchFact(label: "Branch", value: record.branchName)
          WorkbenchFact(label: "Commit", value: record.commitSha)
          if let tournamentID = record.tournamentID {
            WorkbenchFact(label: "Tournament", value: tournamentID)
          }
          if let roundID = record.roundID {
            WorkbenchFact(label: "Round", value: roundID)
          }
          if let contenderID = record.contenderID {
            WorkbenchFact(label: "Contender", value: contenderID)
          }
          if let decisionIntent = record.decisionIntent {
            WorkbenchFact(label: "Target decision", value: decisionIntent.targetDecision.rawValue)
            WorkbenchFact(label: "Current decision", value: decisionIntent.currentDecision.rawValue)
            if !decisionIntent.scorecardFocus.isEmpty {
              WorkbenchFact(
                label: "Intent focus",
                value: decisionIntent.scorecardFocus.prefix(5).joined(separator: ", ")
              )
            }
          }
          if let decisionIntentEvaluation = record.decisionIntentEvaluation {
            WorkbenchFact(
              label: "Intent outcome",
              value: decisionIntentEvaluation.outcome.rawValue
            )
            WorkbenchFact(label: "Intent rationale", value: decisionIntentEvaluation.rationale)
          }
          if let revisionCheck = selectedRunActedRevisionValidationRunContext {
            WorkbenchFact(label: "Revision Check", value: revisionCheck.summary)
              .help(revisionCheck.help)
          }
          if let willingnessToPayScore = record.willingnessToPayScore {
            WorkbenchFact(label: "Willingness to pay", value: "\(willingnessToPayScore)/5")
          }
          if !record.sponsorshipIntent.isEmpty {
            WorkbenchFact(label: "Sponsorship", value: record.sponsorshipIntent)
          }
          WorkbenchFact(
            label: "Completed use",
            value: record.completedUseProof ? "yes" : "no"
          )
          .accessibilityIdentifier("selected-run-completed-use")
          WorkbenchFact(label: "Trace", value: record.traceHash ?? "none")
          if !record.objections.isEmpty {
            WorkbenchFact(
              label: "Objections", value: record.objections.prefix(3).joined(separator: "; "))
          }
          if !record.missingCapabilities.isEmpty {
            WorkbenchFact(
              label: "Missing", value: record.missingCapabilities.prefix(4).joined(separator: ", "))
          }
          if !record.currentAlternativeComparison.isEmpty {
            WorkbenchFact(label: "Alternative", value: record.currentAlternativeComparison)
          }
          Text(record.summary)
            .font(.callout)
            .textSelection(.enabled)
          ProductTournamentEvidenceCopyButton(record: record)
        }
      }
    } else if let recordError {
      ContentUnavailableView(
        "Evidence Record Unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(recordError)
      )
    }
  }

  private var decisionTimeline: some View {
    WorkbenchSection("Decision Timeline", systemImage: "timeline.selection") {
      VStack(alignment: .leading, spacing: 8) {
        let decisions = config.decisions.sorted { lhs, rhs in
          if lhs.decidedAt == rhs.decidedAt { return lhs.id < rhs.id }
          return lhs.decidedAt > rhs.decidedAt
        }
        if decisions.isEmpty {
          WorkbenchEmptyLine("No tournament decisions recorded yet.")
        } else {
          ForEach(decisions.prefix(8)) { decision in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline) {
                Text(decision.experimentID)
                  .font(.callout.weight(.semibold))
                  .lineLimit(1)
                Spacer()
                WorkbenchStatusPill(text: decision.decision.rawValue)
              }
              Text(decision.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              if !decision.evidenceRunIDs.isEmpty {
                WorkbenchFact(
                  label: "Evidence", value: decision.evidenceRunIDs.joined(separator: ", "))
              }
              if let branch = decision.branchName {
                WorkbenchFact(label: "Branch", value: branch)
              }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
    }
  }

  private func loadSelectedRecord() {
    guard let selectedRunID else {
      selectedRecord = nil
      recordError = nil
      return
    }
    do {
      selectedRecord = try project.readProductTournamentEvidenceRecord(id: selectedRunID)
      recordError = nil
    } catch {
      selectedRecord = nil
      recordError = error.localizedDescription
    }
  }

  private func loadSelectedPlanEvaluationRecord() {
    guard let selectedPlanEvaluationID else {
      selectedPlanEvaluationRecord = nil
      planEvaluationRecordError = nil
      return
    }
    do {
      selectedPlanEvaluationRecord = try project.readProductTournamentPlanEvaluationRecord(
        id: selectedPlanEvaluationID
      )
      planEvaluationRecordError = nil
    } catch {
      selectedPlanEvaluationRecord = nil
      planEvaluationRecordError = error.localizedDescription
    }
  }

  private func loadGitPreview() async {
    guard let experiment = selectedExperiment,
      experiment.decision == .promote || experiment.decision == .kill
    else {
      gitPreview = nil
      gitPreviewError = nil
      isLoadingGitPreview = false
      return
    }
    isLoadingGitPreview = true
    defer { isLoadingGitPreview = false }
    do {
      gitPreview = try await project.productTournamentExperimentGitRolloutPreview(
        experimentID: experiment.id)
      gitPreviewError = nil
    } catch {
      gitPreview = nil
      gitPreviewError = error.localizedDescription
    }
  }

  private func loadScenarioDraft() {
    guard let experiment = selectedExperiment else {
      selectedScenarioID = nil
      scenarioTitle = ""
      scenarioCohortID = ""
      scenarioCohortTitle = ""
      scenarioCohortEnabled = true
      scenarioTask = ""
      scenarioSuccessSignal = ""
      scenarioSegmentID = ""
      scenarioWorkflowID = ""
      scenarioAlternativeID = ""
      scenarioTargetCommit = ""
      scenarioMaxTurns = 8
      scenarioTimeoutSeconds = 120
      scenarioEnabled = true
      return
    }
    if selectedScenarioID == nil {
      selectedScenarioID = scenariosForSelectedExperiment.first?.id
    }
    if let scenario = scenariosForSelectedExperiment.first(where: { $0.id == selectedScenarioID }) {
      let cohort =
        cohortsForSelectedExperiment.first { $0.scenarioIDs.contains(scenario.id) }
        ?? cohortsForSelectedExperiment.first
      scenarioTitle = scenario.title
      scenarioCohortID = cohort?.id ?? "\(experiment.id)-starter-cohort"
      scenarioCohortTitle = cohort?.title ?? "\(experiment.title) cohort"
      scenarioCohortEnabled = cohort?.enabled ?? true
      scenarioTask = scenario.task
      scenarioSuccessSignal = scenario.successSignal
      scenarioSegmentID = scenario.segmentID
      scenarioWorkflowID = scenario.currentWorkflowID
      scenarioAlternativeID = scenario.alternativeID ?? ""
      scenarioTargetCommit =
        scenario.targetCommitSha ?? experiment.currentSha ?? experiment.baseSha ?? ""
      scenarioMaxTurns = scenario.maxTurns
      scenarioTimeoutSeconds = scenario.appCommandTimeoutSeconds
      scenarioEnabled = scenario.enabled
      return
    }
    let draft = ProductTournamentScenarioCoordinator.defaultDraft(
      for: experiment,
      in: config
    )
    loadScenarioDraftValues(draft)
  }

  private func loadScenarioDraftValues(_ draft: ProductScenarioDraft) {
    selectedScenarioID = draft.id
    scenarioTitle = draft.title
    scenarioCohortID = draft.cohortID ?? ""
    scenarioCohortTitle = draft.cohortTitle
    scenarioCohortEnabled = draft.cohortEnabled
    scenarioTask = draft.task
    scenarioSuccessSignal = draft.successSignal
    scenarioSegmentID = draft.segmentID
    scenarioWorkflowID = draft.currentWorkflowID
    scenarioAlternativeID = draft.alternativeID ?? ""
    scenarioTargetCommit = draft.targetCommitSha ?? ""
    scenarioMaxTurns = draft.maxTurns
    scenarioTimeoutSeconds = draft.appCommandTimeoutSeconds
    scenarioEnabled = draft.enabled
  }

  private func saveScenarioDraft() async {
    guard let experiment = selectedExperiment else { return }
    isSavingScenario = true
    defer { isSavingScenario = false }
    let draft = ProductScenarioDraft(
      id: selectedScenarioID,
      experimentID: experiment.id,
      cohortID: scenarioCohortID.isEmpty ? nil : scenarioCohortID,
      cohortTitle: scenarioCohortTitle,
      cohortEnabled: scenarioCohortEnabled,
      segmentID: scenarioSegmentID,
      currentWorkflowID: scenarioWorkflowID,
      alternativeID: scenarioAlternativeID.isEmpty ? nil : scenarioAlternativeID,
      title: scenarioTitle,
      task: scenarioTask,
      successSignal: scenarioSuccessSignal,
      targetCommitSha: scenarioTargetCommit.isEmpty
        ? (experiment.currentSha ?? experiment.baseSha)
        : scenarioTargetCommit,
      maxTurns: scenarioMaxTurns,
      appCommandTimeoutSeconds: scenarioTimeoutSeconds,
      enabled: scenarioEnabled
    )
    await project.saveProductScenarioDraft(draft)
    selectedScenarioID = draft.id
    scenarioRunMessage = "Scenario saved."
    await loadContractStatus()
  }

  private func applyRevisionBrief(_ brief: TournamentAutomationRevisionBrief) async {
    isSavingScenario = true
    defer { isSavingScenario = false }
    let startedAt = Date()
    do {
      let draft = try ProductTournamentScenarioCoordinator.revisionDraft(
        for: brief,
        in: project.productTournamentConfig
      )
      selectedExperimentID = draft.experimentID
      loadScenarioDraftValues(draft)
      await project.saveProductScenarioDraft(draft)
      guard let scenarioID = draft.id,
        project.productTournamentConfig.scenarios.contains(where: { $0.id == scenarioID })
      else {
        scenarioRunMessage = project.errorMessage ?? "Revision scenario could not be saved."
        return
      }
      selectedScenarioID = scenarioID
      let targetedProofOutcomeSummaries =
        tournamentAutomationTargetedProofOutcomeSignal(forExperimentID: brief.experimentID)
        .map { [$0.auditSummary] } ?? []
      let audit = appliedRevisionAudit(
        for: brief,
        scenarioID: scenarioID,
        startedAt: startedAt,
        idPrefix: "tournament-cycle-manual-revision",
        targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
        stopDetail: "Manual contender revision applied; run targeted validation evidence next.",
        userMessage:
          "Applied contender revision for \(brief.experimentID). Run targeted validation evidence next."
      )
      scenarioRunMessage = audit.userMessage
      await project.saveProductTournamentConfig(
        project.productTournamentConfig.recordingTournamentAutomationCycleAudit(audit)
      )
      await loadContractStatus()
    } catch {
      scenarioRunMessage = error.localizedDescription
    }
  }

  private func appliedRevisionAudit(
    for brief: TournamentAutomationRevisionBrief,
    scenarioID: String,
    startedAt: Date,
    idPrefix: String,
    targetedProofOutcomeSummaries: [String] = [],
    stopDetail: String,
    userMessage: String
  ) -> TournamentAutomationCycleAudit {
    let started = startedAt.timeIntervalSince1970
    let ended = Date().timeIntervalSince1970
    let stepID =
      "\(brief.experimentID):\(TournamentAutomationStepKind.applyRevision.rawValue):\(scenarioID)"
    return TournamentAutomationCycleAudit(
      id: "\(idPrefix)-\(brief.experimentID)-\(Int(started))-\(scenarioID)",
      startedAt: started,
      endedAt: ended,
      executedStepIDs: [stepID],
      experimentIDs: [brief.experimentID],
      messages: [
        "Applied contender revision \(brief.title) to scenario \(scenarioID)."
      ],
      maxSteps: 1,
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      revisionBriefSummaries: [brief.auditSummary],
      stopReason: .reachedStepLimit,
      stopStepID: stepID,
      stopStepTitle: "Apply contender revision",
      stopDetail: stopDetail,
      userMessage: userMessage
    )
  }

  private func runScenarioModelFree() async {
    await runScenario(mode: .modelFree)
  }

  private func runScenarioPersonaModel() async {
    await runScenario(mode: .personaModel)
  }

  private func runScenarioCohortModelFree() async {
    await runScenarioCohort(mode: .modelFree)
  }

  private func runScenarioCohortPersonaModel() async {
    await runScenarioCohort(mode: .personaModel)
  }

  private func runSuggestedCohort(mode: ProductTournamentSimulationMode) async {
    guard let action = selectedTournamentNextAction,
      let cohortID = action.cohortID
    else { return }
    if let targetScenarioID = action.targetScenarioID {
      await runScenario(
        mode: mode,
        scenarioID: targetScenarioID,
        saveDraftFirst: false,
        targetDecision: action.targetDecision
      )
      return
    }
    await runScenarioCohort(
      mode: mode,
      cohortID: cohortID,
      saveDraftFirst: false,
      targetDecision: action.targetDecision
    )
  }

  private func runTournamentAutomationStep(
    _ explicitStep: TournamentAutomationStep? = nil,
    groupAnchorRowID: String? = nil,
    actedPressureGroupSummary: String? = nil
  ) async {
    guard let step = explicitStep ?? tournamentAutomationStep, step.canExecute else { return }
    selectedProofScoreboardGroupAnchorRowID = groupAnchorRowID
    if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: step.experimentID) {
      selectedExperimentID = step.experimentID
      scenarioRunMessage = blockedMessage
      return
    }
    selectedExperimentID = step.experimentID
    isRunningTournamentStep = true
    defer { isRunningTournamentStep = false }
    let stepStartedAt = Date()
    let startingProofDebtSnapshot = TournamentAutomationProofDebtSnapshotter.snapshot(
      experimentIDs: [step.experimentID],
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      preferredSteps: [step.experimentID: step]
    )
    let decisionCandidateSummaries =
      tournamentAutomationDecisionCandidate(forExperimentID: step.experimentID)
      .map { [$0.auditSummary] } ?? []
    let evidenceTensionSummaries =
      tournamentAutomationEvidenceTension(forExperimentID: step.experimentID)
      .map { [$0.auditSummary] } ?? []
    let proofTargetSummaries =
      tournamentAutomationProofTarget(forExperimentID: step.experimentID)
      .map { [$0.auditSummary] } ?? []
    let targetedProofOutcomeSummaries =
      tournamentAutomationTargetedProofOutcomeSignal(forExperimentID: step.experimentID)
      .map { [$0.auditSummary] } ?? []
    let revisionBriefSummaries =
      step.kind == .applyRevision
      ? tournamentAutomationRevisionBrief(forExperimentID: step.experimentID).map {
        [$0.auditSummary]
      }
        ?? []
      : []
    let personaRationaleSignalSummaries: [String]
    if let stepExperiment = project.productTournamentConfig.tournamentExperiments.first(where: {
      $0.id == step.experimentID
    }),
      let rationaleSignal = TournamentAutomationRationaleSignalAdvisor.signal(
        for: stepExperiment,
        config: project.productTournamentConfig,
        evidenceIndex: project.productTournamentEvidenceIndex
      )
    {
      personaRationaleSignalSummaries = [rationaleSignal.auditSummary]
    } else {
      personaRationaleSignalSummaries = []
    }
    let result = await executeTournamentAutomationStep(step)
    let endingProofDebtSnapshot = TournamentAutomationProofDebtSnapshotter.snapshot(
      experimentIDs: [step.experimentID],
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      preferredSteps: [step.experimentID: step]
    )
    let stopReason: TournamentAutomationCycleStopReason =
      result == nil
      ? .executionFailed(
        stepID: step.id,
        title: step.title,
        message: project.errorMessage ?? step.blockedReason
      )
      : .reachedStepLimit
    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: result == nil ? [] : [step],
      executedStepIDs: result.map { [$0.executedStepID ?? step.id] } ?? [],
      messages: result.map { [$0.message] } ?? [],
      maxSteps: 1,
      stopReason: stopReason,
      evidenceRunIDs: result?.evidenceRunIDs ?? [],
      completedEvidenceRunCount: result?.completedEvidenceRunCount ?? 0,
      failedEvidenceRunCount: result?.failedEvidenceRunCount ?? 0,
      skippedScenarioCount: result?.skippedScenarioCount ?? 0,
      startingProofDebtCount: startingProofDebtSnapshot?.count,
      endingProofDebtCount: endingProofDebtSnapshot?.count,
      startingProofDebtSummary: startingProofDebtSnapshot?.summary,
      endingProofDebtSummary: endingProofDebtSnapshot?.summary,
      startingPersonaModelPlanEvaluationCount: startingProofDebtSnapshot?
        .personaModelPlanEvaluationCount,
      endingPersonaModelPlanEvaluationCount: endingProofDebtSnapshot?
        .personaModelPlanEvaluationCount,
      startingModelFreePlanEvaluationCount: startingProofDebtSnapshot?.modelFreePlanEvaluationCount,
      endingModelFreePlanEvaluationCount: endingProofDebtSnapshot?.modelFreePlanEvaluationCount,
      decisionCandidateSummaries: decisionCandidateSummaries,
      evidenceTensionSummaries: evidenceTensionSummaries,
      proofTargetSummaries: proofTargetSummaries,
      actedProofPressureGroupSummaries: actedPressureGroupSummary.map { [$0] } ?? [],
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      personaRationaleSignalSummaries: personaRationaleSignalSummaries,
      revisionBriefSummaries: revisionBriefSummaries
    )
    let audit = outcome.audit(startedAt: stepStartedAt)
    scenarioRunMessage = result?.message ?? project.errorMessage ?? step.blockedReason
    await project.saveProductTournamentConfig(
      project.productTournamentConfig.recordingTournamentAutomationCycleAudit(audit)
    )
    focusProofTarget(after: audit, preferredStep: step)
    await loadContractStatus()
  }

  private func runTournamentAutomationCycle() async {
    guard tournamentAutomationCyclePlan.canRun else { return }
    isRunningTournamentAutomationCycle = true
    defer { isRunningTournamentAutomationCycle = false }
    let cycleStartedAt = Date()
    let maxSteps = tournamentAutomationCyclePlan.maxSteps
    var executedSteps: [TournamentAutomationStep] = []
    var messages: [String] = []
    var evidenceRunIDs: [String] = []
    var completedEvidenceRunCount = 0
    var failedEvidenceRunCount = 0
    var skippedScenarioCount = 0
    var touchedExperimentIDs: [String] = []
    var touchedStepsByExperiment: [String: TournamentAutomationStep] = [:]
    var startingProofDebtSnapshots: [String: TournamentAutomationProofDebtSnapshot] = [:]
    var decisionCandidateSummaries: [String] = []
    var evidenceTensionSummaries: [String] = []
    var proofTargetSummaries: [String] = []
    var executedStepIDs: [String] = []
    var targetedProofOutcomeSummaries = TournamentAutomationTargetedProofOutcomeAdvisor.signals(
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
    .prefix(3)
    .map(\.auditSummary)
    var revisionBriefSummaries: [String] = []
    var personaRationaleSignalSummaries = TournamentAutomationRationaleSignalAdvisor.signals(
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
    .prefix(3)
    .map(\.auditSummary)
    var seenStepIDs = Set<String>()
    var stopReason: TournamentAutomationCycleStopReason = .reachedStepLimit
    for _ in 0..<maxSteps {
      guard
        let step = TournamentAutomationPlanner.nextExecutableStep(
          config: project.productTournamentConfig,
          evidenceIndex: project.productTournamentEvidenceIndex,
          isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
        )
      else {
        stopReason = .noExecutableStep
        break
      }
      guard seenStepIDs.insert(step.id).inserted else {
        stopReason = .repeatedStep(stepID: step.id, title: step.title)
        break
      }
      if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: step.experimentID) {
        stopReason = .executionFailed(
          stepID: step.id,
          title: step.title,
          message: blockedMessage
        )
        break
      }
      selectedExperimentID = step.experimentID
      if !touchedExperimentIDs.contains(step.experimentID) {
        touchedExperimentIDs.append(step.experimentID)
      }
      if touchedStepsByExperiment[step.experimentID] == nil {
        touchedStepsByExperiment[step.experimentID] = step
      }
      if startingProofDebtSnapshots[step.experimentID] == nil {
        startingProofDebtSnapshots[step.experimentID] =
          TournamentAutomationProofDebtSnapshotter
          .snapshot(
            experimentIDs: [step.experimentID],
            config: project.productTournamentConfig,
            evidenceIndex: project.productTournamentEvidenceIndex,
            preferredSteps: [step.experimentID: step]
          )
      }
      if step.action.kind == .applyDecision,
        let candidate = tournamentAutomationDecisionCandidate(forExperimentID: step.experimentID),
        !decisionCandidateSummaries.contains(candidate.auditSummary)
      {
        decisionCandidateSummaries.append(candidate.auditSummary)
      }
      if let evidenceTension = tournamentAutomationEvidenceTension(
        forExperimentID: step.experimentID),
        !evidenceTensionSummaries.contains(evidenceTension.auditSummary)
      {
        evidenceTensionSummaries.append(evidenceTension.auditSummary)
      }
      if let proofTarget = tournamentAutomationProofTarget(forExperimentID: step.experimentID),
        !proofTargetSummaries.contains(proofTarget.auditSummary)
      {
        proofTargetSummaries.append(proofTarget.auditSummary)
      }
      if let targetedProofOutcome = tournamentAutomationTargetedProofOutcomeSignal(
        forExperimentID: step.experimentID
      ),
        !targetedProofOutcomeSummaries.contains(targetedProofOutcome.auditSummary)
      {
        targetedProofOutcomeSummaries.append(targetedProofOutcome.auditSummary)
      }
      let stepRevisionBrief =
        step.kind == .applyRevision
        ? tournamentAutomationRevisionBrief(forExperimentID: step.experimentID)
        : nil
      if let revisionBrief = stepRevisionBrief,
        !revisionBriefSummaries.contains(revisionBrief.auditSummary)
      {
        revisionBriefSummaries.append(revisionBrief.auditSummary)
      }
      if let stepExperiment = project.productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == step.experimentID
      }),
        let rationaleSignal = TournamentAutomationRationaleSignalAdvisor.signal(
          for: stepExperiment,
          config: project.productTournamentConfig,
          evidenceIndex: project.productTournamentEvidenceIndex
        ),
        !personaRationaleSignalSummaries.contains(rationaleSignal.auditSummary)
      {
        personaRationaleSignalSummaries.append(rationaleSignal.auditSummary)
      }
      guard let result = await executeTournamentAutomationStep(step) else {
        stopReason = .executionFailed(
          stepID: step.id,
          title: step.title,
          message: project.errorMessage ?? step.blockedReason
        )
        break
      }
      executedSteps.append(step)
      executedStepIDs.append(result.executedStepID ?? step.id)
      messages.append(result.message)
      evidenceRunIDs.append(contentsOf: result.evidenceRunIDs)
      completedEvidenceRunCount += result.completedEvidenceRunCount
      failedEvidenceRunCount += result.failedEvidenceRunCount
      skippedScenarioCount += result.skippedScenarioCount
      if let stepRevisionBrief,
        let scenarioID =
          result.targetScenarioID ?? step.targetScenarioID ?? stepRevisionBrief.targetScenarioID
      {
        let checkpoint = appliedRevisionAudit(
          for: stepRevisionBrief,
          scenarioID: scenarioID,
          startedAt: Date(),
          idPrefix: "tournament-cycle-revision-checkpoint",
          targetedProofOutcomeSummaries:
            tournamentAutomationTargetedProofOutcomeSignal(
              forExperimentID: stepRevisionBrief.experimentID
            )
            .map { [$0.auditSummary] } ?? [],
          stopDetail:
            "Contender revision checkpoint recorded; continue with targeted validation evidence.",
          userMessage:
            "Contender revision checkpoint recorded for \(stepRevisionBrief.experimentID). Continuing with targeted validation evidence."
        )
        await project.saveProductTournamentConfig(
          project.productTournamentConfig.recordingTournamentAutomationCycleAudit(checkpoint)
        )
      }
    }
    let startingProofDebt = TournamentAutomationProofDebtSnapshotter.snapshot(
      experimentIDs: touchedExperimentIDs,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      storedSnapshots: startingProofDebtSnapshots,
      preferredSteps: touchedStepsByExperiment
    )
    let endingProofDebt = TournamentAutomationProofDebtSnapshotter.snapshot(
      experimentIDs: touchedExperimentIDs,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      preferredSteps: touchedStepsByExperiment
    )
    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: executedSteps,
      executedStepIDs: executedStepIDs,
      messages: messages,
      maxSteps: maxSteps,
      stopReason: stopReason,
      evidenceRunIDs: evidenceRunIDs,
      completedEvidenceRunCount: completedEvidenceRunCount,
      failedEvidenceRunCount: failedEvidenceRunCount,
      skippedScenarioCount: skippedScenarioCount,
      startingProofDebtCount: startingProofDebt?.count,
      endingProofDebtCount: endingProofDebt?.count,
      startingProofDebtSummary: startingProofDebt?.summary,
      endingProofDebtSummary: endingProofDebt?.summary,
      startingPersonaModelPlanEvaluationCount: startingProofDebt?
        .personaModelPlanEvaluationCount,
      endingPersonaModelPlanEvaluationCount: endingProofDebt?.personaModelPlanEvaluationCount,
      startingModelFreePlanEvaluationCount: startingProofDebt?.modelFreePlanEvaluationCount,
      endingModelFreePlanEvaluationCount: endingProofDebt?.modelFreePlanEvaluationCount,
      decisionCandidateSummaries: decisionCandidateSummaries,
      evidenceTensionSummaries: evidenceTensionSummaries,
      proofTargetSummaries: proofTargetSummaries,
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      personaRationaleSignalSummaries: personaRationaleSignalSummaries,
      revisionBriefSummaries: revisionBriefSummaries
    )
    let audit = outcome.audit(startedAt: cycleStartedAt)
    scenarioRunMessage = audit.userMessage
    await project.saveProductTournamentConfig(
      project.productTournamentConfig.recordingTournamentAutomationCycleAudit(audit)
    )
    focusProofTarget(after: audit, preferredStep: executedSteps.last)
    await loadContractStatus()
  }

  private func tournamentAutomationProofTarget(
    forExperimentID experimentID: String
  ) -> TournamentAutomationProofTarget? {
    guard
      let experiment = project.productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationProofTargetAdvisor.target(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
  }

  private func transitionScopeLabel(for step: TournamentAutomationStep) -> String {
    let round = step.roundID.map { "round \($0)" } ?? "round unknown"
    let contender = step.contenderID.map { "contender \($0)" } ?? "contender unknown"
    if let tournamentID = step.tournamentID {
      return "\(round), \(contender), tournament \(tournamentID)"
    }
    return "\(round), \(contender)"
  }

  private func tournamentAutomationDecisionCandidate(
    forExperimentID experimentID: String
  ) -> TournamentAutomationDecisionCandidate? {
    TournamentAutomationDecisionCandidateAdvisor.candidates(
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
    .first { $0.experimentID == experimentID }
  }

  private func tournamentAutomationEvidenceTension(
    forExperimentID experimentID: String
  ) -> TournamentAutomationEvidenceTension? {
    guard
      let experiment = project.productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationEvidenceTensionAdvisor.tension(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
  }

  private func tournamentAutomationTargetedProofOutcomeSignal(
    forExperimentID experimentID: String
  ) -> TournamentAutomationTargetedProofOutcomeSignal? {
    guard
      let experiment = project.productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationTargetedProofOutcomeAdvisor.signal(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
  }

  private func tournamentAutomationRevisionBrief(
    forExperimentID experimentID: String
  ) -> TournamentAutomationRevisionBrief? {
    guard
      let experiment = project.productTournamentConfig.tournamentExperiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationRevisionBriefAdvisor.brief(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
  }

  private func executeTournamentAutomationStep(
    _ step: TournamentAutomationStep
  ) async -> TournamentAutomationStepResult? {
    switch step.kind {
    case .applyDecision:
      let decisionCount = project.productTournamentConfig.decisions.count
      await project.applyProductTournamentDecisionRecommendation(experimentID: step.experimentID)
      if project.productTournamentConfig.decisions.count > decisionCount {
        return TournamentAutomationStepResult(
          message: "Applied tournament advice for \(step.experimentTitle)."
        )
      }
      return nil
    case .applyRoundTransition:
      do {
        guard let workspace = project.workspace else {
          project.fail(AppModelError.noRepositorySelected)
          return nil
        }
        let result = try await ProductTournamentEngine(workspace: workspace).apply(
          .applyRoundTransition(
            tournamentID: step.tournamentID,
            roundID: step.roundID,
            contenderID: step.contenderID
          )
        )
        project.productTournamentConfig = result.config
        project.productTournamentEvidenceIndex =
          result.evidenceIndex ?? workspace.readProductTournamentEvidenceIndex()
        project.log(result.message, level: .success)
        return TournamentAutomationStepResult(message: result.message)
      } catch {
        project.fail(error)
        return nil
      }
    case .prepareWorktree:
      do {
        guard let workspace = project.workspace else {
          project.fail(AppModelError.noRepositorySelected)
          return nil
        }
        let outcome = try await TournamentAutomationPrepareWorktreeStepExecutor.run(
          step,
          in: workspace
        )
        project.productTournamentConfig = outcome.config
        project.productTournamentEvidenceIndex = workspace.readProductTournamentEvidenceIndex()
        loadScenarioDraft()
        project.log(outcome.userMessage, level: .success)
        return TournamentAutomationStepResult(message: outcome.userMessage)
      } catch {
        project.fail(error)
        return nil
      }
    case .runPlanProof:
      do {
        guard let workspace = project.workspace else {
          project.fail(AppModelError.noRepositorySelected)
          return nil
        }
        let outcome = try await TournamentAutomationPlanProofStepExecutor.runAutomation(
          step,
          in: workspace,
          projectID: project.id
        )
        project.productTournamentConfig = try workspace.readProductTournamentConfig()
        project.productTournamentEvidenceIndex = workspace.readProductTournamentEvidenceIndex()
        project.log(outcome.userMessage, level: outcome.isSuccess ? .success : .warning)
        if let latestRecordID = outcome.latestRecordID {
          selectedPlanEvaluationID = latestRecordID
          loadSelectedPlanEvaluationRecord()
        }
        return TournamentAutomationStepResult(
          message: outcome.userMessage,
          evidenceRunIDs: outcome.records.map(\.id),
          completedEvidenceRunCount: outcome.completedEvaluationCount,
          failedEvidenceRunCount: outcome.records.count - outcome.completedEvaluationCount,
          skippedScenarioCount: outcome.skippedContenderIDs.count
        )
      } catch {
        project.fail(error)
        return nil
      }
    case .runCohort:
      guard let cohortID = step.cohortID else { return nil }
      if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: step.experimentID) {
        scenarioRunMessage = blockedMessage
        return nil
      }
      guard
        step.action.requiredSimulationMode != .personaModel
          || FoundationModelsAvailability.isAvailable
      else { return nil }
      let mode =
        step.action.requiredSimulationMode
        ?? TournamentAutomationPlanner.cohortSimulationMode(
          isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
        )
      let outcome: ProductTournamentScenarioCohortRunOutcome?
      if let targetScenarioID = step.targetScenarioID {
        let scenarioOutcome: ProductTournamentScenarioRunOutcome?
        switch mode {
        case .modelFree:
          scenarioOutcome = await project.runProductTournamentScenarioModelFree(
            experimentID: step.experimentID,
            scenarioID: targetScenarioID,
            targetDecision: step.action.targetDecision
          )
        case .personaModel:
          scenarioOutcome = await project.runProductTournamentScenarioPersonaModel(
            experimentID: step.experimentID,
            scenarioID: targetScenarioID,
            targetDecision: step.action.targetDecision
          )
        case .marketPressure:
          scenarioRunMessage = "Market-pressure evaluations run from market pressure court evidence."
          return nil
        }
        if let scenarioOutcome {
          selectedRunID = scenarioOutcome.record.id
          loadSelectedRecord()
          return TournamentAutomationStepResult(
            message: "\(scenarioOutcome.userMessage) Run \(scenarioOutcome.record.id).",
            evidenceRunIDs: [scenarioOutcome.record.id],
            completedEvidenceRunCount: scenarioOutcome.result.isSuccess ? 1 : 0,
            failedEvidenceRunCount: scenarioOutcome.result.isSuccess ? 0 : 1
          )
        }
        return nil
      }
      switch mode {
      case .modelFree:
        outcome = await project.runProductTournamentScenarioCohortModelFree(
          experimentID: step.experimentID,
          cohortID: cohortID,
          targetDecision: step.action.targetDecision
        )
      case .personaModel:
        outcome = await project.runProductTournamentScenarioCohortPersonaModel(
          experimentID: step.experimentID,
          cohortID: cohortID,
          targetDecision: step.action.targetDecision
        )
      case .marketPressure:
        scenarioRunMessage = "Market-pressure evaluations run from market pressure court evidence."
        return nil
      }
      if let outcome {
        if let latestRecordID = outcome.latestRecordID {
          selectedRunID = latestRecordID
          loadSelectedRecord()
        }
        return TournamentAutomationStepResult(
          message: outcome.userMessage,
          evidenceRunIDs: outcome.outcomes.map(\.record.id),
          completedEvidenceRunCount: outcome.completedRunCount,
          failedEvidenceRunCount: outcome.failedRunCount,
          skippedScenarioCount: outcome.skippedScenarioIDs.count
        )
      }
      return nil
    case .applyRevision:
      guard let brief = tournamentAutomationRevisionBrief(forExperimentID: step.experimentID) else {
        return nil
      }
      do {
        let draft = try ProductTournamentScenarioCoordinator.revisionDraft(
          for: brief,
          in: project.productTournamentConfig
        )
        selectedExperimentID = draft.experimentID
        loadScenarioDraftValues(draft)
        await project.saveProductScenarioDraft(draft)
        guard let scenarioID = draft.id,
          project.productTournamentConfig.scenarios.contains(where: { $0.id == scenarioID })
        else {
          return nil
        }
        selectedScenarioID = scenarioID
        await loadContractStatus()
        return TournamentAutomationStepResult(
          message:
            "Applied contender revision for \(step.experimentTitle): \(brief.title) to scenario \(scenarioID).",
          executedStepID:
            "\(step.experimentID):\(TournamentAutomationStepKind.applyRevision.rawValue):\(scenarioID)",
          targetScenarioID: scenarioID
        )
      } catch {
        project.fail(error)
        return nil
      }
    case .blocked:
      return nil
    }
  }

  private func runScenario(
    mode: ProductTournamentSimulationMode,
    scenarioID: String? = nil,
    saveDraftFirst: Bool = true,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) async {
    guard let experiment = selectedExperiment,
      let targetScenarioID = scenarioID ?? selectedScenarioID
    else { return }
    if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: experiment.id) {
      scenarioRunMessage = blockedMessage
      return
    }
    if saveDraftFirst && scenarioDraftCanSave {
      await saveScenarioDraft()
    }
    isRunningScenario = true
    defer { isRunningScenario = false }
    let outcome: ProductTournamentScenarioRunOutcome?
    switch mode {
    case .modelFree:
      outcome = await project.runProductTournamentScenarioModelFree(
        experimentID: experiment.id,
        scenarioID: targetScenarioID,
        targetDecision: targetDecision
      )
    case .personaModel:
      outcome = await project.runProductTournamentScenarioPersonaModel(
        experimentID: experiment.id,
        scenarioID: targetScenarioID,
        targetDecision: targetDecision
      )
    case .marketPressure:
      scenarioRunMessage = "Market-pressure evaluations run from market pressure court evidence."
      return
    }
    if let outcome {
      scenarioRunMessage = "\(outcome.userMessage) Run \(outcome.record.id)."
      selectedRunID = outcome.record.id
      loadSelectedRecord()
    } else {
      scenarioRunMessage = project.errorMessage
    }
    await loadContractStatus()
  }

  private func runScenarioCohort(
    mode: ProductTournamentSimulationMode,
    cohortID: String? = nil,
    saveDraftFirst: Bool = true,
    targetDecision: ProductTournamentExperimentDecision? = nil
  ) async {
    guard let experiment = selectedExperiment,
      !(cohortID ?? scenarioCohortID).isEmpty
    else { return }
    if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: experiment.id) {
      scenarioRunMessage = blockedMessage
      return
    }
    let targetCohortID = cohortID ?? scenarioCohortID
    if saveDraftFirst && scenarioDraftCanSave {
      await saveScenarioDraft()
    }
    isRunningScenario = true
    defer { isRunningScenario = false }
    let outcome: ProductTournamentScenarioCohortRunOutcome?
    switch mode {
    case .modelFree:
      outcome = await project.runProductTournamentScenarioCohortModelFree(
        experimentID: experiment.id,
        cohortID: targetCohortID,
        targetDecision: targetDecision
      )
    case .personaModel:
      outcome = await project.runProductTournamentScenarioCohortPersonaModel(
        experimentID: experiment.id,
        cohortID: targetCohortID,
        targetDecision: targetDecision
      )
    case .marketPressure:
      scenarioRunMessage = "Market-pressure evaluations run from market pressure court evidence."
      return
    }
    if let outcome {
      scenarioRunMessage = outcome.userMessage
      if let latestRecordID = outcome.latestRecordID {
        selectedRunID = latestRecordID
        loadSelectedRecord()
      }
    } else {
      scenarioRunMessage = project.errorMessage
    }
    await loadContractStatus()
  }

  private func runPlanEvaluationRound(
    contenderID: String?,
    mode: ProductTournamentSimulationMode
  ) async {
    guard let tournament = activeTournamentForPlanEvaluation,
      let round = activePlanRoundForEvaluation
    else { return }
    isRunningPlanEvaluation = true
    runningPlanEvaluationContenderID = contenderID
    defer {
      isRunningPlanEvaluation = false
      runningPlanEvaluationContenderID = nil
    }
    let outcome: ProductTournamentPlanEvaluationOutcome?
    switch mode {
    case .modelFree:
      outcome = await project.runProductTournamentPlanRoundModelFree(
        tournamentID: tournament.id,
        roundID: round.id,
        contenderID: contenderID
      )
    case .personaModel:
      outcome = await project.runProductTournamentPlanRoundPersonaModel(
        tournamentID: tournament.id,
        roundID: round.id,
        contenderID: contenderID
      )
    case .marketPressure:
      planEvaluationMessage = "Market-pressure evaluations run from market pressure court evidence."
      return
    }
    if let outcome {
      planEvaluationMessage = outcome.userMessage
      if let latestRecordID = outcome.latestRecordID {
        selectedPlanEvaluationID = latestRecordID
        loadSelectedPlanEvaluationRecord()
      }
    } else {
      planEvaluationMessage = project.errorMessage
    }
  }

  private func applyPlanTransition() async {
    guard let tournament = activeTournamentForPlanEvaluation,
      let round = activePlanRoundForEvaluation
    else { return }
    isApplyingPlanTransition = true
    defer { isApplyingPlanTransition = false }
    let outcome = await project.applyBestProductTournamentPlanTransition(
      tournamentID: tournament.id,
      roundID: round.id
    )
    if let outcome {
      planTransitionMessage = outcome.userMessage
    } else {
      planTransitionMessage = project.errorMessage
    }
  }

  private func applyRoundEvidenceTransition() async {
    guard let tournament = activeTournamentForRoundEvidence,
      let round = activeCoreTechnologyRoundForEvidence
    else { return }
    isApplyingRoundEvidenceTransition = true
    defer { isApplyingRoundEvidenceTransition = false }
    let outcome = await project.applyBestProductTournamentRoundEvidenceTransition(
      tournamentID: tournament.id,
      roundID: round.id
    )
    if let outcome {
      roundEvidenceTransitionMessage = outcome.userMessage
    } else {
      roundEvidenceTransitionMessage = project.errorMessage
    }
  }

  private func applyProductImplementationEvidenceTransition() async {
    guard let tournament = activeTournamentForRoundEvidence,
      let round = activeProductImplementationRoundForEvidence
    else { return }
    isApplyingProductImplementationEvidenceTransition = true
    defer { isApplyingProductImplementationEvidenceTransition = false }
    let outcome = await project.applyBestProductTournamentProductImplementationEvidenceTransition(
      tournamentID: tournament.id,
      roundID: round.id
    )
    if let outcome {
      productImplementationEvidenceTransitionMessage = outcome.userMessage
    } else {
      productImplementationEvidenceTransitionMessage = project.errorMessage
    }
  }

  private func loadContractStatus() async {
    guard let experiment = selectedExperiment else {
      contractAvailable = nil
      return
    }
    contractAvailable = await project.productTournamentScenarioContractAvailable(
      experimentID: experiment.id
    )
  }

  private func roundTwoLaunchBlockedMessage(experimentID: String) -> String? {
    guard
      let target = ProductTournamentRoundImplementationTargetResolver.roundTwoTarget(
        forExperimentInTargetTournament: experimentID,
        in: config
      ),
      target.experimentID != experimentID
    else { return nil }

    return
      "Round 2 evidence is locked to \(roundTwoTargetExperimentTitle(target)) (\(target.experimentID)) for contender \(roundTwoTargetContenderTitle(target))."
  }

  private func roundTwoTargetExperimentTitle(
    _ target: ProductTournamentRoundImplementationTarget
  ) -> String {
    config.tournamentExperiments.first { $0.id == target.experimentID }?.title
      ?? target.experimentID
  }

  private func roundTwoTargetContenderTitle(
    _ target: ProductTournamentRoundImplementationTarget
  ) -> String {
    config.tournamentContenders.first { $0.id == target.contenderID }?.title ?? target.contenderID
  }

  private func selectCockpitContender(_ lane: ContenderLane) {
    if let row =
      tournamentAutomationProofTargetScoreboard
      .flatMap(\.rows)
      .first(where: { $0.contenderID == lane.id })
    {
      selectProofScoreboardRow(row)
      return
    }

    if let experimentID = lane.auditReferences.first(where: { $0.kind == .experiment })?.value {
      selectedExperimentID = experimentID
    }
    if let planEvaluationID = lane.proofDebt.auditReferences.first(where: {
      $0.kind == .planEvaluation
    })?.value {
      selectedPlanEvaluationID = planEvaluationID
      loadSelectedPlanEvaluationRecord()
    }
    if let scenarioID = lane.auditReferences.first(where: { $0.kind == .scenario })?.value {
      selectedScenarioID = scenarioID
    }
    loadScenarioDraft()
  }

  private func selectCockpitEvidence(_ lane: ContenderLane, signal: EvidenceSignal) {
    selectCockpitContender(lane)
    if let planEvaluationID = signal.sourceAuditReferences.first(where: {
      $0.kind == .planEvaluation
    })?.value {
      selectedPlanEvaluationID = planEvaluationID
      loadSelectedPlanEvaluationRecord()
    }
    if let evidenceRunID = signal.sourceAuditReferences.first(where: {
      $0.kind == .evidenceRun
    })?.value {
      selectedRunID = evidenceRunID
      if let summary = evidenceIndex.summaries.first(where: { $0.runID == evidenceRunID }) {
        selectedScenarioID = summary.scenarioID
      }
      loadSelectedRecord()
    }
  }

  private func selectNextMoveAudit() {
    guard let step = tournamentAutomationStep else { return }
    if let row =
      tournamentAutomationProofTargetScoreboard
      .flatMap(\.rows)
      .first(where: { $0.experimentID == step.experimentID })
    {
      selectProofScoreboardRow(row)
      return
    }
    selectedExperimentID = step.experimentID
  }

  private func selectProofScoreboardRow(
    _ row: TournamentAutomationProofTargetScoreboardRow,
    preserveGroupSelection: Bool = false
  ) {
    let experimentChanged = selectedExperimentID != row.experimentID
    if !preserveGroupSelection {
      selectedProofScoreboardGroupAnchorRowID = nil
    }
    selectedProofScoreboardRowID = row.selectionID
    selectedExperimentID = row.experimentID

    if let targetScenarioID = row.targetScenarioID {
      selectedScenarioID = targetScenarioID
    }

    if let evidenceRunID = TournamentAutomationProofTargetScoreboard.firstKnownEvidenceRunID(
      for: row,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      selectedRunID = evidenceRunID
      if row.targetScenarioID == nil,
        let summary = evidenceIndex.summaries.first(where: { $0.runID == evidenceRunID })
      {
        selectedScenarioID = summary.scenarioID
      }
      loadSelectedRecord()
    } else if !experimentChanged {
      selectedRunID = nil
      loadSelectedRecord()
    }

    if let planEvaluationID =
      TournamentAutomationProofTargetScoreboard
      .firstKnownPlanEvaluationID(for: row, evidenceIndex: evidenceIndex)
    {
      selectedPlanEvaluationID = planEvaluationID
      loadSelectedPlanEvaluationRecord()
    }

    if !experimentChanged {
      loadScenarioDraft()
    }
  }

  private func selectProofScoreboardGroup(
    _ group: TournamentAutomationProofTargetScoreboardReadinessGroup,
    preferredRow: TournamentAutomationProofTargetScoreboardRow? = nil
  ) {
    guard let row = preferredRow ?? group.primaryActionRow ?? group.primaryRow else { return }
    selectedProofScoreboardGroupAnchorRowID = row.selectionID
    selectProofScoreboardRow(row, preserveGroupSelection: true)
  }

  private func focusProofTarget(
    after audit: TournamentAutomationCycleAudit,
    preferredStep: TournamentAutomationStep?
  ) {
    guard
      let focus = TournamentAutomationProofTargetScoreboard.focus(
        after: audit,
        config: project.productTournamentConfig,
        evidenceIndex: evidenceIndex,
        preferredStep: preferredStep,
        isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
      )
    else { return }

    selectProofScoreboardRow(focus.row, preserveGroupSelection: true)
    if let evidenceRunID = focus.evidenceRunID {
      selectedRunID = evidenceRunID
      if let summary = evidenceIndex.summaries.first(where: { $0.runID == evidenceRunID }) {
        selectedScenarioID = summary.scenarioID
      }
      loadSelectedRecord()
    }
    if let planEvaluationID = focus.planEvaluationID {
      selectedPlanEvaluationID = planEvaluationID
      loadSelectedPlanEvaluationRecord()
    }
  }

  private func score(_ value: Int?) -> String {
    value.map(String.init) ?? "n/a"
  }

  private func scoreLabel(_ value: Double) -> String {
    value == 0 ? "0" : String(format: "%.1f", value)
  }

  private func priceLabel(cents: Int) -> String {
    String(format: "$%.0f/month", Double(max(0, cents)) / 100)
  }

  private func evidenceIntentSummary(
    _ summary: ProductTournamentEvidenceSummary,
    intent: ProductTournamentSimulationDecisionIntent
  ) -> String {
    var parts = [
      "target_decision \(intent.targetDecision.rawValue)",
      "current \(intent.currentDecision.rawValue)",
    ]
    if let evaluation = summary.decisionIntentEvaluation {
      parts.append(evaluation.outcome.rawValue)
    }
    return parts.joined(separator: ", ")
  }

  private func short(_ sha: String) -> String {
    String(sha.prefix(12))
  }
}

private struct MarketDecisionPanel: View {
  var cockpit: MarketDecisionCockpit

  var body: some View {
    WorkbenchSection("Market Pressure", systemImage: "person.3.sequence") {
      if let move = cockpit.nextMarketMove {
        WorkbenchStatusFact(
          label: "Next",
          value: move.reason,
          statusText: move.actionTitle,
          statusSystemImage: "arrow.forward.circle"
        )
        if let blockedReason = move.blockedReason {
          WorkbenchFact(label: "Blocked", value: blockedReason)
        }
      } else {
        WorkbenchEmptyLine("No market move queued.")
      }

      if let market = cockpit.activeMarket {
        WorkbenchFact(label: "Market", value: "\(market.category): \(market.summary)")
      } else {
        WorkbenchFact(label: "Market", value: "No synthetic market compiled.")
      }

      HStack(alignment: .top, spacing: 10) {
        WorkbenchMetric(
          label: "Debt",
          value: "\(cockpit.proofDebt.blockingCount)",
          systemImage: "exclamationmark.triangle"
        )
        WorkbenchMetric(
          label: "Actors",
          value: "\(cockpit.actors.count)",
          systemImage: "person.3"
        )
        WorkbenchMetric(
          label: "Pressure",
          value: "\(cockpit.pressureRows.count)",
          systemImage: "gavel"
        )
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
        ForEach(cockpit.proofDebt.cells) { cell in
          WorkbenchStatusFact(
            label: cell.label,
            value: cell.latestMovement.map { "Latest \($0)" } ?? "Debt \(cell.value)",
            statusText: cell.status.label,
            statusSystemImage: icon(for: cell.status)
          )
        }
      }

      if !cockpit.actors.isEmpty {
        Divider()
        ForEach(cockpit.actors.prefix(6)) { actor in
          WorkbenchStatusFact(
            label: actor.role,
            value: "\(actor.name): \(actor.job)",
            statusText: actor.pressureStatus,
            statusSystemImage: "person.crop.circle"
          )
        }
      }

      if !cockpit.pressureRows.isEmpty {
        Divider()
        ForEach(cockpit.pressureRows.prefix(4)) { row in
          WorkbenchStatusFact(
            label: row.kind.rawValue,
            value: row.strongestObjection.isEmpty ? row.nextAction : row.strongestObjection,
            statusText: row.verdict,
            statusSystemImage: "gavel"
          )
        }
      }

      if !cockpit.distributionRows.isEmpty || !cockpit.lifecycleRows.isEmpty {
        Divider()
        ForEach(cockpit.distributionRows.prefix(3)) { row in
          WorkbenchFact(
            label: "Channel",
            value: "\(row.channelName); \(row.verdict); next \(row.nextAction)"
          )
        }
        ForEach(cockpit.lifecycleRows.prefix(4)) { row in
          WorkbenchFact(
            label: "Lifecycle",
            value: "\(row.title); \(row.status.rawValue); next \(row.nextAction)"
          )
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      cockpit.nextMarketMove.map { "Market pressure, next move \($0.actionTitle)" }
        ?? "Market pressure"
    )
  }

  private func icon(for status: MarketProofDebtStatus) -> String {
    switch status {
    case .clear: return "checkmark.circle"
    case .moved: return "arrow.down.circle"
    case .missing: return "exclamationmark.circle"
    case .worsened: return "arrow.up.circle"
    case .blocked: return "xmark.octagon"
    }
  }
}

private struct WorkbenchSection<Content: View>: View {
  var title: String
  var systemImage: String
  let content: Content

  init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label(title, systemImage: systemImage)
        .font(.callout.weight(.semibold))
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }
}

private func tournamentStatusRank(_ status: ProductTournamentStatus) -> Int {
  switch status {
  case .active: return 0
  case .drafting: return 1
  case .completed: return 2
  case .archived: return 3
  }
}

private func contenderStatusRank(_ status: ProductTournamentContenderStatus) -> Int {
  switch status {
  case .competing: return 0
  case .narrowed: return 1
  case .needsRevision: return 2
  case .winner: return 3
  case .eliminated: return 4
  case .archived: return 5
  }
}

private struct WorkbenchValueBlock: View {
  var title: String
  var subtitle: String
  var detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer()
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      if !detail.isEmpty {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct WorkbenchFact: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 86, alignment: .leading)
      Text(value.isEmpty ? "none" : value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct WorkbenchStatusFact: View {
  var label: String
  var value: String
  var statusText: String
  var statusSystemImage: String
  var statusAccessibilityID: String?

  init(
    label: String,
    value: String,
    statusText: String,
    statusSystemImage: String,
    statusAccessibilityID: String? = nil
  ) {
    self.label = label
    self.value = value
    self.statusText = statusText
    self.statusSystemImage = statusSystemImage
    self.statusAccessibilityID = statusAccessibilityID
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 86, alignment: .leading)
      Text(value.isEmpty ? "none" : value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
      Spacer(minLength: 8)
      if let statusAccessibilityID {
        WorkbenchStatusPill(text: statusText, systemImage: statusSystemImage)
          .accessibilityIdentifier(statusAccessibilityID)
      } else {
        WorkbenchStatusPill(text: statusText, systemImage: statusSystemImage)
      }
    }
  }
}

private struct WorkbenchMetric: View {
  var label: String
  var value: String
  var systemImage: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
      Text(label)
      Text(value)
        .fontWeight(.bold)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(.quaternary.opacity(0.55), in: Capsule())
  }
}

private struct WorkbenchStatusPill: View {
  var text: String
  var systemImage: String? = nil

  var body: some View {
    HStack(spacing: 4) {
      if let systemImage {
        Image(systemName: systemImage)
      }
      Text(text)
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(.quaternary.opacity(0.55), in: Capsule())
  }
}

private struct WorkbenchEmptyLine: View {
  var text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

private struct ProductTournamentEvidenceCopyButton: View {
  var record: ProductTournamentEvidenceRecord
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(ProductTournamentEvidenceMarkdownExporter.markdown(record: record))
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .buttonStyle(.bordered)
    .help("Copy tournament evidence summary")
  }
}
