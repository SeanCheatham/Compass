import Foundation

enum SharedCompassVMGitStateStore {
  private static let lock = NSLock()
  private static var contextsByHostPath: [String: SharedCompassVMGitContext] = [:]

  static func record(_ context: SharedCompassVMGitContext, forHostRepoURL repoURL: URL) {
    lock.lock()
    contextsByHostPath[repoURL.standardizedFileURL.path] = context
    lock.unlock()
  }

  static func context(forHostRepoURL repoURL: URL) -> SharedCompassVMGitContext? {
    lock.lock()
    defer { lock.unlock() }
    return contextsByHostPath[repoURL.standardizedFileURL.path]
  }
}

enum SharedCompassVMGitWorkspaceSync {
  enum SyncError: LocalizedError, CustomStringConvertible {
    case missingCatalogEntry
    case helperInstallFailed(exitCode: Int32, stderr: String)
    case cloneOrUpdateFailed(exitCode: Int32, stderr: String)
    case invalidGuestPath(String)

    var description: String {
      switch self {
      case .missingCatalogEntry:
        return "missing guest workspace catalog entry"
      case .helperInstallFailed(let exitCode, let stderr):
        return "git remote helper install failed (exit \(exitCode)): \(stderr)"
      case .cloneOrUpdateFailed(let exitCode, let stderr):
        return "guest git clone/update failed (exit \(exitCode)): \(stderr)"
      case .invalidGuestPath(let path):
        return "refusing to use suspicious guest git workspace path: \(path)"
      }
    }

    var errorDescription: String? { description }
  }

  enum Outcome: Equatable {
    case cloned
    case alreadyCurrent
    case resetToHost
    case preservedLocalCommits
    case rebasedLocalCommits
  }

  static func ensurePopulated(
    hostRepoURL: URL,
    client: AgentVsockClient
  ) async throws -> (guestPath: String, context: SharedCompassVMGitContext, outcome: Outcome) {
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: hostRepoURL)
    let guestPath = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    try validateGuestPath(guestPath)

    let context = try await SharedCompassVMGitExchange.prepare(
      hostRepoURL: hostRepoURL,
      repoID: entry.id
    )
    SharedCompassVMGitService.shared.register(
      repoID: entry.id,
      exchangeRepoURL: context.exchangeRepoURL
    )
    SharedCompassVMGitStateStore.record(context, forHostRepoURL: hostRepoURL)

    try await ensureRemoteHelperInstalled(client: client)
    let outcome = try await cloneOrUpdateGuestWorkspace(
      guestPath: guestPath,
      context: context,
      client: client
    )
    return (guestPath, context, outcome)
  }

  private static func ensureRemoteHelperInstalled(client: AgentVsockClient) async throws {
    let command = """
      set -euo pipefail
      sudo /bin/mkdir -p /usr/local/bin
      sudo /bin/ln -sf /usr/local/libexec/compass-guest-agent /usr/local/bin/git-remote-compass
      sudo /bin/chmod 0755 /usr/local/libexec/compass-guest-agent
      /usr/local/bin/git-remote-compass --version >/dev/null
      """
    let result = try await client.run(
      command: command,
      workingDirectory: URL(fileURLWithPath: "/"),
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw SyncError.helperInstallFailed(exitCode: result.exitCode, stderr: result.stderr)
    }
  }

  private static func cloneOrUpdateGuestWorkspace(
    guestPath: String,
    context: SharedCompassVMGitContext,
    client: AgentVsockClient
  ) async throws -> Outcome {
    let quotedGuest = SharedCompassVMGuestBridge.posixQuote(guestPath)
    let quotedRemote = SharedCompassVMGuestBridge.posixQuote(context.remoteURL)
    let quotedBranch = SharedCompassVMGuestBridge.posixQuote(context.branchName)
    let command = """
      set -euo pipefail
      export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
      GUEST_PATH=\(quotedGuest)
      REMOTE_URL=\(quotedRemote)
      BRANCH=\(quotedBranch)
      if [ ! -d "$GUEST_PATH/.git" ]; then
        rm -rf "$GUEST_PATH"
        mkdir -p "$(dirname "$GUEST_PATH")"
        git clone --branch "$BRANCH" "$REMOTE_URL" "$GUEST_PATH"
        cd "$GUEST_PATH"
        git config user.name "Compass Agent"
        git config user.email "compass-agent@localhost"
        echo COMPASS_GIT_OUTCOME=cloned
        exit 0
      fi

      cd "$GUEST_PATH"
      git config user.name "Compass Agent"
      git config user.email "compass-agent@localhost"
      git remote set-url origin "$REMOTE_URL"
      git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" --tags
      if ! git rev-parse --verify --quiet "$BRANCH" >/dev/null; then
        git checkout -b "$BRANCH" "origin/$BRANCH"
        echo COMPASS_GIT_OUTCOME=reset
        exit 0
      fi
      git checkout "$BRANCH"
      if [ -n "$(git status --porcelain)" ]; then
        echo "guest worktree has uncommitted changes; commit or discard them before Compass can sync host history" >&2
        exit 3
      fi
      if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ]; then
        echo COMPASS_GIT_OUTCOME=current
      elif git merge-base --is-ancestor HEAD "origin/$BRANCH"; then
        git reset --hard "origin/$BRANCH"
        echo COMPASS_GIT_OUTCOME=reset
      elif git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
        echo COMPASS_GIT_OUTCOME=local-ahead
      else
        git rebase "origin/$BRANCH"
        echo COMPASS_GIT_OUTCOME=rebased
      fi
      """
    let result = try await client.run(
      command: command,
      workingDirectory: URL(fileURLWithPath: "/"),
      timeout: 180
    )
    guard result.exitCode == 0 else {
      throw SyncError.cloneOrUpdateFailed(
        exitCode: result.exitCode,
        stderr: result.stderr + result.stdout
      )
    }
    if result.stdout.contains("COMPASS_GIT_OUTCOME=cloned") {
      return .cloned
    }
    if result.stdout.contains("COMPASS_GIT_OUTCOME=current") {
      return .alreadyCurrent
    }
    if result.stdout.contains("COMPASS_GIT_OUTCOME=local-ahead") {
      return .preservedLocalCommits
    }
    if result.stdout.contains("COMPASS_GIT_OUTCOME=rebased") {
      return .rebasedLocalCommits
    }
    return .resetToHost
  }

  private static func validateGuestPath(_ path: String) throws {
    let standardized = (path as NSString).standardizingPath
    guard !standardized.contains("..") else {
      throw SyncError.invalidGuestPath(path)
    }
    let root = SharedCompassVMGuestWorkspaceCatalog.guestReposRoot
    let prefix = root.hasSuffix("/") ? root : root + "/"
    guard standardized.hasPrefix(prefix) else {
      throw SyncError.invalidGuestPath(path)
    }
  }
}
