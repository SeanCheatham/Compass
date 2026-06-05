import Foundation

enum ProductExperimentGitRolloutKind: String, Equatable, Sendable {
  case fastForwardPromotion = "fast_forward_promotion"
  case mergePromotion = "merge_promotion"
  case archive
}

struct ProductExperimentGitRolloutPreview: Equatable, Sendable {
  var experimentID: String
  var solutionID: String
  var experimentBranchName: String
  var acceptedBranchName: String
  var archiveBranchName: String?
  var expectedExperimentSha: String?
  var actualExperimentSha: String
  var acceptedBeforeSha: String
  var mergeBaseSha: String
  var kind: ProductExperimentGitRolloutKind
  var changedFiles: [String]
  var commitSubjects: [String]

  var experimentStateMatchesBranch: Bool {
    guard let expectedExperimentSha else { return false }
    return ProductExperimentGit.commitMatches(expected: expectedExperimentSha, actual: actualExperimentSha)
  }

  var boundedSummary: String {
    var lines = [
      "Accepted branch: \(acceptedBranchName) @ \(short(acceptedBeforeSha))",
      "Experiment branch: \(experimentBranchName) @ \(short(actualExperimentSha))",
      "Operation: \(kind.rawValue)",
    ]
    if let expectedExperimentSha, !experimentStateMatchesBranch {
      lines.append("State mismatch: expected \(short(expectedExperimentSha))")
    }
    if let archiveBranchName {
      lines.append("Archive branch: \(archiveBranchName)")
    }
    if !commitSubjects.isEmpty {
      lines.append("Commits: \(commitSubjects.prefix(3).joined(separator: "; "))")
    }
    if !changedFiles.isEmpty {
      lines.append("Files: \(changedFiles.prefix(6).joined(separator: "; "))")
    }
    return String(lines.joined(separator: "\n").prefix(1_500))
  }

  private func short(_ sha: String) -> String {
    String(sha.prefix(12))
  }
}

struct ProductExperimentGitRolloutResult: Equatable, Sendable {
  var config: ProductizationConfig
  var preview: ProductExperimentGitRolloutPreview
  var acceptedAfterSha: String
  var archiveBranchName: String?
}

enum ProductExperimentGitRolloutError: LocalizedError, Equatable {
  case unknownExperiment(String)
  case missingGitRepository(URL)
  case expectedDecision(
    experimentID: String,
    expected: ProductExperimentDecision,
    actual: ProductExperimentDecision
  )
  case missingExperimentSha(String)
  case staleExperimentSha(branchName: String, expected: String, actual: String)
  case detachedAcceptedBranch
  case dirtyAcceptedWorktree(String)
  case invalidBranchName(String)
  case gitCommandFailed(command: String, detail: String)

  var errorDescription: String? {
    switch self {
    case .unknownExperiment(let id):
      return "Product experiment \(id) was not found in productization state."
    case .missingGitRepository(let url):
      return "Product experiment rollout requires a git repository at \(url.path)."
    case .expectedDecision(let experimentID, let expected, let actual):
      return
        "Product experiment \(experimentID) must be \(expected.rawValue) before this git rollout, but it is \(actual.rawValue)."
    case .missingExperimentSha(let id):
      return "Product experiment \(id) has no recorded current commit sha."
    case .staleExperimentSha(let branchName, let expected, let actual):
      return
        "Product experiment branch \(branchName) is stale: state expected \(expected), but git has \(actual). Refresh productization state before rollout."
    case .detachedAcceptedBranch:
      return "Cannot promote into a detached HEAD. Check out the accepted product branch first."
    case .dirtyAcceptedWorktree(let status):
      return "Refusing product experiment rollout from a dirty accepted worktree:\n\(status)"
    case .invalidBranchName(let branch):
      return "Invalid product experiment rollout branch name: \(branch)."
    case .gitCommandFailed(let command, let detail):
      return "Git command failed (\(command)): \(detail)"
    }
  }
}

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

