import Foundation

/// Per-repo bookkeeping that maps a host repo to a stable guest workspace
/// directory inside the Shared VM.
///
/// Compass keeps a single persistent guest-side worktree per host repo
/// (rather than one per Develop iteration) so:
///
///   * Plan / Reflect / Develop / Verify all share the same guest
///     working directory — no phase ever falls back to host execution
///     just because it lives outside a `Worktrees/dev-<UUID>/worktree`
///     subtree.
///   * Git-backed workspaces can be fetched/rebased in place instead of
///     repopulated from scratch. The host branch still re-anchors each
///     run, but local guest commits survive until Compass promotes them
///     through the exchange repo.
///   * The guest never sees the host's actual repo path
///     (`/Users/<user>/git/<repo>`). Its working directory is always a
///     Shared VM guest-local `Compass/Repos/<UUID>/worktree` path it owns.
///
/// The ID lives in `<repo>/.compass/guest-workspace.json`. `.compass/`
/// is already gitignored (see `CompassWorkspace.ensureCompassIsIgnored`),
/// so the ID does not leak into the user's commit history.
enum SharedCompassVMGuestWorkspaceCatalog {
  /// Guest layout used to allocate per-repo workspaces. Currently this is the
  /// macOS Shared VM layout; keeping it centralized makes the future Linux guest
  /// root a single contract swap instead of a repo-wide string rewrite.
  static let guestLayout = SharedCompassVMGuestLayout.current

  /// Guest-side root that holds every per-repo workspace.
  static let guestReposRoot = guestLayout.reposRoot

  /// Subdirectory inside each per-repo workspace that actually carries
  /// the synced worktree contents. Keeping a layer of nesting (rather
  /// than putting files directly under `<UUID>/`) leaves room for
  /// adjacent guest-side bookkeeping later (e.g. `<UUID>/.compass-sync`)
  /// without touching the worktree namespace.
  static let guestWorktreeSubdirectory = "worktree"

  /// Filename inside `<repo>/.compass/` that stores the ID.
  static let catalogFilename = "guest-workspace.json"

  /// Sidecar filename inside `<repo>/.compass/` that stores the NUL-
  /// separated set of host file paths captured at the last successful
  /// sync. Kept out of the JSON catalog to avoid blowing the per-call
  /// decode cost on large repos.
  static let filesetFilename = "guest-workspace-fileset.dat"
  static let experimentCatalogDirectory = "product-tournament/guest-workspaces"

  // MARK: - Catalog entry

  /// On-disk record. The wrapper struct exists so future additions
  /// don't break older catalog files via Codable's default decoding —
  /// every non-`id` field is optional and absence-tolerant.
  struct CatalogEntry: Codable, Equatable {
    /// Stable UUID for this host repo's guest workspace. Generated
    /// the first time Compass needs a guest workspace and never
    /// rotated unless the caller explicitly resets the entry.
    var id: String
    var experimentID: String?
    var branchName: String?
    /// Lowercase-hex SHA-256 of the host worktree's content as of the
    /// last successful push or pull. Used by `SharedCompassVMRepoWorkspaceSync`
    /// to detect out-of-band host edits made while Compass wasn't
    /// running; on mismatch the fast-path is refused and the guest is
    /// re-populated from the host so the user's changes participate
    /// in the next session. Optional so catalogs written before this
    /// field existed still decode.
    var lastSyncedHostFingerprint: String?

    init(
      id: String,
      experimentID: String? = nil,
      branchName: String? = nil,
      lastSyncedHostFingerprint: String? = nil
    ) {
      self.id = id
      self.experimentID = experimentID
      self.branchName = branchName
      self.lastSyncedHostFingerprint = lastSyncedHostFingerprint
    }
  }

  // MARK: - Public API

