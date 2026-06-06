import Foundation

struct ProductExperimentWorktree: Equatable {
  var experimentID: String
  var branchName: String
  var worktreeURL: URL
  var baseSha: String
  var currentSha: String
}

struct ProductExperimentSimulationTarget: Codable, Equatable, Sendable {
  var experimentID: String
  var branchName: String
  var commitSha: String
  var scenarioCohortID: String

  init(
    experimentID: String,
    branchName: String,
    commitSha: String,
    scenarioCohortID: String
  ) {
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.branchName = StringUtils.boundedText(branchName, limit: 240)
    self.commitSha = StringUtils.boundedText(commitSha, limit: 80)
    self.scenarioCohortID = ProductTournamentModelText.identifier(
      scenarioCohortID,
      fallback: "cohort"
    )
  }

  var readOnlyKey: String {
    [experimentID, branchName, commitSha, scenarioCohortID].joined(separator: "|")
  }
}

enum ProductExperimentWorktreeError: LocalizedError, Equatable {
  case experimentNotFound(String)
  case missingGitRepository(URL)
  case invalidBranchName(String)
  case dirtyBaseWorktree(String)
  case worktreePathCollision(URL)
  case worktreeOnUnexpectedBranch(expected: String, actual: String)
  case gitCommandFailed(command: String, detail: String)

  var errorDescription: String? {
    switch self {
    case .experimentNotFound(let id):
      return "Product experiment \(id) was not found in productization state."
    case .missingGitRepository(let url):
      return "Product experiment worktrees require a git repository at \(url.path)."
    case .invalidBranchName(let branch):
      return "Invalid product experiment branch name: \(branch)."
    case .dirtyBaseWorktree(let status):
      return "Refusing to create an experiment branch from a dirty base worktree:\n\(status)"
    case .worktreePathCollision(let url):
      return "Product experiment worktree path exists but is not a git worktree: \(url.path)."
    case .worktreeOnUnexpectedBranch(let expected, let actual):
      return "Product experiment worktree is on \(actual), expected \(expected)."
    case .gitCommandFailed(let command, let detail):
      return "Git command failed (\(command)): \(detail)"
    }
  }
}

enum ProductExperimentGitRef {
  static func isPlausibleBranchName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == value, !trimmed.isEmpty, trimmed.count <= 240 else { return false }
    guard !trimmed.hasPrefix("-") && !trimmed.hasPrefix("/") && !trimmed.hasSuffix("/") else {
      return false
    }
    guard !trimmed.contains("..") && !trimmed.contains("@{") else { return false }
    guard !trimmed.hasSuffix(".") && !trimmed.hasSuffix(".lock") else { return false }
    let forbidden = CharacterSet(charactersIn: #" ~^:?*[\\"#)
    guard trimmed.rangeOfCharacter(from: forbidden) == nil else { return false }
    return trimmed.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
      !component.isEmpty && !component.hasPrefix(".") && !component.hasSuffix(".lock")
    }
  }
}

