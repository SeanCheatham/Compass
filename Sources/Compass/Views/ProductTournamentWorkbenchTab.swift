import AppKit
import SwiftUI

struct ProductTournamentWorkbenchTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedExperimentID: String?
  @State private var selectedRunID: String?
  @State private var selectedRecord: ProductTournamentEvidenceRecord?
  @State private var recordError: String?
  @State private var selectedPlanEvaluationID: String?
  @State private var selectedPlanEvaluationRecord: ProductTournamentPlanEvaluationRecord?
  @State private var planEvaluationRecordError: String?
  @State private var gitPreview: ProductExperimentGitRolloutPreview?
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
  @State private var isApplyingPrototypeEvidenceTransition = false
  @State private var isRunningTournamentStep = false
  @State private var isRunningTournamentAutomationCycle = false
  @State private var scenarioRunMessage: String?
  @State private var planEvaluationMessage: String?
  @State private var planTransitionMessage: String?
  @State private var roundEvidenceTransitionMessage: String?
  @State private var prototypeEvidenceTransitionMessage: String?
  @State private var contractAvailable: Bool?

  private var config: ProductTournamentConfig { project.productTournamentConfig }
  private var evidenceIndex: ProductTournamentEvidenceIndex { project.productTournamentEvidenceIndex }

  private var tournamentsForBoard: [ProductTournament] {
    config.tournaments.sorted { lhs, rhs in
      if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
      return tournamentStatusRank(lhs.status) < tournamentStatusRank(rhs.status)
    }
  }

  private var contendersForBoard: [ProductTournamentContender] {
    config.tournamentContenders.sorted { lhs, rhs in
      if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
      return contenderStatusRank(lhs.status) < contenderStatusRank(rhs.status)
    }
  }

  private var tournamentRoundsForBoard: [ProductTournamentRound] {
    config.tournamentRounds.sorted { lhs, rhs in
      if lhs.ordinal == rhs.ordinal { return lhs.title < rhs.title }
      return lhs.ordinal < rhs.ordinal
    }
  }

  private var activeTournamentForPlanEvaluation: ProductTournament? {
    tournamentsForBoard.first { $0.status == .active || $0.status == .drafting }
  }

  private var activePlanRoundForEvaluation: ProductTournamentRound? {
    guard let tournament = activeTournamentForPlanEvaluation else { return nil }
    if let currentRoundID = tournament.currentRoundID,
      let current = config.tournamentRounds.first(where: { $0.id == currentRoundID }),
      current.kind == .productPlans,
      current.status != .completed
    {
      return current
    }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id && $0.kind == .productPlans && $0.status != .completed
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.title < rhs.title }
        return lhs.ordinal < rhs.ordinal
      }
      .first
  }

  private var activeTournamentForRoundEvidence: ProductTournament? {
    tournamentsForBoard.first { $0.status == .active || $0.status == .drafting }
  }

  private var activeCoreTechnologyRoundForEvidence: ProductTournamentRound? {
    guard let tournament = activeTournamentForRoundEvidence else { return nil }
    if let currentRoundID = tournament.currentRoundID,
      let current = config.tournamentRounds.first(where: { $0.id == currentRoundID }),
      current.kind == .coreTechnology,
      current.status == .active
    {
      return current
    }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id && $0.kind == .coreTechnology && $0.status == .active
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.title < rhs.title }
        return lhs.ordinal < rhs.ordinal
      }
      .first
  }

  private var activePrototypeRoundForEvidence: ProductTournamentRound? {
    guard let tournament = activeTournamentForRoundEvidence else { return nil }
    if let currentRoundID = tournament.currentRoundID,
      let current = config.tournamentRounds.first(where: { $0.id == currentRoundID }),
      current.kind == .prototype,
      current.status == .active
    {
      return current
    }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id && $0.kind == .prototype && $0.status == .active
      }
      .sorted { lhs, rhs in
        if lhs.ordinal == rhs.ordinal { return lhs.title < rhs.title }
        return lhs.ordinal < rhs.ordinal
      }
      .first
  }

  private var planEvaluationCanRun: Bool {
    activeTournamentForPlanEvaluation != nil
      && activePlanRoundForEvaluation != nil
      && !isRunningPlanEvaluation
      && !isApplyingPlanTransition
      && !isApplyingRoundEvidenceTransition
      && !isApplyingPrototypeEvidenceTransition
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
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
      && !isApplyingPrototypeEvidenceTransition
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
      && !isApplyingPrototypeEvidenceTransition
      && !isApplyingPlanTransition
      && !isRunningPlanEvaluation
      && !isRunningTournamentStep
      && !isRunningTournamentAutomationCycle
      && !isRunningScenario
  }

  private var prototypeEvidenceTransitionProposal:
    ProductTournamentPrototypeEvidenceTransitionProposal?
  {
    ProductTournamentPrototypeEvidenceTransitioner.bestProposal(
      tournamentID: activeTournamentForRoundEvidence?.id,
      roundID: activePrototypeRoundForEvidence?.id,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var prototypeEvidenceTransitionCanApply: Bool {
    prototypeEvidenceTransitionProposal != nil
      && !isApplyingPrototypeEvidenceTransition
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

  private var selectedExperiment: ProductExperiment? {
    guard let selectedExperimentID else { return config.experiments.first }
    return config.experiments.first { $0.id == selectedExperimentID } ?? config.experiments.first
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

  private var experimentsForBoard: [ProductExperiment] {
    TournamentAutomationExperimentRanker.rankedExperiments(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationProofTargets: [TournamentAutomationProofTarget] {
    TournamentAutomationProofTargetAdvisor.targets(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationRationaleSignals: [TournamentAutomationRationaleSignal] {
    TournamentAutomationRationaleSignalAdvisor.signals(
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var tournamentAutomationTargetedProofOutcomeSignals: [TournamentAutomationTargetedProofOutcomeSignal] {
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
    TournamentAutomationPlanner.nextStep(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
  }

  private var tournamentAutomationCyclePlan: TournamentAutomationCyclePlan {
    TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: evidenceIndex,
      maxSteps: 3,
      isPersonaModelAvailable: FoundationModelsAvailability.isAvailable
    )
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

  private var latestTournamentAutomationCycleAudit: TournamentAutomationCycleAudit? {
    config.tournamentAutomationCycleAudits.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
      return lhs.endedAt > rhs.endedAt
    }
    .first
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
      if config.isEmpty {
        ContentUnavailableView(
          "No Product Tournament State",
          systemImage: "trophy",
          description: Text("Enter a user pain or run Discover to seed product tournament state.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(alignment: .top, spacing: 12) {
          painMap
            .frame(width: 300)
          Divider()
          solutionAndExperimentBoard
            .frame(minWidth: 360, idealWidth: 460, maxWidth: 560)
          Divider()
          evidenceAndDecisionPane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .task(id: experimentSelectionTaskID) {
      let preferredExperimentID =
        defaultRoundTwoImplementationTarget?.experimentID ?? config.experiments.first?.id
      if selectedExperimentID == nil
        || !config.experiments.contains(where: { $0.id == selectedExperimentID })
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
      selectedRunID = runsForSelectedExperiment.first?.runID
      loadSelectedRecord()
      selectedScenarioID = scenariosForSelectedExperiment.first?.id
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
      config.experiments.map(\.id).joined(separator: ","),
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

  private var solutionAndExperimentBoard: some View {
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

        WorkbenchSection("Rounds", systemImage: "list.number") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Button {
                Task { await runPlanEvaluationRound(contenderID: nil) }
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
              ForEach(feasibilityHandoffs.prefix(3)) { handoff in
                feasibilityHandoffRow(handoff)
              }
            }
          }
        }

        WorkbenchSection("Round 3 Prototype", systemImage: "crown") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Button {
                Task { await applyPrototypeEvidenceTransition() }
              } label: {
                Label(
                  isApplyingPrototypeEvidenceTransition ? "Applying" : "Apply Round 3",
                  systemImage: "checkmark.seal"
                )
              }
              .buttonStyle(.bordered)
              .disabled(!prototypeEvidenceTransitionCanApply)
              .help(
                prototypeEvidenceTransitionProposal?.detail
                  ?? "No actionable Round 3 prototype recommendation yet."
              )

              if let prototypeEvidenceTransitionMessage {
                Text(prototypeEvidenceTransitionMessage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            if let proposal = prototypeEvidenceTransitionProposal {
              WorkbenchValueBlock(
                title: proposal.title,
                subtitle:
                  "\(proposal.contenderTitle) - \(proposal.scoreLabel)/100 - \(proposal.recommendation.rawValue)",
                detail: proposal.detail
              )
            } else {
              WorkbenchEmptyLine("No contender is active in Round 3 prototype evidence yet.")
            }
          }
        }

        WorkbenchSection("Solution Hypotheses", systemImage: "lightbulb") {
          VStack(alignment: .leading, spacing: 8) {
            if config.solutionHypotheses.isEmpty {
              WorkbenchEmptyLine("No solution hypotheses yet.")
            } else {
              ForEach(SolutionHypothesisStatus.allCases, id: \.rawValue) { status in
                let solutions = config.solutionHypotheses.filter { $0.status == status }
                if !solutions.isEmpty {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(status.rawValue)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                    ForEach(solutions) { solution in
                      WorkbenchValueBlock(
                        title: solution.title,
                        subtitle: "pain \(solution.painID)",
                        detail: solution.promise
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
            if config.experiments.isEmpty {
              WorkbenchEmptyLine("No contender implementation branches yet.")
            } else {
              ForEach(experimentsForBoard) { experiment in
                experimentRow(experiment)
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

        WorkbenchSection("AI-User Rationale Signals", systemImage: "person.2.wave.2") {
          VStack(alignment: .leading, spacing: 8) {
            if tournamentAutomationRationaleSignals.isEmpty {
              WorkbenchEmptyLine("No repeated AI-user rationale signals detected.")
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
              WorkbenchEmptyLine("No product revision briefs queued.")
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
      config.experiments.first { $0.id == experimentID }
    }
    let planReadiness = planReadiness(for: contender)
    let nextProofTarget = planProofTargetSummary(for: contender, readiness: planReadiness)
    return VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(contender.title)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
        Spacer()
        WorkbenchStatusPill(text: contender.status.rawValue)
      }
      WorkbenchFact(label: "Solution", value: contender.solutionID)
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
            Task { await runPlanEvaluationRound(contenderID: contender.id) }
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

  private func experimentRow(_ experiment: ProductExperiment) -> some View {
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
        WorkbenchFact(
          label: "Commit", value: experiment.currentSha ?? experiment.baseSha ?? "not created")
        if let roundTwoTarget {
          WorkbenchFact(
            label: "Round 2",
            value: roundTwoTarget.experimentID == experiment.id
              ? "selected implementation target"
              : "evidence locked to \(roundTwoTargetExperimentTitle(roundTwoTarget))"
          )
        }
        Text(experiment.prototypeScope)
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
        if let nextActionTitle = target.nextActionTitle {
          WorkbenchFact(label: "Next", value: nextActionTitle)
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
            signal.targetPersonaName.map { "AI-user rationale: \($0)" }
              ?? "AI-user rationale signal"
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
          WorkbenchFact(label: "Prototype", value: brief.prototypeChange)
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

  private func decisionCandidateRow(_ candidate: TournamentAutomationDecisionCandidate) -> some View {
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
          if step.kind == .runCohort {
            WorkbenchFact(
              label: "Mode",
              value: "\(tournamentAutomationCohortMode.tournamentAutomationLabel) cohort"
            )
          }
          if let tournamentAutomationRoundTwoBlockedMessage {
            WorkbenchFact(label: "Round 2", value: tournamentAutomationRoundTwoBlockedMessage)
          }
          if let latestTournamentAutomationCycleAudit {
            WorkbenchFact(label: "Last Cycle", value: latestTournamentAutomationCycleAudit.summary)
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

  @ViewBuilder
  private var scenarioAuthoring: some View {
    if let experiment = selectedExperiment {
      WorkbenchSection("Scenario Authoring", systemImage: "target") {
        VStack(alignment: .leading, spacing: 9) {
          if !scenariosForSelectedExperiment.isEmpty {
            Picker("Scenario", selection: scenarioSelectionBinding) {
              ForEach(scenariosForSelectedExperiment) { scenario in
                Text(scenario.title).tag(scenario.id)
              }
            }
            .pickerStyle(.menu)
          }

          TextField("Scenario title", text: $scenarioTitle)
            .textFieldStyle(.roundedBorder)
          HStack(spacing: 8) {
            TextField("Cohort title", text: $scenarioCohortTitle)
              .textFieldStyle(.roundedBorder)
            Toggle("Cohort enabled", isOn: $scenarioCohortEnabled)
              .toggleStyle(.checkbox)
          }
          HStack(spacing: 8) {
            Picker("Segment", selection: $scenarioSegmentID) {
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
                isSavingScenario ? "Saving" : "Save Scenario", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(isSavingScenario || !scenarioDraftCanSave)

            Button {
              Task { await runScenarioModelFree() }
            } label: {
              Label(isRunningScenario ? "Running" : "Run Model-Free", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunningScenario || !scenarioCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? "Run this scenario with a model-free simulated user."
            )

            Button {
              Task { await runScenarioPersonaModel() }
            } label: {
              Label(
                isRunningScenario ? "Running" : "Run AI User",
                systemImage: "brain.head.profile"
              )
            }
            .buttonStyle(.bordered)
            .disabled(isRunningScenario || !personaScenarioCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? (FoundationModelsAvailability.isAvailable
                  ? "Run with an AI simulated user"
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
                isRunningScenario ? "Running" : "AI Cohort",
                systemImage: "person.2.wave.2"
              )
            }
            .buttonStyle(.bordered)
            .disabled(isRunningScenario || !personaCohortCanRun)
            .help(
              selectedRoundTwoBlockedMessage
                ?? (FoundationModelsAvailability.isAvailable
                  ? "Run the cohort with AI simulated users"
                  : ProductTournamentPersonaActionModelError.unavailable.localizedDescription)
            )
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
            WorkbenchFact(label: "Target AI-user", value: targetValue)
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
                Label("AI Suggested Cohort", systemImage: "person.2.wave.2")
              }
              .buttonStyle(.bordered)
              .disabled(
                isRunningScenario || !suggestedCohortCanRun
                  || !FoundationModelsAvailability.isAvailable
              )
              .help(
                selectedRoundTwoBlockedMessage
                  ?? (FoundationModelsAvailability.isAvailable
                    ? "Run the suggested cohort with AI simulated users."
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
            label: "AI-user rationale",
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
          WorkbenchFact(label: "Solution", value: record.solutionID)
          if let experimentID = record.experimentID {
            WorkbenchFact(label: "Track", value: experimentID)
          }
          WorkbenchFact(label: "Mode", value: record.mode.rawValue)
          WorkbenchFact(label: "Model", value: record.model)
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
    _ action: ProductExperimentRolloutAction,
    experiment: ProductExperiment
  ) -> some View {
    Button {
      Task {
        await project.applyProductExperimentRolloutAction(action, experimentID: experiment.id)
      }
    } label: {
      Label(
        action.title(from: experiment.decision),
        systemImage: action == .promoteOrConfirm ? "arrow.up.forward" : "archivebox")
    }
    .buttonStyle(.bordered)
    .disabled(!ProductExperimentRolloutWorkflow.canApply(action, to: experiment))
  }

  @ViewBuilder
  private func gitRolloutPreviewBlock(for experiment: ProductExperiment) -> some View {
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
          if let willingnessToPayScore = record.willingnessToPayScore {
            WorkbenchFact(label: "Willingness to pay", value: "\(willingnessToPayScore)/5")
          }
          if !record.sponsorshipIntent.isEmpty {
            WorkbenchFact(label: "Sponsorship", value: record.sponsorshipIntent)
          }
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
          WorkbenchEmptyLine("No product decisions recorded yet.")
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
      gitPreview = try await project.productExperimentGitRolloutPreview(experimentID: experiment.id)
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
        stopDetail: "Manual product revision applied; run targeted validation evidence next.",
        userMessage:
          "Applied product revision for \(brief.experimentID). Run targeted validation evidence next."
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
        "Applied product revision \(brief.title) to scenario \(scenarioID)."
      ],
      maxSteps: 1,
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      revisionBriefSummaries: [brief.auditSummary],
      stopReason: .reachedStepLimit,
      stopStepID: stepID,
      stopStepTitle: "Apply product revision",
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

  private func runTournamentAutomationStep() async {
    guard let step = tournamentAutomationStep, step.canExecute else { return }
    if let blockedMessage = roundTwoLaunchBlockedMessage(experimentID: step.experimentID) {
      selectedExperimentID = step.experimentID
      scenarioRunMessage = blockedMessage
      return
    }
    selectedExperimentID = step.experimentID
    isRunningTournamentStep = true
    defer { isRunningTournamentStep = false }
    let stepStartedAt = Date()
    let startingProofDebt = tournamentAutomationProofDebt(forExperimentID: step.experimentID)
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
      ? tournamentAutomationRevisionBrief(forExperimentID: step.experimentID).map { [$0.auditSummary] }
        ?? []
      : []
    let personaRationaleSignalSummaries: [String]
    if let stepExperiment = project.productTournamentConfig.experiments.first(where: {
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
    let startingProofDebtSnapshot = tournamentAutomationProofDebtSnapshot(
      experimentIDs: [step.experimentID],
      proofDebts: startingProofDebt.map { [step.experimentID: $0] }
    )
    let endingProofDebtSnapshot = tournamentAutomationProofDebtSnapshot(
      experimentIDs: [step.experimentID]
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
      decisionCandidateSummaries: decisionCandidateSummaries,
      evidenceTensionSummaries: evidenceTensionSummaries,
      proofTargetSummaries: proofTargetSummaries,
      targetedProofOutcomeSummaries: targetedProofOutcomeSummaries,
      personaRationaleSignalSummaries: personaRationaleSignalSummaries,
      revisionBriefSummaries: revisionBriefSummaries
    )
    let audit = outcome.audit(startedAt: stepStartedAt)
    scenarioRunMessage = result?.message ?? project.errorMessage ?? step.blockedReason
    await project.saveProductTournamentConfig(
      project.productTournamentConfig.recordingTournamentAutomationCycleAudit(audit)
    )
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
    var startingProofDebts: [String: ProductTournamentProofDebt] = [:]
    var decisionCandidateSummaries: [String] = []
    var evidenceTensionSummaries: [String] = []
    var proofTargetSummaries: [String] = []
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
      if startingProofDebts[step.experimentID] == nil {
        startingProofDebts[step.experimentID] = tournamentAutomationProofDebt(
          forExperimentID: step.experimentID
        )
      }
      if step.action.kind == .applyDecision,
        let candidate = tournamentAutomationDecisionCandidate(forExperimentID: step.experimentID),
        !decisionCandidateSummaries.contains(candidate.auditSummary)
      {
        decisionCandidateSummaries.append(candidate.auditSummary)
      }
      if let evidenceTension = tournamentAutomationEvidenceTension(forExperimentID: step.experimentID),
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
      if let stepExperiment = project.productTournamentConfig.experiments.first(where: {
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
      messages.append(result.message)
      evidenceRunIDs.append(contentsOf: result.evidenceRunIDs)
      completedEvidenceRunCount += result.completedEvidenceRunCount
      failedEvidenceRunCount += result.failedEvidenceRunCount
      skippedScenarioCount += result.skippedScenarioCount
      if let stepRevisionBrief,
        let scenarioID = step.targetScenarioID ?? stepRevisionBrief.targetScenarioID
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
            "Product revision checkpoint recorded; continue with targeted validation evidence.",
          userMessage:
            "Product revision checkpoint recorded for \(stepRevisionBrief.experimentID). Continuing with targeted validation evidence."
        )
        await project.saveProductTournamentConfig(
          project.productTournamentConfig.recordingTournamentAutomationCycleAudit(checkpoint)
        )
      }
    }
    let startingProofDebt = tournamentAutomationProofDebtSnapshot(
      experimentIDs: touchedExperimentIDs,
      proofDebts: startingProofDebts
    )
    let endingProofDebt = tournamentAutomationProofDebtSnapshot(
      experimentIDs: touchedExperimentIDs
    )
    let outcome = TournamentAutomationCycleOutcome(
      executedSteps: executedSteps,
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
    await loadContractStatus()
  }

  private func tournamentAutomationProofDebt(
    forExperimentID experimentID: String
  ) -> ProductTournamentProofDebt? {
    guard
      let experiment = project.productTournamentConfig.experiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return project.productTournamentEvidenceIndex.currentTournamentReadiness(for: experiment)?.proofDebt
      ?? ProductTournamentProofDebt(
        completedRunCount: 0,
        distinctPersonaCount: 0,
        aiUserDistinctPersonaCount: 0,
        aiUserCurrentAlternativePersonaCount: 0,
        failedRunCount: 0
      )
  }

  private func tournamentAutomationProofTarget(
    forExperimentID experimentID: String
  ) -> TournamentAutomationProofTarget? {
    guard
      let experiment = project.productTournamentConfig.experiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationProofTargetAdvisor.target(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
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
      let experiment = project.productTournamentConfig.experiments.first(where: {
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
      let experiment = project.productTournamentConfig.experiments.first(where: {
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
      let experiment = project.productTournamentConfig.experiments.first(where: {
        $0.id == experimentID
      })
    else { return nil }
    return TournamentAutomationRevisionBriefAdvisor.brief(
      for: experiment,
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex
    )
  }

  private func tournamentAutomationProofDebtSnapshot(
    experimentIDs: [String],
    proofDebts: [String: ProductTournamentProofDebt]? = nil
  ) -> (count: Int, summary: String)? {
    var orderedExperimentIDs: [String] = []
    for experimentID in experimentIDs where !orderedExperimentIDs.contains(experimentID) {
      orderedExperimentIDs.append(experimentID)
    }
    var total = 0
    var parts: [String] = []
    for experimentID in orderedExperimentIDs {
      guard
        let debt = proofDebts?[experimentID]
          ?? tournamentAutomationProofDebt(forExperimentID: experimentID)
      else { continue }
      total += debt.blockingDebtCount
      parts.append("\(experimentID): \(debt.summary)")
    }
    guard !parts.isEmpty else { return nil }
    return (
      total,
      StringUtils.boundedText(parts.joined(separator: "; "), limit: 500)
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
            "Applied product revision for \(step.experimentTitle): \(brief.title) to scenario \(scenarioID)."
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
    targetDecision: ProductExperimentDecision? = nil
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
    targetDecision: ProductExperimentDecision? = nil
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

  private func runPlanEvaluationRound(contenderID: String?) async {
    guard let tournament = activeTournamentForPlanEvaluation,
      let round = activePlanRoundForEvaluation
    else { return }
    isRunningPlanEvaluation = true
    runningPlanEvaluationContenderID = contenderID
    defer {
      isRunningPlanEvaluation = false
      runningPlanEvaluationContenderID = nil
    }
    let outcome = await project.runProductTournamentPlanRoundModelFree(
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contenderID
    )
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

  private func applyPrototypeEvidenceTransition() async {
    guard let tournament = activeTournamentForRoundEvidence,
      let round = activePrototypeRoundForEvidence
    else { return }
    isApplyingPrototypeEvidenceTransition = true
    defer { isApplyingPrototypeEvidenceTransition = false }
    let outcome = await project.applyBestProductTournamentPrototypeEvidenceTransition(
      tournamentID: tournament.id,
      roundID: round.id
    )
    if let outcome {
      prototypeEvidenceTransitionMessage = outcome.userMessage
    } else {
      prototypeEvidenceTransitionMessage = project.errorMessage
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
    config.experiments.first { $0.id == target.experimentID }?.title ?? target.experimentID
  }

  private func roundTwoTargetContenderTitle(
    _ target: ProductTournamentRoundImplementationTarget
  ) -> String {
    config.tournamentContenders.first { $0.id == target.contenderID }?.title ?? target.contenderID
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

  var body: some View {
    Text(text)
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