  /// Returns the existing entry for `repoURL`, or creates and persists
  /// a fresh one. Idempotent — concurrent callers on the same repo end
  /// up with the same ID (the first writer wins; subsequent callers
  /// re-read the file).
  static func ensureEntry(
    forRepoURL repoURL: URL,
    fileManager: FileManager = .default
  ) throws -> CatalogEntry {
    let url = catalogURL(forRepoURL: repoURL)
    if let existing = try loadEntry(from: url, fileManager: fileManager) {
      return existing
    }
    let entry = CatalogEntry(
      id: UUID().uuidString.lowercased(),
      lastSyncedHostFingerprint: nil
    )
    try save(entry, to: url, fileManager: fileManager)
    // Re-read so we observe whatever a concurrent writer produced in
    // between our load and save. The first writer always wins.
    if let observed = try loadEntry(from: url, fileManager: fileManager) {
      return observed
    }
    return entry
  }

  static func ensureEntry(
    forRepoURL repoURL: URL,
    experimentID: String,
    branchName: String,
    fileManager: FileManager = .default
  ) throws -> CatalogEntry {
    let url = experimentCatalogURL(
      forRepoURL: repoURL,
      experimentID: experimentID,
      branchName: branchName
    )
    if let existing = try loadEntry(from: url, fileManager: fileManager) {
      return existing
    }
    let entry = CatalogEntry(
      id: UUID().uuidString.lowercased(),
      experimentID: ProductizationModelText.identifier(experimentID, fallback: "experiment"),
      branchName: StringUtils.boundedText(branchName, limit: 240),
      lastSyncedHostFingerprint: nil
    )
    try save(entry, to: url, fileManager: fileManager)
    if let observed = try loadEntry(from: url, fileManager: fileManager) {
      return observed
    }
    return entry
  }

  /// Returns the catalog entry for `repoURL` if one has been allocated,
  /// or nil. Useful for diagnostics paths that should not implicitly
  /// allocate.
  static func loadEntry(
    forRepoURL repoURL: URL,
    fileManager: FileManager = .default
  ) throws -> CatalogEntry? {
    try loadEntry(
      from: catalogURL(forRepoURL: repoURL),
      fileManager: fileManager
    )
  }

  static func loadEntry(
    forRepoURL repoURL: URL,
    experimentID: String,
    branchName: String,
    fileManager: FileManager = .default
  ) throws -> CatalogEntry? {
    try loadEntry(
      from: experimentCatalogURL(
        forRepoURL: repoURL,
        experimentID: experimentID,
        branchName: branchName
      ),
      fileManager: fileManager
    )
  }

  /// Wipes the entry and any sidecar files (fileset list). Caller is
  /// responsible for any guest-side cleanup (the helper does not
  /// connect to the VM).
  static func removeEntry(
    forRepoURL repoURL: URL,
    fileManager: FileManager = .default
  ) throws {
    let url = catalogURL(forRepoURL: repoURL)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    let filesetURL = filesetURL(forRepoURL: repoURL)
    if fileManager.fileExists(atPath: filesetURL.path) {
      try fileManager.removeItem(at: filesetURL)
    }
  }

  /// Records a successful host↔guest sync by stamping the entry with
  /// `fingerprint` and writing `fileSet` to the sidecar list. Allocates
  /// the entry if it didn't already exist so callers don't have to
  /// pre-create it.
  ///
  /// The fingerprint and the fileset are written as a pair on every
  /// successful push or pull; `SharedCompassVMRepoWorkspaceSync` uses
  /// the fingerprint to decide whether the host has drifted since the
  /// last sync, and the pull path uses the fileset to scope deletions
  /// to "files that were on the host at last push" so user-added files
  /// between sessions are not clobbered.
  static func recordSync(
    forRepoURL repoURL: URL,
    fingerprint: String,
    fileSet: Set<String>,
    fileManager: FileManager = .default
  ) throws {
    let url = catalogURL(forRepoURL: repoURL)
    var entry =
      try loadEntry(from: url, fileManager: fileManager)
      ?? CatalogEntry(id: UUID().uuidString.lowercased(), lastSyncedHostFingerprint: nil)
    entry.lastSyncedHostFingerprint = fingerprint
    try save(entry, to: url, fileManager: fileManager)
    try writeFileSet(fileSet, to: filesetURL(forRepoURL: repoURL), fileManager: fileManager)
  }

