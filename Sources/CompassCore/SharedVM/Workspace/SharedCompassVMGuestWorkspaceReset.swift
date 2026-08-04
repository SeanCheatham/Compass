import Foundation

/// Discards per-repo guest workspace dirt without reprovisioning the shared VM.
///
/// Plan/Develop/Verify keep one worktree for a live session; this API makes that
/// worktree discardable between sessions or on demand. Toolchains stay installed.
public enum SharedCompassVMGuestWorkspaceReset {
  public enum Mode: String, Sendable, Equatable {
    /// Remove build/mutant/dist trees inside the existing guest worktree.
    /// Catalog ID is unchanged.
    case dirt
    /// Delete the guest `Repos/<id>` tree, rotate the host catalog entry, and
    /// optionally force-sync a fresh worktree.
    case full
  }

  public struct Outcome: Sendable, Equatable {
    public var mode: Mode
    public var previousWorkspaceID: String?
    public var workspaceID: String?
    public var guestWorktreePath: String?
    public var detail: String

    public init(
      mode: Mode,
      previousWorkspaceID: String? = nil,
      workspaceID: String? = nil,
      guestWorktreePath: String? = nil,
      detail: String
    ) {
      self.mode = mode
      self.previousWorkspaceID = previousWorkspaceID
      self.workspaceID = workspaceID
      self.guestWorktreePath = guestWorktreePath
      self.detail = detail
    }
  }

  public enum ResetError: LocalizedError {
    case invalidWorkspaceID(String)
    case guestCommandFailed(exitCode: Int32, detail: String)

    public var errorDescription: String? {
      switch self {
      case .invalidWorkspaceID(let id):
        return "Refusing to reset guest workspace with invalid id \(id)."
      case .guestCommandFailed(let exitCode, let detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          return "Guest workspace reset command exited \(exitCode)."
        }
        return "Guest workspace reset command exited \(exitCode): \(trimmed)"
      }
    }
  }

  /// Resets the guest workspace for `repoURL`.
  ///
  /// - Parameters:
  ///   - mode: `.dirt` or `.full`.
  ///   - resyncAfterFull: When `mode == .full`, force-sync the host repo into a
  ///     freshly allocated guest worktree (default `true`).
  @discardableResult
  public static func reset(
    repoURL: URL,
    mode: Mode,
    resyncAfterFull: Bool = true,
    fileManager: FileManager = .default
  ) async throws -> Outcome {
    let repo = repoURL.standardizedFileURL
    switch mode {
    case .dirt:
      return try await resetDirt(repoURL: repo, fileManager: fileManager)
    case .full:
      return try await resetFull(
        repoURL: repo,
        resync: resyncAfterFull,
        fileManager: fileManager
      )
    }
  }

  // MARK: - Dirt

