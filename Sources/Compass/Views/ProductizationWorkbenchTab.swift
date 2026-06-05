import AppKit
import SwiftUI

struct ProductizationWorkbenchTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedExperimentID: String?
  @State private var selectedRunID: String?
  @State private var selectedRecord: ProductizationEvidenceRecord?
  @State private var recordError: String?
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
  @State private var scenarioRunMessage: String?
  @State private var contractAvailable: Bool?

  private var config: ProductizationConfig { project.productizationConfig }
  private var evidenceIndex: ProductizationEvidenceIndex { project.productizationEvidenceIndex }

  private var selectedExperiment: ProductExperiment? {
    guard let selectedExperimentID else { return config.experiments.first }
    return config.experiments.first { $0.id == selectedExperimentID } ?? config.experiments.first
  }

  private var runsForSelectedExperiment: [ProductizationEvidenceSummary] {
    guard let selectedExperiment else { return [] }
    return evidenceIndex.summaries(for: selectedExperiment)
  }

  private var selectedPMFReadiness: ProductMarketFitReadiness? {
    guard let selectedExperiment else { return nil }
    return evidenceIndex.currentPMFReadiness(for: selectedExperiment)
  }

  private var selectedStaleEvidenceCount: Int {
    guard let selectedExperiment else { return 0 }
    return evidenceIndex.staleSummaryCount(for: selectedExperiment)
  }

  private var selectedPMFDecisionProposal: ProductMarketFitDecisionProposal? {
    guard let experimentID = selectedExperiment?.id else { return nil }
    return ProductMarketFitDecisionAdvisor.proposal(
      experimentID: experimentID,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var selectedPMFNextAction: ProductMarketFitNextAction? {
    guard let selectedExperiment else { return nil }
    return ProductMarketFitNextActionAdvisor.nextAction(
      for: selectedExperiment,
      config: config,
      evidenceIndex: evidenceIndex
    )
  }

  private var selectedSuggestedCohortReadiness: ProductMarketFitCohortRunReadiness? {
    guard let selectedExperiment,
      let action = selectedPMFNextAction
    else { return nil }
    return ProductMarketFitNextActionAdvisor.cohortRunReadiness(
      for: action,
      experiment: selectedExperiment,
      config: config
    )
  }

  private var suggestedCohortCanRun: Bool {
    contractAvailable == true && selectedSuggestedCohortReadiness?.canRun == true
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if config.isEmpty {
        ContentUnavailableView(
          "No Productization State",
          systemImage: "scope",
          description: Text("Enter raw pain or run Discover to seed productization state.")
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
    .task(id: config.experiments.map(\.id).joined(separator: "|")) {
      if selectedExperimentID == nil
        || !config.experiments.contains(where: { $0.id == selectedExperimentID })
      {
        selectedExperimentID = config.experiments.first?.id
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

  private var contractStatusTaskID: String {
    let experiment = selectedExperiment
    return [
      selectedExperimentID ?? "",
      experiment?.currentSha ?? "",
      "\(config.scenarios.count)",
    ].joined(separator: "|")
  }

  private var header: some View {
    HStack {
      SectionHeader("Productization", systemImage: "scope")
      Spacer()
      Button {
        Task { await project.reloadProductizationEvidenceIndex() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .help("Reload productization evidence")
    }
  }

  private var painMap: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
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

  private var solutionAndExperimentBoard: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        WorkbenchSection("Solution Board", systemImage: "rectangle.3.group") {
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

        WorkbenchSection("Experiment Board", systemImage: "point.3.connected.trianglepath.dotted") {
          VStack(alignment: .leading, spacing: 8) {
            if config.experiments.isEmpty {
              WorkbenchEmptyLine("No experiment branches yet.")
            } else {
              ForEach(config.experiments) { experiment in
                experimentRow(experiment)
              }
            }
          }
        }
      }
      .padding(.trailing, 4)
    }
  }

  private func experimentRow(_ experiment: ProductExperiment) -> some View {
    Button {
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
        WorkbenchFact(label: "Branch", value: experiment.branchName)
        WorkbenchFact(label: "Worktree", value: experiment.worktreeID)
        WorkbenchFact(
          label: "Commit", value: experiment.currentSha ?? experiment.baseSha ?? "not created")
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

  private var evidenceAndDecisionPane: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        aggregateEvidence
        selectedExperimentActions
        scenarioAuthoring
        evidenceRuns
        selectedEvidenceDetail
        decisionTimeline
      }
      .padding(.trailing, 8)
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
          if let contractAvailable {
            Label(
              contractAvailable
                ? "Productization contract available" : "Productization contract missing",
              systemImage: contractAvailable ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(contractAvailable ? Color.secondary : Color.orange)
          } else {
            WorkbenchEmptyLine("Checking productization contract...")
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
              FoundationModelsAvailability.isAvailable
                ? "Run with an AI simulated user"
                : ProductizationPersonaActionModelError.unavailable.localizedDescription
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
              FoundationModelsAvailability.isAvailable
                ? "Run the cohort with AI simulated users"
                : ProductizationPersonaActionModelError.unavailable.localizedDescription
            )
          }
        }
      }
    }
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
          if let readiness = selectedPMFReadiness {
            WorkbenchMetric(
              label: "PMF", value: readiness.scoreLabel, systemImage: "chart.line.uptrend.xyaxis")
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
        if let readiness = selectedPMFReadiness {
          WorkbenchFact(
            label: "Readiness",
            value:
              "\(readiness.recommendation.title), \(readiness.completedRunCount)/\(readiness.runCount) completed, \(readiness.distinctPersonaCount) persona(s)"
          )
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
        if let nextAction = selectedPMFNextAction {
          WorkbenchFact(label: "Next action", value: nextAction.title)
          WorkbenchFact(
            label: "Action",
            value: "\(nextAction.kind.rawValue), priority \(nextAction.priority)"
          )
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
            }
          }
        }
        if let objection = evidenceIndex.aggregate.repeatedObjections.first {
          WorkbenchFact(
            label: "Repeated objection", value: "\(objection.objection) (\(objection.count)x)")
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

  @ViewBuilder
  private var selectedExperimentActions: some View {
    if let experiment = selectedExperiment {
      WorkbenchSection("Promotion And Archive", systemImage: "arrow.up.forward.circle") {
        VStack(alignment: .leading, spacing: 8) {
          Text(experiment.evidenceSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          if let proposal = selectedPMFDecisionProposal {
            WorkbenchFact(
              label: "PMF advice",
              value:
                "\(proposal.currentDecision.rawValue) -> \(proposal.update.decision.rawValue)"
            )
            Text(proposal.update.summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button {
              Task {
                await project.applyProductMarketFitDecisionRecommendation(
                  experimentID: experiment.id
                )
              }
            } label: {
              Label("Apply PMF Advice", systemImage: "checkmark.seal")
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
          ProductizationEvidenceCopyButton(record: record)
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
      selectedRecord = try project.readProductizationEvidenceRecord(id: selectedRunID)
      recordError = nil
    } catch {
      selectedRecord = nil
      recordError = error.localizedDescription
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
    let draft = ProductizationScenarioCoordinator.defaultDraft(
      for: experiment,
      in: config
    )
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

  private func runSuggestedCohort(mode: ProductizationSimulationMode) async {
    guard let cohortID = selectedPMFNextAction?.cohortID else { return }
    await runScenarioCohort(
      mode: mode,
      cohortID: cohortID,
      saveDraftFirst: false
    )
  }

  private func runScenario(mode: ProductizationSimulationMode) async {
    guard let experiment = selectedExperiment,
      let selectedScenarioID
    else { return }
    if scenarioDraftCanSave {
      await saveScenarioDraft()
    }
    isRunningScenario = true
    defer { isRunningScenario = false }
    let outcome: ProductizationScenarioRunOutcome?
    switch mode {
    case .modelFree:
      outcome = await project.runProductizationScenarioModelFree(
        experimentID: experiment.id,
        scenarioID: selectedScenarioID
      )
    case .personaModel:
      outcome = await project.runProductizationScenarioPersonaModel(
        experimentID: experiment.id,
        scenarioID: selectedScenarioID
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
    mode: ProductizationSimulationMode,
    cohortID: String? = nil,
    saveDraftFirst: Bool = true
  ) async {
    guard let experiment = selectedExperiment,
      !(cohortID ?? scenarioCohortID).isEmpty
    else { return }
    let targetCohortID = cohortID ?? scenarioCohortID
    if saveDraftFirst && scenarioDraftCanSave {
      await saveScenarioDraft()
    }
    isRunningScenario = true
    defer { isRunningScenario = false }
    let outcome: ProductizationScenarioCohortRunOutcome?
    switch mode {
    case .modelFree:
      outcome = await project.runProductizationScenarioCohortModelFree(
        experimentID: experiment.id,
        cohortID: targetCohortID
      )
    case .personaModel:
      outcome = await project.runProductizationScenarioCohortPersonaModel(
        experimentID: experiment.id,
        cohortID: targetCohortID
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

  private func loadContractStatus() async {
    guard let experiment = selectedExperiment else {
      contractAvailable = nil
      return
    }
    contractAvailable = await project.productizationScenarioContractAvailable(
      experimentID: experiment.id
    )
  }

  private func score(_ value: Int?) -> String {
    value.map(String.init) ?? "n/a"
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

private struct ProductizationEvidenceCopyButton: View {
  var record: ProductizationEvidenceRecord
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(ProductizationEvidenceMarkdownExporter.markdown(record: record))
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .buttonStyle(.bordered)
    .help("Copy productization evidence summary")
  }
}