  /// Returns the file set written at the last `recordSync`, or nil if
  /// no sync has been recorded yet. Used by the pull path to determine
  /// which host files are eligible for "agent deleted this" cleanup.
  static func loadLastSyncedFileSet(
    forRepoURL repoURL: URL,
    fileManager: FileManager = .default
  ) throws -> Set<String>? {
    let url = filesetURL(forRepoURL: repoURL)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let text = String(decoding: data, as: UTF8.self)
    let parts = text.split(separator: "\0", omittingEmptySubsequences: true)
    return Set(parts.map(String.init))
  }

  /// Absolute guest path of the worktree directory for `entry`. This is
  /// the path Compass hands to the agent as its working directory under
  /// the `.sharedVM` route.
  static func guestWorktreePath(forEntry entry: CatalogEntry) -> String {
    guestLayout.worktreePath(
      workspaceID: entry.id,
      subdirectory: guestWorktreeSubdirectory
    )
  }

  /// Convenience: ensure-or-create the entry and return the guest path
  /// in one call. The common shape for callers that just want
  /// `"give me the guest working directory for this repo"`.
  static func ensureGuestWorktreePath(
    forRepoURL repoURL: URL,
    fileManager: FileManager = .default
  ) throws -> String {
    let entry = try ensureEntry(forRepoURL: repoURL, fileManager: fileManager)
    return guestWorktreePath(forEntry: entry)
  }

  static func ensureGuestWorktreePath(
    forRepoURL repoURL: URL,
    experimentID: String,
    branchName: String,
    fileManager: FileManager = .default
  ) throws -> String {
    let entry = try ensureEntry(
      forRepoURL: repoURL,
      experimentID: experimentID,
      branchName: branchName,
      fileManager: fileManager
    )
    return guestWorktreePath(forEntry: entry)
  }

  // MARK: - Path helpers

  static func catalogURL(forRepoURL repoURL: URL) -> URL {
    CompassWorkspace.repoLocalStorageRootURL(for: repoURL)
      .appending(path: catalogFilename)
  }

  static func filesetURL(forRepoURL repoURL: URL) -> URL {
    CompassWorkspace.repoLocalStorageRootURL(for: repoURL)
      .appending(path: filesetFilename)
  }

  static func experimentCatalogURL(
    forRepoURL repoURL: URL,
    experimentID: String,
    branchName: String
  ) -> URL {
    CompassWorkspace.repoLocalStorageRootURL(for: repoURL)
      .appending(path: experimentCatalogDirectory, directoryHint: .isDirectory)
      .appending(path: "\(experimentCatalogComponent(experimentID))-\(experimentCatalogComponent(branchName)).json")
  }

  // MARK: - Internals

  private static func loadEntry(
    from url: URL,
    fileManager: FileManager
  ) throws -> CatalogEntry? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    do {
      let decoded = try JSONDecoder().decode(CatalogEntry.self, from: data)
      guard isValidID(decoded.id) else {
        // Refuse to hand back a corrupt ID — caller will fall
        // into ensureEntry's "create a new one" branch.
        return nil
      }
      return decoded
    } catch {
      // Corrupt file. Treat as absent rather than throwing so a
      // caller asking "ensure entry" recovers by writing a fresh
      // one instead of failing the whole agent run.
      return nil
    }
  }

  private static func save(
    _ entry: CatalogEntry,
    to url: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entry)
    try data.write(to: url, options: .atomic)
  }

  private static func experimentCatalogComponent(_ value: String) -> String {
    let normalized =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let bounded = String(normalized.prefix(80))
    return bounded.isEmpty ? "experiment" : bounded
  }

  private static func writeFileSet(
    _ files: Set<String>,
    to url: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // Sorted for deterministic on-disk bytes — keeps diffing the
    // sidecar tractable when debugging.
    let sorted = files.sorted()
    var buffer = Data()
    for path in sorted {
      buffer.append(Data(path.utf8))
      buffer.append(0)
    }
    try buffer.write(to: url, options: .atomic)
  }

  /// Lower-cased UUID strings only. Rejects whitespace, slashes, or
  /// anything else that could shell-inject into the guest path.
  private static func isValidID(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 64 else { return false }
    for scalar in id.unicodeScalars {
      switch scalar {
      case "a"..."z", "0"..."9", "-":
        continue
      default:
        return false
      }
    }
    return true
  }
}
