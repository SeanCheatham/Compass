import Foundation

public enum HealthBranchError: LocalizedError, Equatable {
  case notAGitRepository(String)
  case dirtyWorkingTree(String)
  case gitFailed(String)
  case missingSHA

  public var errorDescription: String? {
    switch self {
    case .notAGitRepository(let path):
      return "Not a Git repository: \(path)"
    case .dirtyWorkingTree(let detail):
      return "Working tree is dirty; commit or stash before a health pass. \(detail)"
    case .gitFailed(let detail):
      return "Git failed: \(detail)"
    case .missingSHA:
      return "Could not resolve HEAD SHA."
    }
  }
}

/// Compass-owned branch choreography for imported health projects.
public enum HealthBranch {
  public struct Session: Equatable, Sendable {
    public var previousRef: String
    public var baseSHA: String
    public var healthBranch: String

    public init(previousRef: String, baseSHA: String, healthBranch: String) {
      self.previousRef = previousRef
      self.baseSHA = baseSHA
      self.healthBranch = healthBranch
    }
  }

  public static func branchName(projectId: UUID) -> String {
    "compass/health/\(projectId.uuidString.lowercased())"
  }

  public static func branchName(projectId: String) -> String {
    let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = trimmed.isEmpty ? UUID().uuidString.lowercased() : trimmed.lowercased()
    return "compass/health/\(safe)"
  }

  /// Refuse dirty trees, record base, create/reset health branch, check it out.
  ///
  /// Uses `git checkout -B` so a retry still works when a previous pass left
  /// this worktree on the health branch (`git branch -f` refuses that).
  public static func begin(repoURL: URL, projectId: String) throws -> Session {
    try requireGitRepo(repoURL)
    try requireClean(repoURL)
    let branch = branchName(projectId: projectId)
    let current = try currentRef(repoURL)
    // If a crashed pass left us on the health branch, restore to the user's
    // mainline after the pass and rebase the health tip onto that mainline.
    let previousRef: String
    let baseRev: String
    if current == branch {
      if let userBranch = try preferredUserBranch(repoURL) {
        previousRef = userBranch
        baseRev = userBranch
      } else {
        previousRef = current
        baseRev = "HEAD"
      }
    } else {
      previousRef = current
      baseRev = "HEAD"
    }
    let baseSHA = try revParse(repoURL, rev: baseRev)
    try runGit(repoURL, args: ["checkout", "-B", branch, baseSHA])
    return Session(previousRef: previousRef, baseSHA: baseSHA, healthBranch: branch)
  }

  public static func commitIfDirty(repoURL: URL, message: String) throws -> String? {
    let status = try runGitOutput(repoURL, args: ["status", "--porcelain"])
    if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return nil
    }
    try runGit(repoURL, args: ["add", "-A"])
    try runGit(repoURL, args: ["commit", "-m", message])
    return try revParse(repoURL, rev: "HEAD")
  }

  public static func end(repoURL: URL, session: Session) throws {
    let current = (try? currentRef(repoURL)) ?? ""
    if current == session.previousRef { return }
    try runGit(repoURL, args: ["checkout", session.previousRef])
  }

  public static func tipSHA(repoURL: URL) throws -> String {
    try revParse(repoURL, rev: "HEAD")
  }

  public static func commits(repoURL: URL, baseSHA: String, tipSHA: String) throws
    -> [HealthCommitSummary]
  {
    if baseSHA == tipSHA { return [] }
    let range = "\(baseSHA)..\(tipSHA)"
    let output = try runGitOutput(
      repoURL,
      args: ["log", "--format=%H%x09%s", range]
    )
    return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return nil }
      return HealthCommitSummary(sha: String(parts[0]), subject: String(parts[1]))
    }
  }

  /// Prefer a normal user branch when recovering from a health-branch checkout.
  private static func preferredUserBranch(_ repoURL: URL) throws -> String? {
    for name in ["main", "master"] where try branchExists(repoURL, name: name) {
      return name
    }
    return nil
  }

  private static func requireGitRepo(_ repoURL: URL) throws {
    let gitDir = repoURL.appending(path: ".git")
    guard FileManager.default.fileExists(atPath: gitDir.path) else {
      throw HealthBranchError.notAGitRepository(repoURL.path)
    }
  }

  private static func requireClean(_ repoURL: URL) throws {
    let status = try runGitOutput(repoURL, args: ["status", "--porcelain"])
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      throw HealthBranchError.dirtyWorkingTree(String(trimmed.prefix(500)))
    }
  }

  private static func currentRef(_ repoURL: URL) throws -> String {
    if let branch = try? runGitOutput(repoURL, args: ["symbolic-ref", "--short", "HEAD"]) {
      let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { return name }
    }
    return try revParse(repoURL, rev: "HEAD")
  }

  private static func branchExists(_ repoURL: URL, name: String) throws -> Bool {
    let result = try runGitResult(repoURL, args: ["show-ref", "--verify", "--quiet", "refs/heads/\(name)"])
    return result.exitCode == 0
  }

  private static func revParse(_ repoURL: URL, rev: String) throws -> String {
    let sha = try runGitOutput(repoURL, args: ["rev-parse", rev])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sha.isEmpty else { throw HealthBranchError.missingSHA }
    return sha
  }

  @discardableResult
  private static func runGit(_ repoURL: URL, args: [String]) throws -> String {
    let result = try runGitResult(repoURL, args: args)
    if result.exitCode != 0 {
      let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw HealthBranchError.gitFailed(detail.isEmpty ? "git \(args.joined(separator: " "))" : detail)
    }
    return result.stdout
  }

  private static func runGitOutput(_ repoURL: URL, args: [String]) throws -> String {
    try runGit(repoURL, args: args)
  }

  private static func runGitResult(_ repoURL: URL, args: [String]) throws -> (
    exitCode: Int32, stdout: String, stderr: String
  ) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repoURL.path] + args
    process.currentDirectoryURL = repoURL
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    return (
      process.terminationStatus,
      String(data: outData, encoding: .utf8) ?? "",
      String(data: errData, encoding: .utf8) ?? ""
    )
  }
}
