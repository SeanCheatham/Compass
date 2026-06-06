import Foundation

struct ProductScenarioDraft: Equatable, Sendable {
  var id: String?
  var experimentID: String
  var cohortID: String?
  var cohortTitle: String
  var cohortEnabled: Bool
  var segmentID: String
  var currentWorkflowID: String
  var alternativeID: String?
  var title: String
  var task: String
  var successSignal: String
  var targetCommitSha: String?
  var maxTurns: Int
  var appCommandTimeoutSeconds: Double
  var enabled: Bool

  init(
    id: String? = nil,
    experimentID: String,
    cohortID: String? = nil,
    cohortTitle: String = "",
    cohortEnabled: Bool = true,
    segmentID: String,
    currentWorkflowID: String,
    alternativeID: String? = nil,
    title: String,
    task: String,
    successSignal: String,
    targetCommitSha: String? = nil,
    maxTurns: Int = 8,
    appCommandTimeoutSeconds: Double = 120,
    enabled: Bool = true
  ) {
    self.id = ProductizationModelText.optionalIdentifier(id, fallback: "scenario")
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.cohortID = ProductizationModelText.optionalIdentifier(cohortID, fallback: "cohort")
    self.cohortTitle = ProductizationModelText.cleanedText(
      cohortTitle,
      fallback: "Product scenario cohort",
      limit: 180
    )
    self.cohortEnabled = cohortEnabled
    self.segmentID = ProductizationModelText.identifier(segmentID, fallback: "segment")
    self.currentWorkflowID = ProductizationModelText.identifier(
      currentWorkflowID,
      fallback: "workflow"
    )
    self.alternativeID = ProductizationModelText.optionalIdentifier(
      alternativeID,
      fallback: "alternative"
    )
    self.title = ProductizationModelText.cleanedText(
      title,
      fallback: "Productization scenario",
      limit: 180
    )
    self.task = ProductizationModelText.cleanedText(
      task,
      fallback: "Try the product experiment against the current workflow.",
      limit: 800
    )
    self.successSignal = ProductizationModelText.cleanedText(
      successSignal,
      fallback: "The scenario produces evidence for the next product decision.",
      limit: 500
    )
    self.targetCommitSha = ProductizationModelText.optionalCleanedText(
      targetCommitSha,
      limit: 80
    )
    self.maxTurns = min(20, max(1, maxTurns))
    self.appCommandTimeoutSeconds = min(20 * 60, max(5, appCommandTimeoutSeconds))
    self.enabled = enabled
  }
}

struct ProductizationScenarioRunOutcome {
  var request: ProductizationSimulationRequest
  var result: ProductizationRunResult
  var record: ProductizationEvidenceRecord
  var workingDirectory: URL

  var userMessage: String {
    switch result.status {
    case .completed:
      switch result.mode {
      case .modelFree:
        return "Model-free scenario run completed."
      case .personaModel:
        return "AI-user scenario run completed."
      }
    case .appContractMissing:
      return "Generated app contract is missing for this experiment."
    case .appCommandFailed:
      return result.failure?.message ?? "Generated app command failed."
    case .maxTurnsReached:
      return "Scenario reached the max turn limit before completion."
    case .nondeterministicExperienceTrace:
      return result.failure?.message ?? "Productization trace was nondeterministic."
    case .appOutputNotJSON, .noAllowedActions, .invalidPersonaAction,
      .personaCallFailed:
      return result.failure?.message ?? "Scenario run did not produce usable evidence."
    }
  }
}

struct ProductizationScenarioCohortRunOutcome {
  var experimentID: String
  var cohortID: String
  var mode: ProductizationSimulationMode
  var outcomes: [ProductizationScenarioRunOutcome]
  var skippedScenarioIDs: [String]

  var completedRunCount: Int {
    outcomes.filter { $0.result.isSuccess }.count
  }

  var failedRunCount: Int {
    outcomes.count - completedRunCount
  }

  var latestRecordID: String? {
    outcomes.last?.record.id
  }

  var isSuccess: Bool {
    !outcomes.isEmpty && failedRunCount == 0
  }

  var userMessage: String {
    let label: String
    switch mode {
    case .modelFree:
      label = "Model-free"
    case .personaModel:
      label = "AI-user"
    }
    return
      "\(label) cohort ran \(outcomes.count) scenario(s): \(completedRunCount) completed, \(failedRunCount) needing review, \(skippedScenarioIDs.count) skipped."
  }
}

