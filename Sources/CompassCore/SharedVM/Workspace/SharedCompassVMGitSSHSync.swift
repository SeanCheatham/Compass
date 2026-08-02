import Foundation

/// Git-over-SSH sync between the host repo and the guest workspace.
///
/// Replaces the wipe-and-replace tar push (`SharedCompassVMWorktreeSync.push`)
/// as the primary host→guest transport:
///
///   * The host snapshots the worktree (including uncommitted changes, via a
///     temporary-index commit that respects `.gitignore`) and pushes it to a
///     bare *exchange* repository inside the guest over the SSH channel that
///     provisioning already established (`ssh://compass@<guest-ip>` with the
///     Compass-owned key). Deltas only — no full-tree re-upload per edit.
///   * The guest worktree then `git fetch`es the exchange repo locally and
///     `git reset --hard` to the synced ref. Untracked, gitignored build
///     state (`target/`, `.build/`) survives the reset, so incremental
///     compiles keep working across syncs.
///   * Guest-side edits (e.g. `cargo fmt`) travel back symmetrically: the
///     guest commits them onto `refs/compass/sync-back` and the host fetches
///     and merges that ref.
///
/// The tar path stays as the fallback transport for guests whose git
/// toolchain is broken (see `AgentMacOSVMBashRunner`).
public enum SharedCompassVMGitSSHSync {
  public static let syncRef = "refs/compass/sync"
  public static let syncBackRef = "refs/compass/sync-back"
  public static let exchangeDirectoryName = "exchange.git"

  enum SyncError: LocalizedError, CustomStringConvertible {
    case hostGitFailure(step: String, stderr: String)
    case guestGitFailure(step: String, stderr: String)
    case mergeConflict(detail: String)

    var description: String {
      switch self {
      case .hostGitFailure(let step, let stderr):
        return "host git \(step) failed: \(stderr)"
      case .guestGitFailure(let step, let stderr):
        return "guest git \(step) failed: \(stderr)"
      case .mergeConflict(let detail):
        return "guest sync-back merge conflict: \(detail)"
      }
    }

    var errorDescription: String? { description }
  }

  public struct GuestPaths: Equatable {
    public var workspaceRoot: String
    public var exchangePath: String
    public var worktreePath: String
  }

  public static func guestPaths(
    workspaceID: String,
    layout: SharedCompassVMGuestLayout = .current
  ) -> GuestPaths {
    let root = "\(layout.reposRoot)/\(workspaceID)"
    return GuestPaths(
      workspaceRoot: root,
      exchangePath: "\(root)/\(exchangeDirectoryName)",
      worktreePath: layout.worktreePath(
        workspaceID: workspaceID,
        subdirectory: SharedCompassVMGuestWorkspaceCatalog.guestWorktreeSubdirectory
      )
    )
  }

  /// `ssh://user@host/<exchange path>` remote URL for host-side git.
  public static func exchangeSSHURL(sshDestination: String, exchangePath: String) -> String {
    "ssh://\(sshDestination)\(exchangePath)"
  }