enum ProductExperimentGitRolloutWorkflow {
  static func preview(
    experimentID: String,
    in config: ProductizationConfig,
    repoURL: URL,
    acceptedBranchName: String? = nil
  ) async throws -> ProductExperimentGitRolloutPreview {
    guard CompassWorkspace.isGitRepository(repoURL) else {
      throw ProductExperimentGitRolloutError.missingGitRepository(repoURL)
    }
    guard let experiment = config.experiments.first(where: { $0.id == experimentID }) else {
      throw ProductExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    try await ProductExperimentGit.validateBranchName(experiment.branchName, in: repoURL)
    let acceptedBranch: String
    if let acceptedBranchName {
      acceptedBranch = acceptedBranchName
    } else {
      acceptedBranch = try await ProductExperimentGit.currentBranch(in: repoURL)
    }
    try await ProductExperimentGit.validateBranchName(acceptedBranch, in: repoURL)

    let actualExperimentSha = try await ProductExperimentGit.branchHead(
      experiment.branchName,
      in: repoURL
    )
    let acceptedBeforeSha = try await ProductExperimentGit.branchHead(acceptedBranch, in: repoURL)
    let mergeBaseSha = try await ProductExperimentGit.output(
      ["merge-base", acceptedBranch, experiment.branchName],
      in: repoURL,
      commandName: "merge-base \(acceptedBranch) \(experiment.branchName)"
    )
    let canFastForward = try await ProductExperimentGit.isAncestor(
      acceptedBranch,
      of: experiment.branchName,
      in: repoURL
    )
    let archiveBranchName = archiveBranchName(for: experiment, in: config)
    let changedFiles = try await ProductExperimentGit.lines(
      ["diff", "--name-status", "\(acceptedBranch)...\(experiment.branchName)"],
      in: repoURL,
      commandName: "diff \(acceptedBranch)...\(experiment.branchName)",
      maxLines: 12
    )
    let commitSubjects = try await ProductExperimentGit.lines(
      ["log", "--oneline", "--decorate=short", "--max-count=8", "\(acceptedBranch)..\(experiment.branchName)"],
      in: repoURL,
      commandName: "log \(acceptedBranch)..\(experiment.branchName)",
      maxLines: 8
    )
    return ProductExperimentGitRolloutPreview(
      experimentID: experiment.id,
      solutionID: experiment.solutionID,
      experimentBranchName: experiment.branchName,
      acceptedBranchName: acceptedBranch,
      archiveBranchName: archiveBranchName,
      expectedExperimentSha: experiment.currentSha,
      actualExperimentSha: actualExperimentSha,
      acceptedBeforeSha: acceptedBeforeSha,
      mergeBaseSha: mergeBaseSha,
      kind: experiment.decision == .kill
        ? .archive
        : (canFastForward ? .fastForwardPromotion : .mergePromotion),
      changedFiles: changedFiles,
      commitSubjects: commitSubjects
    )
  }

  static func promote(
    experimentID: String,
    in config: ProductizationConfig,
    repoURL: URL,
    evidenceIndex: ProductizationEvidenceIndex,
    acceptedBranchName: String? = nil,
    now: Date = Date(),
    decidedBy: String = "Productization Workbench"
  ) async throws -> ProductExperimentGitRolloutResult {
    guard let experimentIndex = config.experiments.firstIndex(where: { $0.id == experimentID })
    else {
      throw ProductExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    let experiment = config.experiments[experimentIndex]
    guard experiment.decision == .promote else {
      throw ProductExperimentGitRolloutError.expectedDecision(
        experimentID: experiment.id,
        expected: .promote,
        actual: experiment.decision
      )
    }
    guard let expectedSha = experiment.currentSha else {
      throw ProductExperimentGitRolloutError.missingExperimentSha(experiment.id)
    }
    try await ProductExperimentGit.ensureCleanWorktree(repoURL)
    let preview = try await preview(
      experimentID: experiment.id,
      in: config,
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
    guard preview.experimentStateMatchesBranch else {
      throw ProductExperimentGitRolloutError.staleExperimentSha(
        branchName: experiment.branchName,
        expected: expectedSha,
        actual: preview.actualExperimentSha
      )
    }

    _ = try await ProductExperimentGit.output(
      ["checkout", preview.acceptedBranchName],
      in: repoURL,
      commandName: "checkout \(preview.acceptedBranchName)",
      allowEmptyOutput: true
    )
    switch preview.kind {
    case .fastForwardPromotion:
      _ = try await ProductExperimentGit.output(
        ["merge", "--ff-only", experiment.branchName],
        in: repoURL,
        commandName: "merge --ff-only \(experiment.branchName)",
        allowEmptyOutput: true
      )
    case .mergePromotion:
      _ = try await ProductExperimentGit.output(
        ["merge", "--no-edit", experiment.branchName],
        in: repoURL,
        commandName: "merge --no-edit \(experiment.branchName)",
        allowEmptyOutput: true
      )
    case .archive:
      break
    }

    let acceptedAfterSha = try await ProductExperimentGit.branchHead(
      preview.acceptedBranchName,
      in: repoURL
    )
    let next = applyGitDecision(
      .promoted,
      to: config,
      experimentIndex: experimentIndex,
      summary:
        "Promoted \(experiment.title) from \(experiment.branchName) into \(preview.acceptedBranchName) using \(preview.kind.rawValue).",
      evidenceRunIDs: ProductExperimentRolloutWorkflow.evidenceRunIDs(
        for: experiment.id,
        evidenceIndex: evidenceIndex
      ),
      branchName: experiment.branchName,
      beforeSha: preview.acceptedBeforeSha,
      afterSha: acceptedAfterSha,
      now: now,
      decidedBy: decidedBy
    )
    return ProductExperimentGitRolloutResult(
      config: next,
      preview: preview,
      acceptedAfterSha: acceptedAfterSha,
      archiveBranchName: nil
    )
  }

  static func archive(
    experimentID: String,
    in config: ProductizationConfig,
    repoURL: URL,
    evidenceIndex: ProductizationEvidenceIndex,
    acceptedBranchName: String? = nil,
    now: Date = Date(),
    decidedBy: String = "Productization Workbench"
  ) async throws -> ProductExperimentGitRolloutResult {
    guard CompassWorkspace.isGitRepository(repoURL) else {
      throw ProductExperimentGitRolloutError.missingGitRepository(repoURL)
    }
    guard let experimentIndex = config.experiments.firstIndex(where: { $0.id == experimentID })
    else {
      throw ProductExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    let experiment = config.experiments[experimentIndex]
    guard experiment.decision == .kill else {
      throw ProductExperimentGitRolloutError.expectedDecision(
        experimentID: experiment.id,
        expected: .kill,
        actual: experiment.decision
      )
    }
    guard let expectedSha = experiment.currentSha else {
      throw ProductExperimentGitRolloutError.missingExperimentSha(experiment.id)
    }
    var preview = try await preview(
      experimentID: experiment.id,
      in: config,
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
    guard preview.experimentStateMatchesBranch else {
      throw ProductExperimentGitRolloutError.staleExperimentSha(
        branchName: experiment.branchName,
        expected: expectedSha,
        actual: preview.actualExperimentSha
      )
    }
    let archiveBranch = archiveBranchName(for: experiment, in: config)
    try await ProductExperimentGit.validateBranchName(archiveBranch, in: repoURL)
    _ = try await ProductExperimentGit.output(
      ["update-ref", "refs/heads/\(archiveBranch)", preview.actualExperimentSha],
      in: repoURL,
      commandName: "update-ref refs/heads/\(archiveBranch)",
      allowEmptyOutput: true
    )
    preview.archiveBranchName = archiveBranch
    preview.kind = .archive

    let next = applyGitDecision(
      .archived,
      to: config,
      experimentIndex: experimentIndex,
      summary:
        "Archived \(experiment.title) by preserving \(experiment.branchName) at \(preview.actualExperimentSha) and updating \(archiveBranch).",
      evidenceRunIDs: ProductExperimentRolloutWorkflow.evidenceRunIDs(
        for: experiment.id,
        evidenceIndex: evidenceIndex
      ),
      branchName: experiment.branchName,
      beforeSha: preview.actualExperimentSha,
      afterSha: preview.actualExperimentSha,
      now: now,
      decidedBy: decidedBy
    )
    return ProductExperimentGitRolloutResult(
      config: next,
      preview: preview,
      acceptedAfterSha: preview.acceptedBeforeSha,
      archiveBranchName: archiveBranch
    )
  }

  private static func applyGitDecision(
    _ target: ProductExperimentDecision,
    to config: ProductizationConfig,
    experimentIndex: Int,
    summary: String,
    evidenceRunIDs: [String],
    branchName: String,
    beforeSha: String,
    afterSha: String,
    now: Date,
    decidedBy: String
  ) -> ProductizationConfig {
    var next = config
    let experiment = next.experiments[experimentIndex]
    let timestamp = now.timeIntervalSince1970
    next.experiments[experimentIndex].decision = target
    next.experiments[experimentIndex].evidenceSummary = summary
    next.experiments[experimentIndex].updatedAt = timestamp
    if let solutionIndex = next.solutionHypotheses.firstIndex(where: { $0.id == experiment.solutionID }) {
      switch target {
      case .promoted:
        next.solutionHypotheses[solutionIndex].status = .promoted
      case .archived:
        next.solutionHypotheses[solutionIndex].status = .parked
      case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
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
        branchName: branchName,
        beforeSha: beforeSha,
        afterSha: afterSha,
        decidedAt: timestamp,
        decidedBy: decidedBy
      )
    )
    return next
  }

  private static func archiveBranchName(
    for experiment: ProductExperiment,
    in config: ProductizationConfig
  ) -> String {
    let solution = config.solutionHypotheses.first { $0.id == experiment.solutionID }
    let slug = ProductizationModelText.slug(
      solution?.title ?? experiment.solutionID,
      fallback: experiment.solutionID
    )
    return "compass/archive/\(slug)"
  }
}

extension CompassWorkspace {
  func productExperimentGitRolloutPreview(
    experimentID: String,
    acceptedBranchName: String? = nil
  ) async throws -> ProductExperimentGitRolloutPreview {
    try await ProductExperimentGitRolloutWorkflow.preview(
      experimentID: experimentID,
      in: try readProductizationConfig(),
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
  }

  @discardableResult
  func promoteProductExperiment(
    experimentID: String,
    acceptedBranchName: String? = nil,
    now: Date = Date()
  ) async throws -> ProductExperimentGitRolloutResult {
    let result = try await ProductExperimentGitRolloutWorkflow.promote(
      experimentID: experimentID,
      in: try readProductizationConfig(),
      repoURL: repoURL,
      evidenceIndex: readProductizationEvidenceIndex(),
      acceptedBranchName: acceptedBranchName,
      now: now
    )
    try writeProductizationConfig(result.config)
    return result
  }

  @discardableResult
  func archiveProductExperiment(
    experimentID: String,
    acceptedBranchName: String? = nil,
    now: Date = Date()
  ) async throws -> ProductExperimentGitRolloutResult {
    let result = try await ProductExperimentGitRolloutWorkflow.archive(
      experimentID: experimentID,
      in: try readProductizationConfig(),
      repoURL: repoURL,
      evidenceIndex: readProductizationEvidenceIndex(),
      acceptedBranchName: acceptedBranchName,
      now: now
    )
    try writeProductizationConfig(result.config)
    return result
  }
}

enum ProductExperimentGit {
  static func validateBranchName(_ branchName: String, in repoURL: URL) async throws {
    guard ProductExperimentGitRef.isPlausibleBranchName(branchName) else {
      throw ProductExperimentGitRolloutError.invalidBranchName(branchName)
    }
    let result = try await ProcessRunner.runEnv(
      "git",
      ["check-ref-format", "--branch", branchName],
      workingDirectory: repoURL,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw ProductExperimentGitRolloutError.invalidBranchName(branchName)
    }
  }

  static func currentBranch(in repoURL: URL) async throws -> String {
    let branch = try await output(
      ["rev-parse", "--abbrev-ref", "HEAD"],
      in: repoURL,
      commandName: "rev-parse --abbrev-ref HEAD"
    )
    guard branch != "HEAD" else {
      throw ProductExperimentGitRolloutError.detachedAcceptedBranch
    }
    return branch
  }

  static func branchHead(_ branchName: String, in repoURL: URL) async throws -> String {
    try await output(
      ["rev-parse", "\(branchName)^{commit}"],
      in: repoURL,
      commandName: "rev-parse \(branchName)"
    )
  }

  static func ensureCleanWorktree(_ repoURL: URL) async throws {
    let status = try await output(
      ["status", "--porcelain"],
      in: repoURL,
      commandName: "status --porcelain",
      allowEmptyOutput: true
    )
    guard status.isEmpty else {
      throw ProductExperimentGitRolloutError.dirtyAcceptedWorktree(status)
    }
  }

  static func isAncestor(_ ancestor: String, of descendant: String, in repoURL: URL) async throws
    -> Bool
  {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["merge-base", "--is-ancestor", ancestor, descendant],
      workingDirectory: repoURL,
      timeout: 30
    )
    if result.exitCode == 0 { return true }
    if result.exitCode == 1 { return false }
    throw ProductExperimentGitRolloutError.gitCommandFailed(
      command: "merge-base --is-ancestor \(ancestor) \(descendant)",
      detail: result.stderr + result.stdout
    )
  }

  static func lines(
    _ arguments: [String],
    in repoURL: URL,
    commandName: String,
    maxLines: Int
  ) async throws -> [String] {
    let raw = try await output(
      arguments,
      in: repoURL,
      commandName: commandName,
      allowEmptyOutput: true
    )
    return raw
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(maxLines)
      .map { String($0.prefix(220)) }
  }

  static func output(
    _ arguments: [String],
    in repoURL: URL,
    commandName: String,
    allowEmptyOutput: Bool = false
  ) async throws -> String {
    let result = try await ProcessRunner.runEnv(
      "git",
      arguments,
      workingDirectory: repoURL,
      timeout: 120
    )
    guard result.exitCode == 0 else {
      throw ProductExperimentGitRolloutError.gitCommandFailed(
        command: commandName,
        detail: result.stderr + result.stdout
      )
    }
    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return allowEmptyOutput ? output : output
  }

  static func commitMatches(expected: String, actual: String) -> Bool {
    let expected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
    let actual = actual.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !expected.isEmpty, !actual.isEmpty else { return false }
    return expected == actual || actual.hasPrefix(expected) || expected.hasPrefix(actual)
  }
}

@MainActor
extension CompassProject {
  func productExperimentGitRolloutPreview(
    experimentID: String
  ) async throws -> ProductExperimentGitRolloutPreview {
    guard let workspace else {
      throw AppModelError.noRepositorySelected
    }
    return try await workspace.productExperimentGitRolloutPreview(experimentID: experimentID)
  }

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
      if action == .promoteOrConfirm,
        productizationConfig.experiments.first(where: { $0.id == experimentID })?.decision == .promote
      {
        let result = try await workspace.promoteProductExperiment(experimentID: experimentID)
        productizationConfig = result.config
        log(
          "Promoted product experiment \(experimentID) into \(result.preview.acceptedBranchName) at \(String(result.acceptedAfterSha.prefix(12))).",
          level: .success
        )
        return
      }
      if action == .killOrArchive,
        productizationConfig.experiments.first(where: { $0.id == experimentID })?.decision == .kill
      {
        let result = try await workspace.archiveProductExperiment(experimentID: experimentID)
        productizationConfig = result.config
        log(
          "Archived product experiment \(experimentID) to \(result.archiveBranchName ?? "archive branch").",
          level: .success
        )
        return
      }
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
