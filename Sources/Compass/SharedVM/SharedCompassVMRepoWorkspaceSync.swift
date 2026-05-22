import Foundation

/// Higher-level sync orchestrator for the per-repo persistent guest
/// workspace.
///
/// `SharedCompassVMWorktreeSync` provides the raw "stuff a tar from
/// `here` into `there`" plumbing; this helper layers session-level
/// policy on top:
///
///   * Resolves the guest path through `SharedCompassVMGuestWorkspaceCatalog`
///     so callers don't have to know about UUIDs.
///   * Skips the push when the guest workspace already exists — agent
///     state from previous sessions/iterations survives. The Compass
///     model treats the guest as the source of truth between sessions;
///     callers that need to force a refresh do so explicitly.
///   * Returns the resolved guest path so the agent runtime can plumb
///     it through as the working directory without re-deriving it.
///
/// Threading: pure async helpers. No actor isolation. Safe to call from
/// any context that already owns a vsock client.
enum SharedCompassVMRepoWorkspaceSync {

    enum SyncError: Error, CustomStringConvertible {
        case catalogFailure(detail: String)
        case probeFailure(stderr: String)
        case wrappedSyncFailure(SharedCompassVMWorktreeSync.SyncError)

        var description: String {
            switch self {
            case .catalogFailure(let detail):
                return "guest workspace catalog failure: \(detail)"
            case .probeFailure(let stderr):
                return "guest workspace probe failed: \(stderr)"
            case .wrappedSyncFailure(let inner):
                return "guest workspace sync failed: \(inner)"
            }
        }
    }

    /// Outcome of a sync attempt. Useful for diagnostic logging and for
    /// future Verify integration that wants to know whether the agent
    /// is operating on freshly-pushed contents or persisted ones.
    enum Outcome: Equatable {
        /// The guest workspace already existed; no push was performed.
        case reused
        /// The guest workspace was missing and was populated from the
        /// host repo for the first time (or after an explicit reset).
        case freshlyPopulated
        /// The caller forced a refresh; we re-pushed even though a
        /// guest workspace already existed.
        case refreshed
    }

    /// Ensures the persistent guest workspace for `hostRepoURL` exists
    /// and is populated, returning the guest path the caller should use
    /// as the agent's working directory.
    ///
    /// - Parameters:
    ///   - hostRepoURL: The host-side repo whose contents back the guest
    ///     workspace. Must be a real git working tree the first time
    ///     this is called (we use `git ls-files` to enumerate).
    ///   - client: Vsock client connected to the live guest agent.
    ///   - forceRefresh: When `true`, re-push from the host even if the
    ///     guest workspace already exists. Use for "the host repo
    ///     changed underneath me, please resync" flows.
    static func ensurePopulated(
        hostRepoURL: URL,
        client: AgentVsockClient,
        forceRefresh: Bool = false
    ) async throws -> (guestPath: String, outcome: Outcome) {
        let entry: SharedCompassVMGuestWorkspaceCatalog.CatalogEntry
        do {
            entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
                forRepoURL: hostRepoURL
            )
        } catch {
            throw SyncError.catalogFailure(detail: "\(error)")
        }
        let guestPath = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(
            forEntry: entry
        )

        if forceRefresh {
            try await push(
                hostRepoURL: hostRepoURL,
                guestPath: guestPath,
                client: client
            )
            return (guestPath, .refreshed)
        }

        let exists = try await guestPathExists(guestPath, client: client)
        if exists {
            return (guestPath, .reused)
        }

        try await push(
            hostRepoURL: hostRepoURL,
            guestPath: guestPath,
            client: client
        )
        return (guestPath, .freshlyPopulated)
    }

    // MARK: - Internals

    private static func push(
        hostRepoURL: URL,
        guestPath: String,
        client: AgentVsockClient
    ) async throws {
        do {
            try await SharedCompassVMWorktreeSync.push(
                hostWorktreeURL: hostRepoURL,
                guestWorktreePath: guestPath,
                client: client
            )
        } catch let error as SharedCompassVMWorktreeSync.SyncError {
            throw SyncError.wrappedSyncFailure(error)
        }
    }

    /// Returns true when the guest path exists as a directory. Used to
    /// short-circuit the push step on subsequent sessions so the agent's
    /// prior work is preserved.
    private static func guestPathExists(
        _ guestPath: String,
        client: AgentVsockClient
    ) async throws -> Bool {
        // Use a single bash RPC rather than the filesystem stat RPC so
        // we get a definite yes/no plus the exit code, without having to
        // distinguish "missing" from "permission denied" in two places.
        let result: ProcessResult
        do {
            result = try await client.run(
                command: "if [ -d '\(guestPath)' ]; then echo PRESENT; else echo ABSENT; fi",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                timeout: 15
            )
        } catch {
            throw SyncError.probeFailure(stderr: "\(error)")
        }
        if result.exitCode != 0 {
            throw SyncError.probeFailure(stderr: result.stderr)
        }
        return result.stdout.contains("PRESENT")
    }
}