  /// Value for `GIT_SSH_COMMAND`: the same ssh invocation the bridge uses,
  /// minus destination and remote command, shell-quoted so paths with
  /// spaces (`Application Support`) survive git's shell parsing.
  public static func gitSSHCommand(
    options: SharedCompassVMGuestBridge.ConnectionOptions
  ) -> String {
    var tokens: [String] = [options.executablePath]
    if let identity = options.identityFile, !identity.isEmpty {
      tokens.append(contentsOf: ["-i", identity])
    }
    if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
      tokens.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHosts)"])
    }
    tokens.append(contentsOf: [
      "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")"
    ])
    if options.batchMode {
      tokens.append(contentsOf: ["-o", "BatchMode=yes"])
    }
    if let timeout = options.connectTimeoutSeconds {
      tokens.append(contentsOf: ["-o", "ConnectTimeout=\(timeout)"])
    }
    return tokens.map(SharedCompassVMGuestBridge.posixQuote).joined(separator: " ")
  }

  // MARK: - Guest scripts

  /// Creates the exchange repo + worktree git repo if absent and points the
  /// worktree's `exchange` remote at the bare repo. Idempotent.
  public static func guestBootstrapScript(paths: GuestPaths) -> String {
    let root = SharedCompassVMGuestBridge.posixQuote(paths.workspaceRoot)
    let exchange = SharedCompassVMGuestBridge.posixQuote(paths.exchangePath)
    let worktree = SharedCompassVMGuestBridge.posixQuote(paths.worktreePath)
    return """
      set -e
      mkdir -p \(root)
      if ! git --git-dir=\(exchange) rev-parse --is-bare-repository >/dev/null 2>&1; then
        git init --bare \(exchange)
      fi
      mkdir -p \(worktree)
      if ! git -C \(worktree) rev-parse --git-dir >/dev/null 2>&1; then
        git -C \(worktree) init
      fi
      git -C \(worktree) remote remove exchange >/dev/null 2>&1 || true
      git -C \(worktree) remote add exchange \(exchange)
      """
  }

  /// Fetches the pushed sync ref from the exchange repo and hard-resets the
  /// worktree to it. `reset --hard` leaves untracked gitignored paths
  /// (`target/`, `.build/`) in place, preserving incremental build state.
  public static func guestResetScript(paths: GuestPaths) -> String {
    let worktree = SharedCompassVMGuestBridge.posixQuote(paths.worktreePath)
    return """
      set -e
      git -C \(worktree) fetch exchange \(syncRef)
      git -C \(worktree) reset --hard FETCH_HEAD
      """
  }

  /// Commits any guest-side worktree changes and pushes them to the
  /// exchange repo's sync-back ref for the host to fetch. No-op when the
  /// worktree is clean.
  public static func guestSyncBackScript(paths: GuestPaths) -> String {
    let worktree = SharedCompassVMGuestBridge.posixQuote(paths.worktreePath)
    return """
      set -e
      cd \(worktree)
      if ! git diff --quiet || ! git diff --cached --quiet \\
        || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        git add -A
        git -c user.name=Compass -c user.email=compass@localhost \\
          commit -m "compass guest sync-back"
        git push exchange HEAD:\(syncBackRef)
      fi
      """
  }

  // MARK: - Orchestration

  /// Pushes the host repo state into the guest and returns the guest
  /// worktree path the caller should use as the working directory.
  public static func syncToGuest(
    hostRepoURL: URL,
    client: AgentVsockClient,
    sshDestination: String,
    sshOptions: SharedCompassVMGuestBridge.ConnectionOptions
  ) async throws -> String {
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: hostRepoURL)
    let paths = guestPaths(workspaceID: entry.id)

    try await runGuest(
      guestBootstrapScript(paths: paths), client: client, step: "bootstrap")

    let sha = try await createSyncCommit(hostRepoURL: hostRepoURL)
    let sshURL = exchangeSSHURL(sshDestination: sshDestination, exchangePath: paths.exchangePath)
    let sshCommand = gitSSHCommand(options: sshOptions)
    try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["push", "--force", sshURL, "\(sha):\(syncRef)"],
      sshCommand: sshCommand,
      step: "push"
    )

    try await runGuest(guestResetScript(paths: paths), client: client, step: "reset")

    // Keep the catalog fingerprint coherent with the tar fallback so the
    // two transports share the same drift-detection state.
    if let snapshot = try? SharedCompassVMHostFingerprint.compute(at: hostRepoURL) {
      try? SharedCompassVMGuestWorkspaceCatalog.recordSync(
        forRepoURL: hostRepoURL,
        fingerprint: snapshot.fingerprint,
        fileSet: snapshot.fileSet
      )
    }
    return paths.worktreePath
  }

  /// Pulls guest-side worktree changes back into the host repo. No-op when
  /// the guest worktree is clean. Throws on merge conflicts — the guest
  /// commit stays on `refs/compass/sync-back` for manual recovery.
  public static func pullFromGuest(
    hostRepoURL: URL,
    client: AgentVsockClient,
    sshDestination: String,
    sshOptions: SharedCompassVMGuestBridge.ConnectionOptions
  ) async throws {
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: hostRepoURL)
    let paths = guestPaths(workspaceID: entry.id)

    try await runGuest(guestSyncBackScript(paths: paths), client: client, step: "sync-back")

    let sshURL = exchangeSSHURL(sshDestination: sshDestination, exchangePath: paths.exchangePath)
    let sshCommand = gitSSHCommand(options: sshOptions)
    let fetch = try await hostGitAllowingFailure(
      hostRepoURL: hostRepoURL,
      arguments: ["fetch", sshURL, syncBackRef],
      sshCommand: sshCommand
    )
    guard fetch.exitCode == 0 else {
      // No sync-back ref (clean guest) — nothing to pull.
      return
    }

    let ffMerge = try await hostGitAllowingFailure(
      hostRepoURL: hostRepoURL,
      arguments: ["merge", "--ff-only", "FETCH_HEAD"],
      sshCommand: nil
    )
    if ffMerge.exitCode != 0 {
      let merge = try await hostGitAllowingFailure(
        hostRepoURL: hostRepoURL,
        arguments: ["merge", "--no-edit", "FETCH_HEAD"],
        sshCommand: nil
      )
      if merge.exitCode != 0 {
        _ = try? await hostGitAllowingFailure(
          hostRepoURL: hostRepoURL,
          arguments: ["merge", "--abort"],
          sshCommand: nil
        )
        throw SyncError.mergeConflict(detail: merge.stderr)
      }
    }

    // Consume the ref so the next pull starts from a clean slate.
    _ = try? await hostGitAllowingFailure(
      hostRepoURL: hostRepoURL,
      arguments: ["push", sshURL, "--delete", syncBackRef],
      sshCommand: sshCommand
    )

    if let snapshot = try? SharedCompassVMHostFingerprint.compute(at: hostRepoURL) {
      try? SharedCompassVMGuestWorkspaceCatalog.recordSync(
        forRepoURL: hostRepoURL,
        fingerprint: snapshot.fingerprint,
        fileSet: snapshot.fileSet
      )
    }
  }

  // MARK: - Host git helpers

  /// Snapshots the worktree as a commit object without touching the user's
  /// index or working tree. Clean trees short-circuit to HEAD; dirty trees
  /// are captured via a temporary index (`read-tree HEAD` + `add -A`, which
  /// respects `.gitignore`) committed on top of HEAD.
  public static func createSyncCommit(hostRepoURL: URL) async throws -> String {
    let status = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["status", "--porcelain"],
      sshCommand: nil,
      step: "status"
    )
    if status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let revParse = try await hostGit(
        hostRepoURL: hostRepoURL,
        arguments: ["rev-parse", "HEAD"],
        sshCommand: nil,
        step: "rev-parse"
      )
      return revParse.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let head = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["rev-parse", "HEAD"],
      sshCommand: nil,
      step: "rev-parse"
    ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

    let indexPath = "/tmp/compass-sync-index-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: indexPath) }
    let indexEnv = "GIT_INDEX_FILE=\(indexPath)"

    _ = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["read-tree", "HEAD"],
      envPrefix: [indexEnv],
      sshCommand: nil,
      step: "read-tree"
    )
    _ = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["add", "-A"],
      envPrefix: [indexEnv],
      sshCommand: nil,
      step: "add"
    )
    let tree = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: ["write-tree"],
      envPrefix: [indexEnv],
      sshCommand: nil,
      step: "write-tree"
    ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = try await hostGit(
      hostRepoURL: hostRepoURL,
      arguments: [
        "commit-tree", tree, "-p", head,
        "-m", "compass host sync \(ISO8601DateFormatter().string(from: Date()))",
      ],
      sshCommand: nil,
      step: "commit-tree"
    )
    return commit.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Process plumbing

  @discardableResult
  private static func hostGit(
    hostRepoURL: URL,
    arguments: [String],
    envPrefix: [String] = [],
    sshCommand: String?,
    step: String
  ) async throws -> ProcessResult {
    let result = try await hostGitAllowingFailure(
      hostRepoURL: hostRepoURL,
      arguments: arguments,
      envPrefix: envPrefix,
      sshCommand: sshCommand
    )
    guard result.exitCode == 0 else {
      throw SyncError.hostGitFailure(step: step, stderr: result.stderr)
    }
    return result
  }

  private static func hostGitAllowingFailure(
    hostRepoURL: URL,
    arguments: [String],
    envPrefix: [String] = [],
    sshCommand: String?
  ) async throws -> ProcessResult {
    var prefix = envPrefix
    if let sshCommand {
      prefix.append("GIT_SSH_COMMAND=\(sshCommand)")
    }
    return try await ProcessRunner.run(
      executable: "/usr/bin/env",
      arguments: prefix + ["git"] + arguments,
      workingDirectory: hostRepoURL,
      timeout: 300
    )
  }

  private static func runGuest(
    _ script: String,
    client: AgentVsockClient,
    step: String
  ) async throws {
    let result = try await client.run(
      command: script,
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 180
    )
    guard result.exitCode == 0 else {
      throw SyncError.guestGitFailure(step: step, stderr: result.stderr)
    }
  }
}
