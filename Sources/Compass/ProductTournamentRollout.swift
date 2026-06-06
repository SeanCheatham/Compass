import Foundation

enum ProductTournamentExperimentGitRolloutKind: String, Equatable, Sendable {
  case fastForwardPromotion = "fast_forward_promotion"
  case mergePromotion = "merge_promotion"
  case archive
}

struct ProductTournamentExperimentGitRolloutPreview: Equatable, Sendable {
  var experimentID: String
  var productHypothesisID: String
  var experimentBranchName: String
  var acceptedBranchName: String
  var archiveBranchName: String?
  var expectedExperimentSha: String?
  var actualExperimentSha: String
  var acceptedBeforeSha: String
  var mergeBaseSha: String
  var kind: ProductTournamentExperimentGitRolloutKind
  var changedFiles: [String]
  var commitSubjects: [String]

  var experimentStateMatchesBranch: Bool {
    guard let expectedExperimentSha else { return false }
    return ProductTournamentExperimentGit.commitMatches(
      expected: expectedExperimentSha, actual: actualExperimentSha)
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

struct ProductTournamentExperimentGitRolloutResult: Equatable, Sendable {
  var config: ProductTournamentConfig
  var preview: ProductTournamentExperimentGitRolloutPreview
  var acceptedAfterSha: String
  var archiveBranchName: String?
}

enum ProductTournamentExperimentGitRolloutError: LocalizedError, Equatable {
  case unknownExperiment(String)
  case missingGitRepository(URL)
  case expectedDecision(
    experimentID: String,
    expected: ProductTournamentExperimentDecision,
    actual: ProductTournamentExperimentDecision
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
      return "Tournament experiment \(id) was not found in product tournament state."
    case .missingGitRepository(let url):
      return "Tournament experiment rollout requires a git repository at \(url.path)."
    case .expectedDecision(let experimentID, let expected, let actual):
      return
        "Tournament experiment \(experimentID) must be \(expected.rawValue) before this git rollout, but it is \(actual.rawValue)."
    case .missingExperimentSha(let id):
      return "Tournament experiment \(id) has no recorded current commit sha."
    case .staleExperimentSha(let branchName, let expected, let actual):
      return
        "Tournament experiment branch \(branchName) is stale: state expected \(expected), but git has \(actual). Refresh product tournament state before rollout."
    case .detachedAcceptedBranch:
      return "Cannot promote into a detached HEAD. Check out the accepted product branch first."
    case .dirtyAcceptedWorktree(let status):
      return "Refusing tournament experiment rollout from a dirty accepted worktree:\n\(status)"
    case .invalidBranchName(let branch):
      return "Invalid tournament experiment rollout branch name: \(branch)."
    case .gitCommandFailed(let command, let detail):
      return "Git command failed (\(command)): \(detail)"
    }
  }
}

enum ProductTournamentExperimentRolloutAction: String, CaseIterable, Equatable, Sendable {
  case promoteOrConfirm
  case killOrArchive

  func targetDecision(from current: ProductTournamentExperimentDecision)
    -> ProductTournamentExperimentDecision
  {
    switch self {
    case .promoteOrConfirm:
      return current == .promote ? .promoted : .promote
    case .killOrArchive:
      return current == .kill ? .archived : .kill
    }
  }

  func title(from current: ProductTournamentExperimentDecision) -> String {
    switch self {
    case .promoteOrConfirm:
      return current == .promote ? "Promote" : "Mark Promote"
    case .killOrArchive:
      return current == .kill ? "Archive" : "Kill"
    }
  }
}

enum ProductTournamentExperimentRolloutError: LocalizedError, Equatable {
  case unknownExperiment(String)

