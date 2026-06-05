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
      return "Model-free scenario run completed."
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

enum ProductizationScenarioRunError: LocalizedError, Equatable {
  case unknownExperiment(String)
  case unknownScenario(String)
  case unknownSolution(String)
  case unknownPain(String)
  case unknownSegment(String)
  case unknownWorkflow(String)
  case unknownAlternative(String)
  case missingExperimentCommit(String)
  case staleScenarioCommit(scenarioID: String, expected: String, actual: String)
  case staleWorkingTree(url: URL, expected: String, actual: String)

  var errorDescription: String? {
    switch self {
    case .unknownExperiment(let id):
      return "Product experiment \(id) was not found in productization state."
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
  static func defaultDraft(
    for experiment: ProductExperiment,
    in config: ProductizationConfig,
    now: Date = Date()
  ) -> ProductScenarioDraft {
    let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
    let painID = solution?.painID ?? config.painHypotheses.first?.id ?? ""
    let segment = config.userSegments.first { segment in
      segment.painID == painID
        && (solution?.targetSegmentIDs.isEmpty != false || solution?.targetSegmentIDs.contains(segment.id) == true)
    } ?? config.userSegments.first
    let workflow = config.currentWorkflows.first { workflow in
      workflow.painID == painID && segment?.currentWorkflowIDs.contains(workflow.id) != false
    } ?? config.currentWorkflows.first
    let alternative = config.alternatives.first { alternative in
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
      task: "Try \(experiment.title) against the current workflow and decide whether it relieves the pain.",
      successSignal: solution?.requiredProof.first
        ?? "The target user can explain why this beats the current alternative.",
      targetCommitSha: experiment.currentSha ?? experiment.baseSha,
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true
    )
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
    settings: AgentRuntimeSettings = AgentRuntimeSettings()
  ) async throws -> ProductizationSimulationRequest {
    guard let experiment = config.experiments.first(where: { $0.id == experimentID }) else {
      throw ProductizationScenarioRunError.unknownExperiment(experimentID)
    }
    guard let scenario = config.scenarios.first(where: { $0.id == scenarioID }) else {
      throw ProductizationScenarioRunError.unknownScenario(scenarioID)
    }
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
      mode: .modelFree,
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
      settings: settings
    )
    let startedAt = now.timeIntervalSince1970
    let result = await ProductizationSimulationRunner(appRunner: appRunner).run(request)
    let endedAt = Date().timeIntervalSince1970
    let record = ProductizationEvidenceRecord(
      runResult: result,
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
    scenarioID: String
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
      let outcome = try await ProductizationScenarioCoordinator.runModelFree(
        experimentID: experimentID,
        scenarioID: scenarioID,
        in: workspace,
        projectID: id,
        projectTitle: repoURL.lastPathComponent,
        launchPlan: agentLaunchPlan(for: workingDirectory)
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
}
