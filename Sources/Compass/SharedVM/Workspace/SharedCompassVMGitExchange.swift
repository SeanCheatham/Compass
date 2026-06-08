import Foundation

struct SharedCompassVMGitContext: Equatable {
  var repoID: String
  var branchName: String
  var baselineHostSHA: String
  var exchangeRepoURL: URL
  var remoteURL: String

  var branchRef: String { "refs/heads/\(branchName)" }
}

enum SharedCompassVMGitExchange {
  static let exchangeRepoDirectoryName = "git-exchange.git"
  static let remoteName = "origin"

  enum ExchangeError: LocalizedError, CustomStringConvertible, Equatable {
    case notGitRepository(String)
    case dirtyHostCheckout(String)
    case detachedHead(String)
    case invalidRepoID(String)
    case invalidRef(String)
    case commandFailed(String)
    case hostAdvanced(expected: String, actual: String)
    case promotionNotFastForward(String)

    var description: String {
      switch self {
      case .notGitRepository(let detail):
        return "host checkout is not a git repository: \(detail)"
      case .dirtyHostCheckout(let status):
        return "host checkout has uncommitted changes; commit or stash them first:\n\(status)"
      case .detachedHead(let detail):
        return
          "host checkout is detached; check out a branch before using guest git mode: \(detail)"
      case .invalidRepoID(let id):
        return "invalid Compass guest repo id: \(id)"
      case .invalidRef(let ref):
        return "invalid git ref: \(ref)"
      case .commandFailed(let detail):
        return detail
      case .hostAdvanced(let expected, let actual):
        return
          "host branch advanced while the guest was working (expected \(expected), found \(actual)); rebase in the guest and retry."
      case .promotionNotFastForward(let detail):
        return "guest commits cannot be promoted as a fast-forward: \(detail)"
      }
    }

    var errorDescription: String? { description }
  }

  static func exchangeRepoURL(forHostRepoURL repoURL: URL) -> URL {
    CompassWorkspace.repoLocalStorageRootURL(for: repoURL)
      .appending(path: exchangeRepoDirectoryName, directoryHint: .isDirectory)
  }

  static func remoteURL(repoID: String) -> String {
    "compass::\(repoID)"
  }

  static func stagingRef(repoID: String, sessionNumber: Int, branchName: String) throws -> String {
    guard isValidRepoID(repoID) else { throw ExchangeError.invalidRepoID(repoID) }
    let ref = "refs/compass/staging/\(repoID)/session-\(sessionNumber)/\(branchName)"
    try validateRef(ref)
    return ref
  }

  @discardableResult
  static func prepare(
    hostRepoURL: URL,
    repoID: String
  ) async throws -> SharedCompassVMGitContext {
    guard isValidRepoID(repoID) else { throw ExchangeError.invalidRepoID(repoID) }
    let host = hostRepoURL.standardizedFileURL
    try await preflightHostCheckout(host)
    let branchName = try await currentBranch(in: host)
    let branchRef = "refs/heads/\(branchName)"
    try validateRef(branchRef)
    let baseline = try await currentHEAD(in: host)
    let exchange = exchangeRepoURL(forHostRepoURL: host)
    try await ensureExchangeRepo(at: exchange, repoID: repoID)
    try await refreshExchange(
      exchangeRepoURL: exchange,
      hostRepoURL: host,
      branchRef: branchRef
    )
    try await runGitOrThrow(
      ["symbolic-ref", "HEAD", branchRef],
      gitDirectory: exchange,
      failurePrefix: "Failed to point Compass git exchange HEAD at host branch"
    )
    return SharedCompassVMGitContext(
      repoID: repoID,
      branchName: branchName,
      baselineHostSHA: baseline,
      exchangeRepoURL: exchange,
      remoteURL: remoteURL(repoID: repoID)
    )
  }

  static func promote(
    stagingRef: String,
    context: SharedCompassVMGitContext,
    hostRepoURL: URL
  ) async throws {
    try validateRef(stagingRef)
    let host = hostRepoURL.standardizedFileURL
    try await preflightHostCheckout(host)
    let currentBranchName = try await currentBranch(in: host)
    guard currentBranchName == context.branchName else {
      throw ExchangeError.hostAdvanced(
        expected: context.branchName,
        actual: currentBranchName
      )
    }
    let current = try await currentHEAD(in: host)
    guard current == context.baselineHostSHA else {
      throw ExchangeError.hostAdvanced(expected: context.baselineHostSHA, actual: current)
    }

    let stagingSHA = try await revParse(
      stagingRef,
      gitDirectory: context.exchangeRepoURL
    )
    let ancestor = try await runGit(
      ["merge-base", "--is-ancestor", current, stagingSHA],
      gitDirectory: context.exchangeRepoURL
    )
    guard ancestor.exitCode == 0 else {
      throw ExchangeError.promotionNotFastForward(ancestor.stderr + ancestor.stdout)
    }

    try await runGitOrThrow(
      ["fetch", context.exchangeRepoURL.path, stagingRef],
      workingDirectory: host,
      failurePrefix: "Failed to fetch staged guest commits into host checkout"
    )
    try await runGitOrThrow(
      ["merge", "--ff-only", "FETCH_HEAD"],
      workingDirectory: host,
      failurePrefix: "Failed to fast-forward host branch to guest commits"
    )
  }

  static func isValidRepoID(_ id: String) -> Bool {
    guard UUID(uuidString: id) != nil else { return false }
    return id == id.lowercased()
  }