  var errorDescription: String? {
    switch self {
    case .unknownExperiment(let id):
      return "Tournament experiment \(id) was not found in product tournament state."
    }
  }
}

enum ProductTournamentExperimentRolloutWorkflow {
  static func canApply(
    _ action: ProductTournamentExperimentRolloutAction,
    to experiment: ProductTournamentExperiment
  ) -> Bool {
    do {
      try ProductTournamentDecisionTransitionValidator.validate(
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
    _ action: ProductTournamentExperimentRolloutAction,
    experimentID: String,
    to config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    now: Date = Date(),
    decidedBy: String = "Product Tournament Workbench"
  ) throws -> ProductTournamentConfig {
    var next = config
    guard
      let experimentIndex = next.tournamentExperiments.firstIndex(where: { $0.id == experimentID })
    else {
      throw ProductTournamentExperimentRolloutError.unknownExperiment(experimentID)
    }

    let experiment = next.tournamentExperiments[experimentIndex]
    let target = action.targetDecision(from: experiment.decision)
    let summary = summary(for: action, experiment: experiment)
    try ProductTournamentDecisionTransitionValidator.validate(
      experimentID: experiment.id,
      from: experiment.decision,
      to: target,
      summary: summary
    )

    let timestamp = now.timeIntervalSince1970
    let evidenceRunIDs = evidenceRunIDs(for: experiment, evidenceIndex: evidenceIndex)
    let beforeSha = experiment.currentSha ?? experiment.baseSha

    next.tournamentExperiments[experimentIndex].decision = target
    next.tournamentExperiments[experimentIndex].evidenceSummary = summary
    next.tournamentExperiments[experimentIndex].updatedAt = timestamp

    if let productHypothesisIndex = next.productHypotheses.firstIndex(where: {
      $0.id == experiment.productHypothesisID
    }) {
      switch target {
      case .promoted:
        next.productHypotheses[productHypothesisIndex].status = .promoted
      case .kill:
        next.productHypotheses[productHypothesisIndex].status = .rejected
      case .archived:
        next.productHypotheses[productHypothesisIndex].status = .parked
      case .notRun, .keepGoing, .narrow, .pivot, .promote:
        break
      }
    }

    next.decisions.append(
      ProductTournamentDecision(
        id: "\(experiment.id)-\(target.rawValue)-\(Int(timestamp))-\(next.decisions.count + 1)",
        experimentID: experiment.id,
        decision: target,
        summary: summary,
        evidenceRunIDs: evidenceRunIDs,
        branchName: experiment.branchName,
        beforeSha: beforeSha,
        afterSha: next.tournamentExperiments[experimentIndex].currentSha
          ?? next.tournamentExperiments[experimentIndex].baseSha,
        decidedAt: timestamp,
        decidedBy: decidedBy
      )
    )
    return next
  }

  static func evidenceRunIDs(
    for experiment: ProductTournamentExperiment,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    evidenceIndex.summaries(for: experiment)
      .prefix(8)
      .map(\.runID)
  }

  private static func summary(
    for action: ProductTournamentExperimentRolloutAction,
    experiment: ProductTournamentExperiment
  ) -> String {
    switch action {
    case .promoteOrConfirm:
      if experiment.decision == .promote {
        return
          "Promoted \(experiment.title) from branch \(experiment.branchName) after product tournament evidence and Verify supported the product direction."
      }
      return
        "Marked \(experiment.title) promotion-ready; verify the branch, inspect evidence, and confirm before merging product direction."
    case .killOrArchive:
      if experiment.decision == .kill {
        return
          "Archived \(experiment.title) while preserving branch \(experiment.branchName), worktree \(experiment.worktreeID), and evidence."
      }
      return
        "Killed \(experiment.title) because the current tournament evidence does not justify continued investment."
    }
  }
}

enum ProductTournamentExperimentGitRolloutWorkflow {
  static func preview(
    experimentID: String,
    in config: ProductTournamentConfig,
    repoURL: URL,
    acceptedBranchName: String? = nil
  ) async throws -> ProductTournamentExperimentGitRolloutPreview {
    guard CompassWorkspace.isGitRepository(repoURL) else {
      throw ProductTournamentExperimentGitRolloutError.missingGitRepository(repoURL)
    }
    guard let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
    else {
      throw ProductTournamentExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    try await ProductTournamentExperimentGit.validateBranchName(experiment.branchName, in: repoURL)
    let acceptedBranch: String
    if let acceptedBranchName {
      acceptedBranch = acceptedBranchName
    } else {
      acceptedBranch = try await ProductTournamentExperimentGit.currentBranch(in: repoURL)
    }
    try await ProductTournamentExperimentGit.validateBranchName(acceptedBranch, in: repoURL)

    let actualExperimentSha = try await ProductTournamentExperimentGit.branchHead(
      experiment.branchName,
      in: repoURL
    )
    let acceptedBeforeSha = try await ProductTournamentExperimentGit.branchHead(
      acceptedBranch, in: repoURL)
    let mergeBaseSha = try await ProductTournamentExperimentGit.output(
      ["merge-base", acceptedBranch, experiment.branchName],
      in: repoURL,
      commandName: "merge-base \(acceptedBranch) \(experiment.branchName)"
    )
    let canFastForward = try await ProductTournamentExperimentGit.isAncestor(
      acceptedBranch,
      of: experiment.branchName,
      in: repoURL
    )
    let archiveBranchName = archiveBranchName(for: experiment, in: config)
    let changedFiles = try await ProductTournamentExperimentGit.lines(
      ["diff", "--name-status", "\(acceptedBranch)...\(experiment.branchName)"],
      in: repoURL,
      commandName: "diff \(acceptedBranch)...\(experiment.branchName)",
      maxLines: 12
    )
    let commitSubjects = try await ProductTournamentExperimentGit.lines(
      [
        "log", "--oneline", "--decorate=short", "--max-count=8",
        "\(acceptedBranch)..\(experiment.branchName)",
      ],
      in: repoURL,
      commandName: "log \(acceptedBranch)..\(experiment.branchName)",
      maxLines: 8
    )
    return ProductTournamentExperimentGitRolloutPreview(
      experimentID: experiment.id,
      productHypothesisID: experiment.productHypothesisID,
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
    in config: ProductTournamentConfig,
    repoURL: URL,
    evidenceIndex: ProductTournamentEvidenceIndex,
    acceptedBranchName: String? = nil,
    now: Date = Date(),
    decidedBy: String = "Product Tournament Workbench"
  ) async throws -> ProductTournamentExperimentGitRolloutResult {
    guard
      let experimentIndex = config.tournamentExperiments.firstIndex(where: { $0.id == experimentID }
      )
    else {
      throw ProductTournamentExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    let experiment = config.tournamentExperiments[experimentIndex]
    guard experiment.decision == .promote else {
      throw ProductTournamentExperimentGitRolloutError.expectedDecision(
        experimentID: experiment.id,
        expected: .promote,
        actual: experiment.decision
      )
    }
    guard let expectedSha = experiment.currentSha else {
      throw ProductTournamentExperimentGitRolloutError.missingExperimentSha(experiment.id)
    }
    try await ProductTournamentExperimentGit.ensureCleanWorktree(repoURL)
    let preview = try await preview(
      experimentID: experiment.id,
      in: config,
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
    guard preview.experimentStateMatchesBranch else {
      throw ProductTournamentExperimentGitRolloutError.staleExperimentSha(
        branchName: experiment.branchName,
        expected: expectedSha,
        actual: preview.actualExperimentSha
      )
    }

    _ = try await ProductTournamentExperimentGit.output(
      ["checkout", preview.acceptedBranchName],
      in: repoURL,
      commandName: "checkout \(preview.acceptedBranchName)",
      allowEmptyOutput: true
    )
    switch preview.kind {
    case .fastForwardPromotion:
      _ = try await ProductTournamentExperimentGit.output(
        ["merge", "--ff-only", experiment.branchName],
        in: repoURL,
        commandName: "merge --ff-only \(experiment.branchName)",
        allowEmptyOutput: true
      )
    case .mergePromotion:
      _ = try await ProductTournamentExperimentGit.output(
        ["merge", "--no-edit", experiment.branchName],
        in: repoURL,
        commandName: "merge --no-edit \(experiment.branchName)",
        allowEmptyOutput: true
      )
    case .archive:
      break
    }

    let acceptedAfterSha = try await ProductTournamentExperimentGit.branchHead(
      preview.acceptedBranchName,
      in: repoURL
    )
    let next = applyGitDecision(
      .promoted,
      to: config,
      experimentIndex: experimentIndex,
      summary:
        "Promoted \(experiment.title) from \(experiment.branchName) into \(preview.acceptedBranchName) using \(preview.kind.rawValue).",
      evidenceRunIDs: ProductTournamentExperimentRolloutWorkflow.evidenceRunIDs(
        for: experiment,
        evidenceIndex: evidenceIndex
      ),
      branchName: experiment.branchName,
      beforeSha: preview.acceptedBeforeSha,
      afterSha: acceptedAfterSha,
      now: now,
      decidedBy: decidedBy
    )
    return ProductTournamentExperimentGitRolloutResult(
      config: next,
      preview: preview,
      acceptedAfterSha: acceptedAfterSha,
      archiveBranchName: nil
    )
  }

  static func archive(
    experimentID: String,
    in config: ProductTournamentConfig,
    repoURL: URL,
    evidenceIndex: ProductTournamentEvidenceIndex,
    acceptedBranchName: String? = nil,
    now: Date = Date(),
    decidedBy: String = "Product Tournament Workbench"
  ) async throws -> ProductTournamentExperimentGitRolloutResult {
    guard CompassWorkspace.isGitRepository(repoURL) else {
      throw ProductTournamentExperimentGitRolloutError.missingGitRepository(repoURL)
    }
    guard
      let experimentIndex = config.tournamentExperiments.firstIndex(where: { $0.id == experimentID }
      )
    else {
      throw ProductTournamentExperimentGitRolloutError.unknownExperiment(experimentID)
    }
    let experiment = config.tournamentExperiments[experimentIndex]
    guard experiment.decision == .kill else {
      throw ProductTournamentExperimentGitRolloutError.expectedDecision(
        experimentID: experiment.id,
        expected: .kill,
        actual: experiment.decision
      )
    }
    guard let expectedSha = experiment.currentSha else {
      throw ProductTournamentExperimentGitRolloutError.missingExperimentSha(experiment.id)
    }
    var preview = try await preview(
      experimentID: experiment.id,
      in: config,
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
    guard preview.experimentStateMatchesBranch else {
      throw ProductTournamentExperimentGitRolloutError.staleExperimentSha(
        branchName: experiment.branchName,
        expected: expectedSha,
        actual: preview.actualExperimentSha
      )
    }
    let archiveBranch = archiveBranchName(for: experiment, in: config)
    try await ProductTournamentExperimentGit.validateBranchName(archiveBranch, in: repoURL)
    _ = try await ProductTournamentExperimentGit.output(
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
      evidenceRunIDs: ProductTournamentExperimentRolloutWorkflow.evidenceRunIDs(
        for: experiment,
        evidenceIndex: evidenceIndex
      ),
      branchName: experiment.branchName,
      beforeSha: preview.actualExperimentSha,
      afterSha: preview.actualExperimentSha,
      now: now,
      decidedBy: decidedBy
    )
    return ProductTournamentExperimentGitRolloutResult(
      config: next,
      preview: preview,
      acceptedAfterSha: preview.acceptedBeforeSha,
      archiveBranchName: archiveBranch
    )
  }

  private static func applyGitDecision(
    _ target: ProductTournamentExperimentDecision,
    to config: ProductTournamentConfig,
    experimentIndex: Int,
    summary: String,
    evidenceRunIDs: [String],
    branchName: String,
    beforeSha: String,
    afterSha: String,
    now: Date,
    decidedBy: String
  ) -> ProductTournamentConfig {
    var next = config
    let experiment = next.tournamentExperiments[experimentIndex]
    let timestamp = now.timeIntervalSince1970
    next.tournamentExperiments[experimentIndex].decision = target
    next.tournamentExperiments[experimentIndex].evidenceSummary = summary
    next.tournamentExperiments[experimentIndex].updatedAt = timestamp
    if let productHypothesisIndex = next.productHypotheses.firstIndex(where: {
      $0.id == experiment.productHypothesisID
    }) {
      switch target {
      case .promoted:
        next.productHypotheses[productHypothesisIndex].status = .promoted
      case .archived:
        next.productHypotheses[productHypothesisIndex].status = .parked
      case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
        break
      }
    }
    next.decisions.append(
      ProductTournamentDecision(
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
    for experiment: ProductTournamentExperiment,
    in config: ProductTournamentConfig
  ) -> String {
    let hypothesis = config.productHypotheses.first { $0.id == experiment.productHypothesisID }
    let slug = ProductTournamentModelText.slug(
      hypothesis?.title ?? experiment.productHypothesisID,
      fallback: experiment.productHypothesisID
    )
    return "compass/archive/\(slug)"
  }
}

extension CompassWorkspace {
  func productTournamentExperimentGitRolloutPreview(
    experimentID: String,
    acceptedBranchName: String? = nil
  ) async throws -> ProductTournamentExperimentGitRolloutPreview {
    try await ProductTournamentExperimentGitRolloutWorkflow.preview(
      experimentID: experimentID,
      in: try readProductTournamentConfig(),
      repoURL: repoURL,
      acceptedBranchName: acceptedBranchName
    )
  }

  @discardableResult
  func promoteProductTournamentExperiment(
    experimentID: String,
    acceptedBranchName: String? = nil,
    now: Date = Date()
  ) async throws -> ProductTournamentExperimentGitRolloutResult {
    let result = try await ProductTournamentExperimentGitRolloutWorkflow.promote(
      experimentID: experimentID,
      in: try readProductTournamentConfig(),
      repoURL: repoURL,
      evidenceIndex: readProductTournamentEvidenceIndex(),
      acceptedBranchName: acceptedBranchName,
      now: now
    )
    try writeProductTournamentConfig(result.config)
    return result
  }

  @discardableResult
  func archiveProductTournamentExperiment(
    experimentID: String,
    acceptedBranchName: String? = nil,
    now: Date = Date()
  ) async throws -> ProductTournamentExperimentGitRolloutResult {
    let result = try await ProductTournamentExperimentGitRolloutWorkflow.archive(
      experimentID: experimentID,
      in: try readProductTournamentConfig(),
      repoURL: repoURL,
      evidenceIndex: readProductTournamentEvidenceIndex(),
      acceptedBranchName: acceptedBranchName,
      now: now
    )
    try writeProductTournamentConfig(result.config)
    return result
  }
}

enum ProductTournamentExperimentGit {
  static func validateBranchName(_ branchName: String, in repoURL: URL) async throws {
    guard ProductTournamentExperimentGitRef.isPlausibleBranchName(branchName) else {
      throw ProductTournamentExperimentGitRolloutError.invalidBranchName(branchName)
    }
    let result = try await ProcessRunner.runEnv(
      "git",
      ["check-ref-format", "--branch", branchName],
      workingDirectory: repoURL,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw ProductTournamentExperimentGitRolloutError.invalidBranchName(branchName)
    }
  }

  static func currentBranch(in repoURL: URL) async throws -> String {
    let branch = try await output(
      ["rev-parse", "--abbrev-ref", "HEAD"],
      in: repoURL,
      commandName: "rev-parse --abbrev-ref HEAD"
    )
    guard branch != "HEAD" else {
      throw ProductTournamentExperimentGitRolloutError.detachedAcceptedBranch
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
      throw ProductTournamentExperimentGitRolloutError.dirtyAcceptedWorktree(status)
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
    throw ProductTournamentExperimentGitRolloutError.gitCommandFailed(
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
    return
      raw
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
      throw ProductTournamentExperimentGitRolloutError.gitCommandFailed(
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
  func productTournamentExperimentGitRolloutPreview(
    experimentID: String
  ) async throws -> ProductTournamentExperimentGitRolloutPreview {
    guard let workspace else {
      throw AppModelError.noRepositorySelected
    }
    return try await workspace.productTournamentExperimentGitRolloutPreview(
      experimentID: experimentID)
  }

  func applyProductTournamentExperimentRolloutAction(
    _ action: ProductTournamentExperimentRolloutAction,
    experimentID: String
  ) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      let actionTitle =
        productTournamentConfig.tournamentExperiments
        .first { $0.id == experimentID }
        .map { action.title(from: $0.decision) }
        ?? action.rawValue
      if action == .promoteOrConfirm,
        productTournamentConfig.tournamentExperiments.first(where: { $0.id == experimentID })?
          .decision == .promote
      {
        let result = try await workspace.promoteProductTournamentExperiment(
          experimentID: experimentID)
        productTournamentConfig = result.config
        log(
          "Promoted tournament experiment \(experimentID) into \(result.preview.acceptedBranchName) at \(String(result.acceptedAfterSha.prefix(12))).",
          level: .success
        )
        return
      }
      if action == .killOrArchive,
        productTournamentConfig.tournamentExperiments.first(where: { $0.id == experimentID })?
          .decision == .kill
      {
        let result = try await workspace.archiveProductTournamentExperiment(
          experimentID: experimentID)
        productTournamentConfig = result.config
        log(
          "Archived tournament experiment \(experimentID) to \(result.archiveBranchName ?? "archive branch").",
          level: .success
        )
        return
      }
      let next = try ProductTournamentExperimentRolloutWorkflow.applying(
        action,
        experimentID: experimentID,
        to: productTournamentConfig,
        evidenceIndex: productTournamentEvidenceIndex
      )
      try workspace.writeProductTournamentConfig(next)
      productTournamentConfig = next
      log(
        "\(actionTitle) recorded for tournament experiment \(experimentID).",
        level: .success
      )
    } catch {
      fail(error)
    }
  }

  func applyProductTournamentDecisionRecommendation(experimentID: String) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      guard
        let proposal = ProductTournamentDecisionAdvisor.proposal(
          experimentID: experimentID,
          config: productTournamentConfig,
          evidenceIndex: productTournamentEvidenceIndex
        )
      else {
        throw ProductTournamentDecisionAdvisorError.noProposal(experimentID)
      }
      let next = try ProductTournamentDecisionAdvisor.applyingRecommendedDecision(
        experimentID: experimentID,
        to: productTournamentConfig,
        evidenceIndex: productTournamentEvidenceIndex
      )
      try workspace.writeProductTournamentConfig(next)
      productTournamentConfig = next
      log(
        "Applied tournament recommendation for tournament experiment \(experimentID): \(proposal.currentDecision.rawValue) -> \(proposal.update.decision.rawValue).",
        level: .success
      )
    } catch {
      fail(error)
    }
  }
}
