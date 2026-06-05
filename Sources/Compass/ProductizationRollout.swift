import Foundation

enum ProductExperimentRolloutAction: String, CaseIterable, Equatable, Sendable {
  case promoteOrConfirm
  case killOrArchive

  func targetDecision(from current: ProductExperimentDecision) -> ProductExperimentDecision {
    switch self {
    case .promoteOrConfirm:
      return current == .promote ? .promoted : .promote
    case .killOrArchive:
      return current == .kill ? .archived : .kill
    }
  }

  func title(from current: ProductExperimentDecision) -> String {
    switch self {
    case .promoteOrConfirm:
      return current == .promote ? "Promote" : "Mark Promote"
    case .killOrArchive:
      return current == .kill ? "Archive" : "Kill"
    }
  }
}

enum ProductExperimentRolloutError: LocalizedError, Equatable {
  case unknownExperiment(String)

  var errorDescription: String? {
    switch self {
    case .unknownExperiment(let id):
      return "Product experiment \(id) was not found in productization state."
    }
  }
}

enum ProductExperimentRolloutWorkflow {
  static func canApply(
    _ action: ProductExperimentRolloutAction,
    to experiment: ProductExperiment
  ) -> Bool {
    do {
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: experiment.id,
        from: experiment.decision,
        to: action.targetDecision(from: experiment.decision),
        summary: summary(for: action, experiment: experiment)
      )
      return true
    } catch {
      return false
    }
  }

  static func applying(
    _ action: ProductExperimentRolloutAction,
    experimentID: String,
    to config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    now: Date = Date(),
    decidedBy: String = "Productization Workbench"
  ) throws -> ProductizationConfig {
    var next = config
    guard let experimentIndex = next.experiments.firstIndex(where: { $0.id == experimentID })
    else {
      throw ProductExperimentRolloutError.unknownExperiment(experimentID)
    }

    let experiment = next.experiments[experimentIndex]
    let target = action.targetDecision(from: experiment.decision)
    let summary = summary(for: action, experiment: experiment)
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: experiment.id,
      from: experiment.decision,
      to: target,
      summary: summary
    )

    let timestamp = now.timeIntervalSince1970
    let evidenceRunIDs = evidenceRunIDs(for: experiment.id, evidenceIndex: evidenceIndex)
    let beforeSha = experiment.currentSha ?? experiment.baseSha

    next.experiments[experimentIndex].decision = target
    next.experiments[experimentIndex].evidenceSummary = summary
    next.experiments[experimentIndex].updatedAt = timestamp

    if let solutionIndex = next.solutionHypotheses.firstIndex(where: { $0.id == experiment.solutionID }) {
      switch target {
      case .promoted:
        next.solutionHypotheses[solutionIndex].status = .promoted
      case .kill:
        next.solutionHypotheses[solutionIndex].status = .rejected
      case .archived:
        next.solutionHypotheses[solutionIndex].status = .parked
      case .notRun, .keepGoing, .narrow, .pivot, .promote:
        break
      }
    }

    next.decisions.append(
      ProductDecision(
        id: "\(experiment.id)-\(target.rawValue)-\(Int(timestamp))-\(next.decisions.count + 1)",
        experimentID: experiment.id,
        decision: target,
        summary: summary,
        evidenceRunIDs: evidenceRunIDs,
        branchName: experiment.branchName,
        beforeSha: beforeSha,
        afterSha: next.experiments[experimentIndex].currentSha
          ?? next.experiments[experimentIndex].baseSha,
        decidedAt: timestamp,
        decidedBy: decidedBy
      )
    )
    return next
  }

  static func evidenceRunIDs(
    for experimentID: String,
    evidenceIndex: ProductizationEvidenceIndex
  ) -> [String] {
    evidenceIndex.summaries
      .filter { $0.experimentID == experimentID }
      .prefix(8)
      .map(\.runID)
  }

  private static func summary(
    for action: ProductExperimentRolloutAction,
    experiment: ProductExperiment
  ) -> String {
    switch action {
    case .promoteOrConfirm:
      if experiment.decision == .promote {
        return
          "Promoted \(experiment.title) from branch \(experiment.branchName) after productization evidence and Verify supported the product direction."
      }
      return
        "Marked \(experiment.title) promotion-ready; verify the branch, inspect evidence, and confirm before merging product direction."
    case .killOrArchive:
      if experiment.decision == .kill {
        return
          "Archived \(experiment.title) while preserving branch \(experiment.branchName), worktree \(experiment.worktreeID), and evidence."
      }
      return
        "Killed \(experiment.title) because the current product evidence does not justify continued investment."
    }
  }
}

@MainActor
extension CompassProject {
  func applyProductExperimentRolloutAction(
    _ action: ProductExperimentRolloutAction,
    experimentID: String
  ) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      let actionTitle = productizationConfig.experiments
        .first { $0.id == experimentID }
        .map { action.title(from: $0.decision) }
        ?? action.rawValue
      let next = try ProductExperimentRolloutWorkflow.applying(
        action,
        experimentID: experimentID,
        to: productizationConfig,
        evidenceIndex: productizationEvidenceIndex
      )
      try workspace.writeProductizationConfig(next)
      productizationConfig = next
      log(
        "\(actionTitle) recorded for product experiment \(experimentID).",
        level: .success
      )
    } catch {
      fail(error)
    }
  }
}