enum ProductizationScenarioRunError: LocalizedError, Equatable {
  case unknownExperiment(String)
  case unknownCohort(String)
  case unknownScenario(String)
  case unknownSolution(String)
  case unknownPain(String)
  case unknownSegment(String)
  case unknownWorkflow(String)
  case unknownAlternative(String)
  case scenarioExperimentMismatch(
    scenarioID: String,
    selectedExperimentID: String,
    scenarioExperimentID: String
  )
  case roundTwoImplementationTargetMismatch(
    selectedExperimentID: String,
    expectedExperimentID: String,
    tournamentID: String,
    roundID: String,
    contenderID: String
  )
  case missingExperimentCommit(String)
  case staleScenarioCommit(scenarioID: String, expected: String, actual: String)
  case staleWorkingTree(url: URL, expected: String, actual: String)

  var errorDescription: String? {
    switch self {
    case .unknownExperiment(let id):
      return "Product experiment \(id) was not found in productization state."
    case .unknownCohort(let id):
      return "Product scenario cohort \(id) was not found in productization state."
    case .unknownScenario(let id):
      return "Product scenario \(id) was not found in productization state."
    case .unknownSolution(let id):
      return "Product solution \(id) was not found in productization state."
    case .unknownPain(let id):
      return "Pain hypothesis \(id) was not found in productization state."
    case .unknownSegment(let id):
      return "User segment \(id) was not found in productization state."
    case .unknownWorkflow(let id):
      return "Current workflow \(id) was not found in productization state."
    case .unknownAlternative(let id):
      return "Current alternative \(id) was not found in productization state."
    case .scenarioExperimentMismatch(
      let scenarioID,
      let selectedExperimentID,
      let scenarioExperimentID
    ):
      return
        "Scenario \(scenarioID) belongs to experiment \(scenarioExperimentID), but the run selected experiment \(selectedExperimentID). Select a scenario from the same experiment before collecting evidence."
    case .roundTwoImplementationTargetMismatch(
      let selectedExperimentID,
      let expectedExperimentID,
      let tournamentID,
      let roundID,
      let contenderID
    ):
      return
        "Round 2 implementation target for tournament \(tournamentID) round \(roundID) is experiment \(expectedExperimentID) / contender \(contenderID). Experiment \(selectedExperimentID) would build a competing contender; run the selected target or transition the tournament first."
    case .missingExperimentCommit(let id):
      return "Product experiment \(id) has no commit to run."
    case .staleScenarioCommit(let scenarioID, let expected, let actual):
      return
        "Scenario \(scenarioID) targets \(expected), but the selected experiment is at \(actual). Refresh or save the scenario before running evidence."
    case .staleWorkingTree(let url, let expected, let actual):
      return
        "Working tree \(url.path) is at \(actual), but the scenario targets \(expected). Refresh the experiment worktree before running evidence."
    }
  }
}