enum ProductExperimentWorktreeManager {
  static func ensureWorktree(
    for experiment: ProductExperiment,
    in workspace: CompassWorkspace
  ) async throws -> ProductExperimentWorktree {
    guard CompassWorkspace.isGitRepository(workspace.repoURL) else {
      throw ProductExperimentWorktreeError.missingGitRepository(workspace.repoURL)
    }
    try await validateBranchName(experiment.branchName, in: workspace.repoURL)
    try await ensureBaseWorktreeClean(workspace.repoURL)

    let baseSha = try await gitOutput(
      ["rev-parse", "HEAD"],
      in: workspace.repoURL,
      commandName: "rev-parse HEAD"
    )
    if !(try await branchExists(experiment.branchName, in: workspace.repoURL)) {
      _ = try await gitOutput(
        ["branch", experiment.branchName, baseSha],
        in: workspace.repoURL,
        commandName: "branch \(experiment.branchName)"
      )
    }

    let worktreeURL = workspace.productExperimentWorktreeURL(experimentID: experiment.id)
    let fm = FileManager.default
    if fm.fileExists(atPath: worktreeURL.path) {
      guard try await isGitWorktree(worktreeURL) else {
        throw ProductExperimentWorktreeError.worktreePathCollision(worktreeURL)
      }
      let actualBranch = try await gitOutput(
        ["rev-parse", "--abbrev-ref", "HEAD"],
        in: worktreeURL,
        commandName: "worktree branch"
      )
      guard actualBranch == experiment.branchName else {
        throw ProductExperimentWorktreeError.worktreeOnUnexpectedBranch(
          expected: experiment.branchName,
          actual: actualBranch
        )
      }
    } else {
      try fm.createDirectory(
        at: worktreeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      _ = try await gitOutput(
        ["worktree", "add", worktreeURL.path, experiment.branchName],
        in: workspace.repoURL,
        commandName: "worktree add"
      )
    }

    let currentSha = try await gitOutput(
      ["rev-parse", "HEAD"],
      in: worktreeURL,
      commandName: "worktree rev-parse HEAD"
    )
    return ProductExperimentWorktree(
      experimentID: experiment.id,
      branchName: experiment.branchName,
      worktreeURL: worktreeURL,
      baseSha: experiment.baseSha ?? baseSha,
      currentSha: currentSha
    )
  }

  private static func validateBranchName(_ branchName: String, in repoURL: URL) async throws {
    guard ProductExperimentGitRef.isPlausibleBranchName(branchName) else {
      throw ProductExperimentWorktreeError.invalidBranchName(branchName)
    }
    let result = try await ProcessRunner.runEnv(
      "git",
      ["check-ref-format", "--branch", branchName],
      workingDirectory: repoURL,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw ProductExperimentWorktreeError.invalidBranchName(branchName)
    }
  }

  private static func ensureBaseWorktreeClean(_ repoURL: URL) async throws {
    let status = try await gitOutput(
      ["status", "--porcelain"],
      in: repoURL,
      commandName: "status --porcelain",
      allowEmptyOutput: true
    )
    guard status.isEmpty else {
      throw ProductExperimentWorktreeError.dirtyBaseWorktree(status)
    }
  }

  private static func branchExists(_ branchName: String, in repoURL: URL) async throws -> Bool {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["show-ref", "--verify", "--quiet", "refs/heads/\(branchName)"],
      workingDirectory: repoURL,
      timeout: 30
    )
    if result.exitCode == 0 { return true }
    if result.exitCode == 1 { return false }
    throw ProductExperimentWorktreeError.gitCommandFailed(
      command: "show-ref \(branchName)",
      detail: result.stderr + result.stdout
    )
  }

  private static func isGitWorktree(_ url: URL) async throws -> Bool {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["rev-parse", "--is-inside-work-tree"],
      workingDirectory: url,
      timeout: 30
    )
    return result.exitCode == 0
      && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
  }

  private static func gitOutput(
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
      throw ProductExperimentWorktreeError.gitCommandFailed(
        command: commandName,
        detail: result.stderr + result.stdout
      )
    }
    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return allowEmptyOutput ? output : output
  }
}

extension CompassWorkspace {
  func productExperimentWorktreeURL(experimentID: String) -> URL {
    productTournamentURL
      .appending(path: "worktrees", directoryHint: .isDirectory)
      .appending(path: ProductTournamentModelText.identifier(experimentID, fallback: "experiment"))
  }

  @discardableResult
  func prepareProductExperimentWorktree(
    experimentID: String
  ) async throws -> ProductExperimentWorktree {
    var config = try readProductTournamentConfig()
    guard let index = config.experiments.firstIndex(where: { $0.id == experimentID }) else {
      throw ProductExperimentWorktreeError.experimentNotFound(experimentID)
    }
    let prepared = try await ProductExperimentWorktreeManager.ensureWorktree(
      for: config.experiments[index],
      in: self
    )
    if config.experiments[index].baseSha == nil {
      config.experiments[index].baseSha = prepared.baseSha
    }
    config.experiments[index].currentSha = prepared.currentSha
    config.experiments[index].updatedAt = Date().timeIntervalSince1970
    try writeProductTournamentConfig(config)
    return prepared
  }
}