  static func validateRef(_ ref: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "check-ref-format", ref]
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      throw ExchangeError.invalidRef(ref)
    }
  }

  private static func preflightHostCheckout(_ repoURL: URL) async throws {
    let isRepo = try await ProcessRunner.runEnv(
      "git",
      ["rev-parse", "--is-inside-work-tree"],
      workingDirectory: repoURL,
      timeout: 10
    )
    guard isRepo.exitCode == 0,
      isRepo.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    else {
      throw ExchangeError.notGitRepository(isRepo.stderr + isRepo.stdout)
    }

    let status = try await ProcessRunner.runEnv(
      "git",
      ["status", "--porcelain"],
      workingDirectory: repoURL,
      timeout: 30
    )
    guard status.exitCode == 0 else {
      throw ExchangeError.commandFailed("Failed to inspect host git status: \(status.stderr)")
    }
    let trimmed = status.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty else {
      throw ExchangeError.dirtyHostCheckout(trimmed)
    }
  }

  private static func currentBranch(in repoURL: URL) async throws -> String {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["symbolic-ref", "--short", "HEAD"],
      workingDirectory: repoURL,
      timeout: 10
    )
    guard result.exitCode == 0 else {
      throw ExchangeError.detachedHead(result.stderr + result.stdout)
    }
    let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !branch.isEmpty else {
      throw ExchangeError.detachedHead("empty branch name")
    }
    return branch
  }

  private static func currentHEAD(in repoURL: URL) async throws -> String {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["rev-parse", "HEAD"],
      workingDirectory: repoURL,
      timeout: 10
    )
    guard result.exitCode == 0 else {
      throw ExchangeError.commandFailed("Failed to resolve host HEAD: \(result.stderr)")
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func revParse(_ ref: String, gitDirectory: URL) async throws -> String {
    let result = try await runGit(
      ["rev-parse", ref],
      gitDirectory: gitDirectory
    )
    guard result.exitCode == 0 else {
      throw ExchangeError.commandFailed(result.stderr + result.stdout)
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func ensureExchangeRepo(at url: URL, repoID: String) async throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if !fileManager.fileExists(atPath: url.appending(path: "HEAD").path) {
      try await runGitOrThrow(
        ["init", "--bare", url.path],
        workingDirectory: nil,
        failurePrefix: "Failed to initialise Compass git exchange repo"
      )
    }
    try await configureExchangeRepo(at: url, repoID: repoID)
  }

  private static func configureExchangeRepo(at url: URL, repoID: String) async throws {
    try await runGitOrThrow(
      ["config", "receive.denyDeletes", "true"],
      gitDirectory: url,
      failurePrefix: "Failed to configure Compass git exchange repo"
    )
    try await runGitOrThrow(
      ["config", "receive.denyNonFastForwards", "true"],
      gitDirectory: url,
      failurePrefix: "Failed to configure Compass git exchange repo"
    )
    let hooks = url.appending(path: "hooks", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
    let hookURL = hooks.appending(path: "pre-receive")
    let hook = """
      #!/bin/sh
      zero=0000000000000000000000000000000000000000
      while read old new ref
      do
        case "$ref" in
          refs/compass/staging/\(repoID)/*) ;;
          *)
            echo "Compass exchange rejects direct guest updates to $ref" >&2
            exit 1
            ;;
        esac
        if [ "$new" = "$zero" ]; then
          echo "Compass exchange rejects deletes for $ref" >&2
          exit 1
        fi
        if [ "$old" != "$zero" ]; then
          if ! git merge-base --is-ancestor "$old" "$new"; then
            echo "Compass exchange rejects non-fast-forward update to $ref" >&2
            exit 1
          fi
        fi
      done
      exit 0
      """
    try Data(hook.utf8).write(to: hookURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: hookURL.path
    )
  }

  private static func refreshExchange(
    exchangeRepoURL: URL,
    hostRepoURL: URL,
    branchRef: String
  ) async throws {
    try await runGitOrThrow(
      [
        "fetch",
        "--prune",
        hostRepoURL.path,
        "+\(branchRef):\(branchRef)",
        "+refs/tags/*:refs/tags/*",
      ],
      gitDirectory: exchangeRepoURL,
      failurePrefix: "Failed to refresh Compass git exchange repo from host checkout"
    )
  }

  @discardableResult
  private static func runGit(
    _ arguments: [String],
    gitDirectory: URL
  ) async throws -> ProcessResult {
    try await ProcessRunner.runEnv(
      "git",
      ["--git-dir", gitDirectory.path] + arguments,
      timeout: 60
    )
  }

  private static func runGitOrThrow(
    _ arguments: [String],
    workingDirectory: URL?,
    failurePrefix: String
  ) async throws {
    let result = try await ProcessRunner.runEnv(
      "git",
      arguments,
      workingDirectory: workingDirectory,
      timeout: 60
    )
    guard result.exitCode == 0 else {
      throw ExchangeError.commandFailed(
        "\(failurePrefix): \(result.stderr)\(result.stdout)"
      )
    }
  }

  private static func runGitOrThrow(
    _ arguments: [String],
    gitDirectory: URL,
    failurePrefix: String
  ) async throws {
    let result = try await runGit(
      arguments,
      gitDirectory: gitDirectory
    )
    guard result.exitCode == 0 else {
      throw ExchangeError.commandFailed(
        "\(failurePrefix): \(result.stderr)\(result.stdout)"
      )
    }
  }
}
