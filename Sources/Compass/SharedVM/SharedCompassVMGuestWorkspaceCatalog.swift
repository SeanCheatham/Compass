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
///   * The sync cost is paid once per repo lifetime, not per iteration.
///     After the first push the host only re-syncs when it detects
///     drift; the guest copy is the source of truth between sessions.
///   * The guest never sees the host's actual repo path
///     (`/Users/<user>/git/<repo>`). Its working directory is always a
///     `/Users/compass/Compass/Repos/<UUID>/worktree` path it owns.
///
/// The ID lives in `<repo>/.compass/guest-workspace.json`. `.compass/`
/// is already gitignored (see `CompassWorkspace.ensureCompassIsIgnored`),
/// so the ID does not leak into the user's commit history.
enum SharedCompassVMGuestWorkspaceCatalog {

    /// Guest-side root that holds every per-repo workspace.
    static let guestReposRoot = "/Users/compass/Compass/Repos"

    /// Subdirectory inside each per-repo workspace that actually carries
    /// the synced worktree contents. Keeping a layer of nesting (rather
    /// than putting files directly under `<UUID>/`) leaves room for
    /// adjacent guest-side bookkeeping later (e.g. `<UUID>/.compass-sync`)
    /// without touching the worktree namespace.
    static let guestWorktreeSubdirectory = "worktree"

    /// Filename inside `<repo>/.compass/` that stores the ID.
    static let catalogFilename = "guest-workspace.json"

    // MARK: - Catalog entry

    /// On-disk record. Only one field today; the wrapper struct exists so
    /// future additions (e.g. `lastSyncedGitSha`) don't break older
    /// catalog files via Codable's default decoding.
    struct CatalogEntry: Codable, Equatable {
        /// Stable UUID for this host repo's guest workspace. Generated
        /// the first time Compass needs a guest workspace and never
        /// rotated unless the caller explicitly resets the entry.
        var id: String

        init(id: String) { self.id = id }
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
        let entry = CatalogEntry(id: UUID().uuidString.lowercased())
        try save(entry, to: url, fileManager: fileManager)
        // Re-read so we observe whatever a concurrent writer produced in
        // between our load and save. The first writer always wins.
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

    /// Wipes the entry. Caller is responsible for any guest-side cleanup
    /// (the helper does not connect to the VM).
    static func removeEntry(
        forRepoURL repoURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = catalogURL(forRepoURL: repoURL)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Absolute guest path of the worktree directory for `entry`. This is
    /// the path Compass hands to the agent as its working directory under
    /// the `.sharedVM` route.
    static func guestWorktreePath(forEntry entry: CatalogEntry) -> String {
        "\(guestReposRoot)/\(entry.id)/\(guestWorktreeSubdirectory)"
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

    // MARK: - Path helpers

    static func catalogURL(forRepoURL repoURL: URL) -> URL {
        CompassWorkspace.repoLocalStorageRootURL(for: repoURL)
            .appending(path: catalogFilename)
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