  private static func resetDirt(
    repoURL: URL,
    fileManager: FileManager
  ) async throws -> Outcome {
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
      forRepoURL: repoURL,
      fileManager: fileManager
    )
    let worktree = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    try validateWorkspaceID(entry.id)
    let quotedWorktree = SharedCompassVMGuestBridge.posixQuote(worktree)
    let command = """
      set -euo pipefail
      WT=\(quotedWorktree)
      if [ ! -d "$WT" ]; then
        echo "guest worktree absent; nothing to clean"
        exit 0
      fi
      cd "$WT"
      rm -rf \
        target \
        .build \
        apps/macos/.build \
        apps/macos/dist \
        mutants.out \
        mutants.out.old \
        coverage \
        lcov.info \
        default.profraw \
        default.profdata \
        2>/dev/null || true
      # cargo-mutants / llvm-cov leave variously named trees; sweep common globs.
      rm -rf mutants.out* *.profraw *.profdata 2>/dev/null || true
      echo "dirt cleaned under $WT"
      """
    try await runGuestCommand(
      command,
      workingDirectory: SharedCompassVMGuestLayout.current.homeDirectory,
      timeout: 120
    )
    return Outcome(
      mode: .dirt,
      previousWorkspaceID: entry.id,
      workspaceID: entry.id,
      guestWorktreePath: worktree,
      detail: "Removed build/mutant/dist artifacts under \(worktree)."
    )
  }

  // MARK: - Full

  private static func resetFull(
    repoURL: URL,
    resync: Bool,
    fileManager: FileManager
  ) async throws -> Outcome {
    let previous = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(
      forRepoURL: repoURL,
      fileManager: fileManager
    )
    if let previous {
      try validateWorkspaceID(previous.id)
      let root = SharedCompassVMGuestWorkspaceCatalog.guestWorkspaceRootPath(forEntry: previous)
      let quotedRoot = SharedCompassVMGuestBridge.posixQuote(root)
      let command = """
        set -euo pipefail
        ROOT=\(quotedRoot)
        if [ -e "$ROOT" ]; then
          rm -rf "$ROOT"
          echo "removed $ROOT"
        else
          echo "guest workspace root absent; catalog only"
        fi
        """
      try await runGuestCommand(
        command,
        workingDirectory: SharedCompassVMGuestLayout.current.homeDirectory,
        timeout: 180
      )
    }

    try SharedCompassVMGuestWorkspaceCatalog.removeEntry(
      forRepoURL: repoURL,
      fileManager: fileManager
    )

    guard resync else {
      return Outcome(
        mode: .full,
        previousWorkspaceID: previous?.id,
        workspaceID: nil,
        guestWorktreePath: nil,
        detail: "Removed guest workspace\(previous.map { " \($0.id)" } ?? "") and host catalog entry."
      )
    }

    let ready = try await AgentMacOSVMBashRunner.ensureReady()
    let guestPath: String
    do {
      guestPath = try await SharedCompassVMGitSSHSync.syncToGuest(
        hostRepoURL: repoURL,
        client: ready.client,
        sshDestination: ready.sshDestination,
        sshOptions: ready.sshOptions
      )
    } catch {
      let sync = try await SharedCompassVMRepoWorkspaceSync.ensurePopulated(
        hostRepoURL: repoURL,
        client: ready.client,
        forceRefresh: true
      )
      guestPath = sync.guestPath
    }
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
      forRepoURL: repoURL,
      fileManager: fileManager
    )
    return Outcome(
      mode: .full,
      previousWorkspaceID: previous?.id,
      workspaceID: entry.id,
      guestWorktreePath: guestPath,
      detail: "Rotated guest workspace to \(entry.id) and force-synced \(guestPath)."
    )
  }

  // MARK: - Helpers

  static func validateWorkspaceID(_ id: String) throws {
    // Mirror catalog validation so we never interpolate an unsafe path.
    guard !id.isEmpty, id.count <= 64 else {
      throw ResetError.invalidWorkspaceID(id)
    }
    for scalar in id.unicodeScalars {
      switch scalar {
      case "a"..."z", "0"..."9", "-":
        continue
      default:
        throw ResetError.invalidWorkspaceID(id)
      }
    }
  }

  private static func runGuestCommand(
    _ command: String,
    workingDirectory: String,
    timeout: TimeInterval
  ) async throws {
    let ready = try await AgentMacOSVMBashRunner.ensureReady()
    let result = try await ready.client.run(
      command: command,
      workingDirectory: URL(fileURLWithPath: workingDirectory),
      timeout: timeout
    )
    guard result.exitCode == 0 else {
      throw ResetError.guestCommandFailed(
        exitCode: result.exitCode,
        detail: result.stderr + "\n" + result.stdout
      )
    }
  }
}

extension SharedCompassVMGuestWorkspaceCatalog {
  /// Absolute guest path of the per-repo workspace root (`Repos/<id>`),
  /// parent of the `worktree` subdirectory.
  static func guestWorkspaceRootPath(forEntry entry: CatalogEntry) -> String {
    "\(guestReposRoot)/\(entry.id)"
  }
}