enum ProductizationScenarioCoordinator {
  static func revisionDraft(
    for brief: ProductFactoryRevisionBrief,
    in config: ProductizationConfig,
    now: Date = Date()
  ) throws -> ProductScenarioDraft {
    guard let experiment = config.experiments.first(where: { $0.id == brief.experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(brief.experimentID)
    }
    let fallback = defaultDraft(for: experiment, in: config, now: now)
    let existingScenario = brief.targetScenarioID.flatMap { scenarioID in
      config.scenarios.first {
        $0.id == scenarioID && $0.experimentID == experiment.id
      }
    }
    let segmentID = brief.targetPersonaID ?? existingScenario?.segmentID ?? fallback.segmentID
    guard config.userSegments.contains(where: { $0.id == segmentID }) else {
      throw ProductizationScenarioRunError.unknownSegment(segmentID)
    }
    let workflowID = existingScenario?.currentWorkflowID ?? fallback.currentWorkflowID
    guard config.currentWorkflows.contains(where: { $0.id == workflowID }) else {
      throw ProductizationScenarioRunError.unknownWorkflow(workflowID)
    }
    let alternativeID = existingScenario?.alternativeID ?? fallback.alternativeID
    if let alternativeID {
      guard config.alternatives.contains(where: { $0.id == alternativeID }) else {
        throw ProductizationScenarioRunError.unknownAlternative(alternativeID)
      }
    }
    let cohortID =
      brief.targetCohortID
      ?? cohortID(containing: existingScenario?.id, experiment: experiment, config: config)
      ?? fallback.cohortID
      ?? "\(experiment.id)-revision-cohort"
    let cohort = config.scenarioCohorts.first {
      $0.id == cohortID && $0.experimentID == experiment.id
    }
    let scenarioID =
      existingScenario?.id
      ?? ProductizationModelText.identifier(
        "\(experiment.id)-revision-\(Int(now.timeIntervalSince1970))",
        fallback: "revision-scenario"
      )
    let targetName = brief.targetPersonaName ?? segmentName(for: segmentID, in: config)
    return ProductScenarioDraft(
      id: scenarioID,
      experimentID: experiment.id,
      cohortID: cohortID,
      cohortTitle: cohort?.title ?? fallback.cohortTitle,
      cohortEnabled: cohort?.enabled ?? fallback.cohortEnabled,
      segmentID: segmentID,
      currentWorkflowID: workflowID,
      alternativeID: alternativeID,
      title: existingScenario?.title ?? "\(experiment.title) revision proof",
      task:
        "Revise the product bet for \(targetName). Prototype change to inspect: \(brief.prototypeChange) Scenario change: \(brief.scenarioChange) Trigger: \(brief.triggerSummary)",
      successSignal:
        "The AI user can say whether the revision resolved the original rationale. Proof plan: \(brief.proofPlan)",
      targetCommitSha: experiment.currentSha ?? experiment.baseSha,
      maxTurns: existingScenario?.maxTurns ?? fallback.maxTurns,
      appCommandTimeoutSeconds: existingScenario?.appCommandTimeoutSeconds
        ?? fallback.appCommandTimeoutSeconds,
      enabled: true
    )
  }

  static func defaultDraft(
    for experiment: ProductExperiment,
    in config: ProductizationConfig,
    now: Date = Date()
  ) -> ProductScenarioDraft {
    let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
    let painID = solution?.painID ?? config.painHypotheses.first?.id ?? ""
    let segment =
      config.userSegments.first { segment in
        segment.painID == painID
          && (solution?.targetSegmentIDs.isEmpty != false
            || solution?.targetSegmentIDs.contains(segment.id) == true)
      } ?? config.userSegments.first
    let workflow =
      config.currentWorkflows.first { workflow in
        workflow.painID == painID && segment?.currentWorkflowIDs.contains(workflow.id) != false
      } ?? config.currentWorkflows.first
    let alternative =
      config.alternatives.first { alternative in
        alternative.painID == painID && segment?.alternativeIDs.contains(alternative.id) != false
      } ?? config.alternatives.first
    let cohort = config.scenarioCohorts.first { $0.experimentID == experiment.id }
    let scenarioID = "\(experiment.id)-scenario-\(Int(now.timeIntervalSince1970))"
    return ProductScenarioDraft(
      id: scenarioID,
      experimentID: experiment.id,
      cohortID: cohort?.id ?? "\(experiment.id)-starter-cohort",
      cohortTitle: cohort?.title ?? "\(experiment.title) cohort",
      cohortEnabled: cohort?.enabled ?? true,
      segmentID: segment?.id ?? "segment",
      currentWorkflowID: workflow?.id ?? "workflow",
      alternativeID: alternative?.id,
      title: "\(experiment.title) scenario",
      task:
        "Try \(experiment.title) against the current workflow and decide whether it relieves the pain.",
      successSignal: solution?.requiredProof.first
        ?? "The target user can explain why this beats the current alternative.",
      targetCommitSha: experiment.currentSha ?? experiment.baseSha,
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true
    )
  }

  private static func cohortID(
    containing scenarioID: String?,
    experiment: ProductExperiment,
    config: ProductizationConfig
  ) -> String? {
    guard let scenarioID else { return nil }
    return config.scenarioCohorts.first {
      $0.experimentID == experiment.id && $0.scenarioIDs.contains(scenarioID)
    }?.id
  }

  private static func segmentName(for segmentID: String, in config: ProductizationConfig) -> String
  {
    let name = config.userSegments.first { $0.id == segmentID }?.name ?? segmentID
    return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segmentID : name
  }

  static func saving(
    draft: ProductScenarioDraft,
    to config: ProductizationConfig,
    now: Date = Date()
  ) throws -> ProductizationConfig {
    var next = config
    guard let experiment = next.experiments.first(where: { $0.id == draft.experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(draft.experimentID)
    }
    guard next.userSegments.contains(where: { $0.id == draft.segmentID }) else {
      throw ProductizationScenarioRunError.unknownSegment(draft.segmentID)
    }
    guard next.currentWorkflows.contains(where: { $0.id == draft.currentWorkflowID }) else {
      throw ProductizationScenarioRunError.unknownWorkflow(draft.currentWorkflowID)
    }
    if let alternativeID = draft.alternativeID {
      guard next.alternatives.contains(where: { $0.id == alternativeID }) else {
        throw ProductizationScenarioRunError.unknownAlternative(alternativeID)
      }
    }

    let timestamp = now.timeIntervalSince1970
    let scenarioID = draft.id ?? "\(experiment.id)-scenario-\(Int(timestamp))"
    let scenario = ProductScenario(
      id: scenarioID,
      experimentID: experiment.id,
      segmentID: draft.segmentID,
      currentWorkflowID: draft.currentWorkflowID,
      alternativeID: draft.alternativeID,
      title: draft.title,
      task: draft.task,
      successSignal: draft.successSignal,
      targetCommitSha: draft.targetCommitSha ?? experiment.currentSha ?? experiment.baseSha,
      maxTurns: draft.maxTurns,
      appCommandTimeoutSeconds: draft.appCommandTimeoutSeconds,
      enabled: draft.enabled,
      createdAt: next.scenarios.first { $0.id == scenarioID }?.createdAt ?? timestamp,
      updatedAt: timestamp
    )
    if let index = next.scenarios.firstIndex(where: { $0.id == scenarioID }) {
      next.scenarios[index] = scenario
    } else {
      next.scenarios.append(scenario)
    }

    let cohortID = draft.cohortID ?? "\(experiment.id)-starter-cohort"
    if let cohortIndex = next.scenarioCohorts.firstIndex(where: { $0.id == cohortID }) {
      var cohort = next.scenarioCohorts[cohortIndex]
      if !cohort.scenarioIDs.contains(scenario.id) {
        cohort.scenarioIDs.append(scenario.id)
      }
      next.scenarioCohorts[cohortIndex] = ProductScenarioCohort(
        id: cohort.id,
        title: draft.cohortTitle,
        experimentID: experiment.id,
        scenarioIDs: cohort.scenarioIDs,
        enabled: draft.cohortEnabled,
        tags: cohort.tags.isEmpty ? ["workbench"] : cohort.tags
      )
    } else {
      next.scenarioCohorts.append(
        ProductScenarioCohort(
          id: cohortID,
          title: draft.cohortTitle,
          experimentID: experiment.id,
          scenarioIDs: [scenario.id],
          enabled: draft.cohortEnabled,
          tags: ["workbench"]
        )
      )
    }
    return next
  }

  static func request(
    experimentID: String,
    scenarioID: String,
    in config: ProductizationConfig,
    projectID: UUID? = nil,
    projectTitle: String,
    generatedAppWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    mode: ProductizationSimulationMode = .modelFree,
    targetDecision: ProductExperimentDecision? = nil
  ) async throws -> ProductizationSimulationRequest {
    guard let experiment = config.experiments.first(where: { $0.id == experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(experimentID)
    }
    guard let scenario = config.scenarios.first(where: { $0.id == scenarioID }) else {
      throw ProductizationScenarioRunError.unknownScenario(scenarioID)
    }
    guard scenario.experimentID == experiment.id else {
      throw ProductizationScenarioRunError.scenarioExperimentMismatch(
        scenarioID: scenario.id,
        selectedExperimentID: experiment.id,
        scenarioExperimentID: scenario.experimentID
      )
    }
    try validateRoundTwoImplementationTarget(
      experimentID: experiment.id,
      in: config
    )
    guard let solution = config.solutionHypotheses.first(where: { $0.id == experiment.solutionID })
    else {
      throw ProductizationScenarioRunError.unknownSolution(experiment.solutionID)
    }
    guard let pain = config.painHypotheses.first(where: { $0.id == solution.painID }) else {
      throw ProductizationScenarioRunError.unknownPain(solution.painID)
    }
    guard let segment = config.userSegments.first(where: { $0.id == scenario.segmentID }) else {
      throw ProductizationScenarioRunError.unknownSegment(scenario.segmentID)
    }
    guard
      let currentWorkflow = config.currentWorkflows.first(where: {
        $0.id == scenario.currentWorkflowID
      })
    else {
      throw ProductizationScenarioRunError.unknownWorkflow(scenario.currentWorkflowID)
    }
    let selectedAlternatives = alternatives(for: scenario, painID: pain.id, in: config)
    let targetCommit = try targetCommit(for: scenario, experiment: experiment)
    if let experimentCommit = experiment.currentSha ?? experiment.baseSha,
      !ProductExperimentGit.commitMatches(expected: targetCommit, actual: experimentCommit)
    {
      throw ProductizationScenarioRunError.staleScenarioCommit(
        scenarioID: scenario.id,
        expected: targetCommit,
        actual: experimentCommit
      )
    }
    if let actualHead = try await gitHeadIfAvailable(at: generatedAppWorkingDirectory),
      !ProductExperimentGit.commitMatches(expected: targetCommit, actual: actualHead)
    {
      throw ProductizationScenarioRunError.staleWorkingTree(
        url: generatedAppWorkingDirectory,
        expected: targetCommit,
        actual: actualHead
      )
    }
    return ProductizationSimulationRequest(
      projectID: projectID,
      projectTitle: projectTitle,
      pain: pain,
      segment: segment,
      currentWorkflow: currentWorkflow,
      alternatives: selectedAlternatives,
      solution: solution,
      experiment: experiment,
      scenarioID: scenario.id,
      scenarioTask: scenario.task,
      scenarioSuccessSignal: scenario.successSignal,
      commitSha: targetCommit,
      generatedAppWorkingDirectory: generatedAppWorkingDirectory,
      launchPlan: launchPlan,
      settings: settings,
      mode: mode,
      targetDecision: targetDecision,
      maxTurns: scenario.maxTurns,
      appCommandTimeout: scenario.appCommandTimeoutSeconds
    )
  }

  static func generatedAppWorkingDirectory(
    for experiment: ProductExperiment,
    in workspace: CompassWorkspace
  ) -> URL {
    let worktreeURL = workspace.productExperimentWorktreeURL(experimentID: experiment.id)
    if FileManager.default.fileExists(atPath: worktreeURL.path) {
      return worktreeURL
    }
    return workspace.repoURL
  }

  static func contractAvailable(
    experimentID: String,
    in config: ProductizationConfig,
    workspace: CompassWorkspace,
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner()
  ) async throws -> Bool {
    guard let experiment = config.experiments.first(where: { $0.id == experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(experimentID)
    }
    return await appRunner.productizationExperienceContractAvailable(
      workingDirectory: generatedAppWorkingDirectory(for: experiment, in: workspace)
    )
  }

  static func runModelFree(
    experimentID: String,
    scenarioID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioRunOutcome {
    try await run(
      experimentID: experimentID,
      scenarioID: scenarioID,
      in: workspace,
      projectID: projectID,
      projectTitle: projectTitle,
      launchPlan: launchPlan,
      settings: settings,
      mode: .modelFree,
      appRunner: appRunner,
      targetDecision: targetDecision,
      now: now
    )
  }

  static func runPersonaModel(
    experimentID: String,
    scenarioID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    personaSelector: ProductizationPersonaActionSelecting =
      ProductizationFoundationModelsPersonaSelector(),
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioRunOutcome {
    try await run(
      experimentID: experimentID,
      scenarioID: scenarioID,
      in: workspace,
      projectID: projectID,
      projectTitle: projectTitle,
      launchPlan: launchPlan,
      settings: settings,
      mode: .personaModel,
      appRunner: appRunner,
      personaSelector: personaSelector,
      targetDecision: targetDecision,
      now: now
    )
  }

  static func runCohortModelFree(
    experimentID: String,
    cohortID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioCohortRunOutcome {
    try await runCohort(
      experimentID: experimentID,
      cohortID: cohortID,
      in: workspace,
      projectID: projectID,
      projectTitle: projectTitle,
      launchPlan: launchPlan,
      settings: settings,
      mode: .modelFree,
      appRunner: appRunner,
      targetDecision: targetDecision,
      now: now
    )
  }

  static func runCohortPersonaModel(
    experimentID: String,
    cohortID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    personaSelector: ProductizationPersonaActionSelecting =
      ProductizationFoundationModelsPersonaSelector(),
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioCohortRunOutcome {
    try await runCohort(
      experimentID: experimentID,
      cohortID: cohortID,
      in: workspace,
      projectID: projectID,
      projectTitle: projectTitle,
      launchPlan: launchPlan,
      settings: settings,
      mode: .personaModel,
      appRunner: appRunner,
      personaSelector: personaSelector,
      targetDecision: targetDecision,
      now: now
    )
  }

  static func runCohort(
    experimentID: String,
    cohortID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    mode: ProductizationSimulationMode,
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    personaSelector: ProductizationPersonaActionSelecting? = nil,
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioCohortRunOutcome {
    let config = try workspace.readProductizationConfig()
    guard config.experiments.contains(where: { $0.id == experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(experimentID)
    }
    guard
      let cohort = config.scenarioCohorts.first(where: {
        $0.id == cohortID && $0.experimentID == experimentID
      })
    else {
      throw ProductizationScenarioRunError.unknownCohort(cohortID)
    }

    var outcomes: [ProductizationScenarioRunOutcome] = []
    var skippedScenarioIDs: [String] = []
    for scenarioID in cohort.scenarioIDs {
      guard let scenario = config.scenarios.first(where: { $0.id == scenarioID }) else {
        throw ProductizationScenarioRunError.unknownScenario(scenarioID)
      }
      guard cohort.enabled && scenario.enabled else {
        skippedScenarioIDs.append(scenarioID)
        continue
      }
      let outcome = try await run(
        experimentID: experimentID,
        scenarioID: scenarioID,
        in: workspace,
        projectID: projectID,
        projectTitle: projectTitle,
        launchPlan: launchPlan,
        settings: settings,
        mode: mode,
        appRunner: appRunner,
        personaSelector: personaSelector,
        targetDecision: targetDecision,
        now: now
      )
      outcomes.append(outcome)
    }
    return ProductizationScenarioCohortRunOutcome(
      experimentID: experimentID,
      cohortID: cohortID,
      mode: mode,
      outcomes: outcomes,
      skippedScenarioIDs: skippedScenarioIDs
    )
  }

  static func run(
    experimentID: String,
    scenarioID: String,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    projectTitle: String,
    launchPlan: AgentExecutionLaunchPlan = .host(),
    settings: AgentRuntimeSettings = AgentRuntimeSettings(),
    mode: ProductizationSimulationMode,
    appRunner: ProductizationExperienceAppRunning = ProductizationExperienceCLIAppRunner(),
    personaSelector: ProductizationPersonaActionSelecting? = nil,
    targetDecision: ProductExperimentDecision? = nil,
    now: Date = Date()
  ) async throws -> ProductizationScenarioRunOutcome {
    var config = try workspace.readProductizationConfig()
    guard let experimentIndex = config.experiments.firstIndex(where: { $0.id == experimentID })
    else {
      throw ProductizationScenarioRunError.unknownExperiment(experimentID)
    }
    let experiment = config.experiments[experimentIndex]
    let workingDirectory = generatedAppWorkingDirectory(for: experiment, in: workspace)
    let request = try await request(
      experimentID: experimentID,
      scenarioID: scenarioID,
      in: config,
      projectID: projectID,
      projectTitle: projectTitle,
      generatedAppWorkingDirectory: workingDirectory,
      launchPlan: launchPlan,
      settings: settings,
      mode: mode,
      targetDecision: targetDecision
    )
    let startedAt = now.timeIntervalSince1970
    let result = await ProductizationSimulationRunner(
      appRunner: appRunner,
      personaSelector: personaSelector
    ).run(request)
    let endedAt = Date().timeIntervalSince1970
    let tournamentScope = ProductTournamentEvidenceScopeResolver.scope(
      experimentID: experimentID,
      in: config
    )
    let record = ProductizationEvidenceRecord(
      runResult: result,
      tournamentScope: tournamentScope,
      id: "\(scenarioID)-\(Int(endedAt))",
      startedAt: startedAt,
      endedAt: endedAt
    )
    let stored = try workspace.writeProductizationEvidenceRecord(
      record,
      traceJSON: result.experienceTraceJSON,
      transcriptJSONL: transcriptJSONL(result.rawPersonaActionTranscript)
    )
    config.experiments[experimentIndex].evidenceSummary = stored.summary
    config.experiments[experimentIndex].updatedAt = endedAt
    try workspace.writeProductizationConfig(config)
    return ProductizationScenarioRunOutcome(
      request: request,
      result: result,
      record: stored,
      workingDirectory: workingDirectory
    )
  }

  private static func alternatives(
    for scenario: ProductScenario,
    painID: String,
    in config: ProductizationConfig
  ) -> [Alternative] {
    if let alternativeID = scenario.alternativeID,
      let selected = config.alternatives.first(where: { $0.id == alternativeID })
    {
      return [selected]
    }
    return config.alternatives.filter { $0.painID == painID }
  }

  private static func validateRoundTwoImplementationTarget(
    experimentID: String,
    in config: ProductizationConfig
  ) throws {
    guard
      let target = roundTwoImplementationTarget(
        forExperimentInTargetTournament: experimentID,
        in: config
      ),
      target.experimentID != experimentID
    else { return }

    throw ProductizationScenarioRunError.roundTwoImplementationTargetMismatch(
      selectedExperimentID: experimentID,
      expectedExperimentID: target.experimentID,
      tournamentID: target.tournamentID,
      roundID: target.roundID,
      contenderID: target.contenderID
    )
  }

  private static func roundTwoImplementationTarget(
    forExperimentInTargetTournament experimentID: String,
    in config: ProductizationConfig
  ) -> ProductTournamentRoundImplementationTarget? {
    guard
      let contender = config.tournamentContenders.first(where: {
        $0.experimentID == experimentID
      }),
      let tournament = config.tournaments.first(where: {
        $0.id == contender.tournamentID && ($0.status == .active || $0.status == .drafting)
      }),
      let round = activeCoreTechnologyRound(for: tournament, in: config)
    else { return nil }

    let candidateIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    let candidates = candidateIDs.compactMap { contenderID in
      config.tournamentContenders.first {
        $0.id == contenderID
          && $0.tournamentID == tournament.id
          && $0.isRoundTwoImplementationCandidate
          && $0.experimentID != nil
      }
    }
    guard candidates.count == 1, let target = candidates.first,
      let targetExperimentID = target.experimentID
    else {
      return nil
    }

    return ProductTournamentRoundImplementationTarget(
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: target.id,
      experimentID: targetExperimentID
    )
  }

  private static func activeCoreTechnologyRound(
    for tournament: ProductTournament,
    in config: ProductizationConfig
  ) -> ProductTournamentRound? {
    let currentRound = tournament.currentRoundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID && $0.tournamentID == tournament.id }
    }
    if let currentRound,
      currentRound.kind == .coreTechnology,
      currentRound.status == .active
    {
      return currentRound
    }
    guard tournament.currentRoundID == nil else { return nil }
    return config.tournamentRounds
      .filter {
        $0.tournamentID == tournament.id
          && $0.kind == .coreTechnology
          && $0.status == .active
      }
      .sorted {
        if $0.ordinal == $1.ordinal { return $0.id < $1.id }
        return $0.ordinal < $1.ordinal
      }
      .first
  }

  private static func targetCommit(
    for scenario: ProductScenario,
    experiment: ProductExperiment
  ) throws -> String {
    let commit = scenario.targetCommitSha ?? experiment.currentSha ?? experiment.baseSha
    guard let commit, !commit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProductizationScenarioRunError.missingExperimentCommit(experiment.id)
    }
    return commit
  }

  private static func gitHeadIfAvailable(at url: URL) async throws -> String? {
    guard CompassWorkspace.isGitRepository(url) else { return nil }
    return try await ProductExperimentGit.output(
      ["rev-parse", "HEAD"],
      in: url,
      commandName: "rev-parse HEAD"
    )
  }

  private static func transcriptJSONL(
    _ transcript: [ProductizationPersonaActionTranscriptEntry]
  ) throws -> String? {
    guard !transcript.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try transcript.map {
      String(decoding: try encoder.encode($0), as: UTF8.self)
    }.joined(separator: "\n")
  }
}

private struct ProductTournamentRoundImplementationTarget: Equatable, Sendable {
  var tournamentID: String
  var roundID: String
  var contenderID: String
  var experimentID: String
}

extension ProductTournamentContender {
  fileprivate var isRoundTwoImplementationCandidate: Bool {
    switch status {
    case .narrowed, .needsRevision:
      return true
    case .competing, .winner, .eliminated, .archived:
      return false
    }
  }
}

extension CompassWorkspace {
  @discardableResult
  func saveProductScenarioDraft(_ draft: ProductScenarioDraft) throws -> ProductizationConfig {
    let next = try ProductizationScenarioCoordinator.saving(
      draft: draft,
      to: try readProductizationConfig()
    )
    try writeProductizationConfig(next)
    return next
  }
}

@MainActor
extension CompassProject {
  func saveProductScenarioDraft(_ draft: ProductScenarioDraft) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      productizationConfig = try workspace.saveProductScenarioDraft(draft)
      log("Saved productization scenario \(draft.title).", level: .success)
    } catch {
      fail(error)
    }
  }

  func productizationScenarioContractAvailable(experimentID: String) async -> Bool? {
    guard let workspace else { return nil }
    do {
      return try await ProductizationScenarioCoordinator.contractAvailable(
        experimentID: experimentID,
        in: productizationConfig,
        workspace: workspace
      )
    } catch {
      return nil
    }
  }

  func runProductizationScenarioModelFree(
    experimentID: String,
    scenarioID: String,
    targetDecision: ProductExperimentDecision? = nil
  ) async -> ProductizationScenarioRunOutcome? {
    await runProductizationScenario(
      experimentID: experimentID,
      scenarioID: scenarioID,
      mode: .modelFree,
      targetDecision: targetDecision
    )
  }

  func runProductizationScenarioPersonaModel(
    experimentID: String,
    scenarioID: String,
    targetDecision: ProductExperimentDecision? = nil
  ) async -> ProductizationScenarioRunOutcome? {
    guard FoundationModelsAvailability.isAvailable else {
      fail(ProductizationPersonaActionModelError.unavailable)
      return nil
    }
    return await runProductizationScenario(
      experimentID: experimentID,
      scenarioID: scenarioID,
      mode: .personaModel,
      targetDecision: targetDecision
    )
  }

  func runProductizationScenarioCohortModelFree(
    experimentID: String,
    cohortID: String,
    targetDecision: ProductExperimentDecision? = nil
  ) async -> ProductizationScenarioCohortRunOutcome? {
    await runProductizationScenarioCohort(
      experimentID: experimentID,
      cohortID: cohortID,
      mode: .modelFree,
      targetDecision: targetDecision
    )
  }

  func runProductizationScenarioCohortPersonaModel(
    experimentID: String,
    cohortID: String,
    targetDecision: ProductExperimentDecision? = nil
  ) async -> ProductizationScenarioCohortRunOutcome? {
    guard FoundationModelsAvailability.isAvailable else {
      fail(ProductizationPersonaActionModelError.unavailable)
      return nil
    }
    return await runProductizationScenarioCohort(
      experimentID: experimentID,
      cohortID: cohortID,
      mode: .personaModel,
      targetDecision: targetDecision
    )
  }

  private func runProductizationScenario(
    experimentID: String,
    scenarioID: String,
    mode: ProductizationSimulationMode,
    targetDecision: ProductExperimentDecision?
  ) async -> ProductizationScenarioRunOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      guard
        let experiment = productizationConfig.experiments.first(where: { $0.id == experimentID })
      else {
        throw ProductizationScenarioRunError.unknownExperiment(experimentID)
      }
      let workingDirectory = ProductizationScenarioCoordinator.generatedAppWorkingDirectory(
        for: experiment,
        in: workspace
      )
      let personaSelector: ProductizationPersonaActionSelecting? =
        mode == .personaModel ? ProductizationFoundationModelsPersonaSelector() : nil
      let outcome = try await ProductizationScenarioCoordinator.run(
        experimentID: experimentID,
        scenarioID: scenarioID,
        in: workspace,
        projectID: id,
        projectTitle: repoURL.lastPathComponent,
        launchPlan: agentLaunchPlan(for: workingDirectory),
        mode: mode,
        personaSelector: personaSelector,
        targetDecision: targetDecision
      )
      productizationConfig = try workspace.readProductizationConfig()
      productizationEvidenceIndex = workspace.readProductizationEvidenceIndex()
      log(outcome.userMessage, level: outcome.result.isSuccess ? .success : .warning)
      return outcome
    } catch {
      fail(error)
      return nil
    }
  }

  private func runProductizationScenarioCohort(
    experimentID: String,
    cohortID: String,
    mode: ProductizationSimulationMode,
    targetDecision: ProductExperimentDecision?
  ) async -> ProductizationScenarioCohortRunOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      guard
        let experiment = productizationConfig.experiments.first(where: { $0.id == experimentID })
      else {
        throw ProductizationScenarioRunError.unknownExperiment(experimentID)
      }
      let workingDirectory = ProductizationScenarioCoordinator.generatedAppWorkingDirectory(
        for: experiment,
        in: workspace
      )
      let personaSelector: ProductizationPersonaActionSelecting? =
        mode == .personaModel ? ProductizationFoundationModelsPersonaSelector() : nil
      let outcome = try await ProductizationScenarioCoordinator.runCohort(
        experimentID: experimentID,
        cohortID: cohortID,
        in: workspace,
        projectID: id,
        projectTitle: repoURL.lastPathComponent,
        launchPlan: agentLaunchPlan(for: workingDirectory),
        mode: mode,
        personaSelector: personaSelector,
        targetDecision: targetDecision
      )
      productizationConfig = try workspace.readProductizationConfig()
      productizationEvidenceIndex = workspace.readProductizationEvidenceIndex()
      log(outcome.userMessage, level: outcome.isSuccess ? .success : .warning)
      return outcome
    } catch {
      fail(error)
      return nil
    }
  }
}
