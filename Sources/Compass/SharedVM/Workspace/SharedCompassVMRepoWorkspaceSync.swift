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

  enum SyncError: LocalizedError, CustomStringConvertible {
    case catalogFailure(detail: String)
    case probeFailure(stderr: String)
    case wrappedSyncFailure(SharedCompassVMWorktreeSync.SyncError)
    case fingerprintFailure(detail: String)

    var description: String {
      switch self {
      case .catalogFailure(let detail):
        return "guest workspace catalog failure: \(detail)"
      case .probeFailure(let stderr):
        return "guest workspace probe failed: \(stderr)"
      case .wrappedSyncFailure(let inner):
        return "guest workspace sync failed: \(inner)"
      case .fingerprintFailure(let detail):
        return "host fingerprint failure: \(detail)"
      }
    }

    // LocalizedError — without this Foundation collapses the message
    // to "The operation couldn't be completed. (Compass.…SyncError
    // error 2.)" in any UI alert that goes through
    // `localizedDescription`, hiding the actual underlying cause.
    var errorDescription: String? { description }
  }

  /// Outcome of a sync attempt. Useful for diagnostic logging and for
  /// future Verify integration that wants to know whether the agent
  /// is operating on freshly-pushed contents or persisted ones.
  enum Outcome: Equatable {
    /// The guest workspace already existed and the host fingerprint
    /// matched the last recorded sync; no push was performed.
    case reused
    /// The guest workspace was missing and was populated from the
    /// host repo for the first time (or after an explicit reset).
    case freshlyPopulated
    /// The caller forced a refresh; we re-pushed even though a
    /// guest workspace already existed.
    case refreshed
    /// The guest workspace existed but the host fingerprint diverged
    /// from the last recorded sync — typically because the user
    /// edited the repo while Compass wasn't running. We re-pushed so
    /// those edits show up in the session, the way they would have
    /// if the guest hadn't existed yet.
    case refreshedDueToHostDrift
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

    // Compute the host fingerprint once up front. We always need it
    // — either to drive the drift-vs-fast-path decision below, or to
    // stamp the catalog after a push so the next session can see
    // whether anything has changed.
    let snapshot: (fingerprint: String, fileSet: Set<String>)
    do {
      snapshot = try SharedCompassVMHostFingerprint.compute(at: hostRepoURL)
    } catch {
      throw SyncError.fingerprintFailure(detail: "\(error)")
    }

    if forceRefresh {
      try await pushAndRecord(
        hostRepoURL: hostRepoURL,
        guestPath: guestPath,
        client: client,
        snapshot: snapshot
      )
      return (guestPath, .refreshed)
    }

    let exists = try await guestPathExists(guestPath, client: client)
    if exists {
      if let recorded = entry.lastSyncedHostFingerprint,
        recorded == snapshot.fingerprint
      {
        return (guestPath, .reused)
      }
      // Either the host has drifted since the last sync, or there is
      // no recorded fingerprint yet (catalog written by an older
      // build). Re-push so the user's edits land in the guest before
      // the agent starts reading.
      try await pushAndRecord(
        hostRepoURL: hostRepoURL,
        guestPath: guestPath,
        client: client,
        snapshot: snapshot
      )
      return (guestPath, .refreshedDueToHostDrift)
    }

    try await pushAndRecord(
      hostRepoURL: hostRepoURL,
      guestPath: guestPath,
      client: client,
      snapshot: snapshot
    )
    return (guestPath, .freshlyPopulated)
  }

  /// Pulls the guest worktree back onto the host repo and updates the
  /// catalog with the post-pull fingerprint so the next session sees
  /// host == guest and takes the fast path.
  ///
  /// Scopes the pull's "agent deleted this file" cleanup to the
  /// fileset captured at the last push: files the user added on the
  /// host between sessions are *not* in that set, so the cleanup
  /// step skips them even if they're missing from the guest. (The
  /// regular drift-check path will have re-pushed before the agent
  /// ever ran, so by the time we get here the user's additions are
  /// in the guest too — this is belt and braces.)
  static func pullAndRecord(
    hostRepoURL: URL,
    client: AgentVsockClient
  ) async throws {
    let entry: SharedCompassVMGuestWorkspaceCatalog.CatalogEntry?
    do {
      entry = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: hostRepoURL)
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
    }
    guard let entry else {
      // Nothing to pull into — caller should have called
      // ensurePopulated first. Surface as a catalog failure rather
      // than silently no-op'ing so a regression here gets caught.
      throw SyncError.catalogFailure(detail: "no catalog entry for host repo \(hostRepoURL.path)")
    }
    let guestPath = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
    let deletionScope: Set<String>?
    do {
      deletionScope =
        try SharedCompassVMGuestWorkspaceCatalog
        .loadLastSyncedFileSet(forRepoURL: hostRepoURL)
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
    }
    do {
      try await SharedCompassVMWorktreeSync.pull(
        hostWorktreeURL: hostRepoURL,
        guestWorktreePath: guestPath,
        client: client,
        deletionScope: deletionScope
      )
    } catch let error as SharedCompassVMWorktreeSync.SyncError {
      throw SyncError.wrappedSyncFailure(error)
    }

    // Re-stamp the catalog: after a successful pull, the host repo
    // mirrors the guest, so its fingerprint is the new ground truth.
    let snapshot: (fingerprint: String, fileSet: Set<String>)
    do {
      snapshot = try SharedCompassVMHostFingerprint.compute(at: hostRepoURL)
    } catch {
      throw SyncError.fingerprintFailure(detail: "\(error)")
    }
    do {
      try SharedCompassVMGuestWorkspaceCatalog.recordSync(
        forRepoURL: hostRepoURL,
        fingerprint: snapshot.fingerprint,
        fileSet: snapshot.fileSet
      )
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
    }
  }

  // MARK: - Internals

  /// Pushes the host worktree to the guest and, on success, stamps the
  /// catalog with the snapshot so subsequent calls can short-circuit
  /// via the fingerprint comparison. The snapshot is passed in rather
  /// than recomputed because `ensurePopulated` already paid for it on
  /// the way in.
  private static func pushAndRecord(
    hostRepoURL: URL,
    guestPath: String,
    client: AgentVsockClient,
    snapshot: (fingerprint: String, fileSet: Set<String>)
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
    do {
      try SharedCompassVMGuestWorkspaceCatalog.recordSync(
        forRepoURL: hostRepoURL,
        fingerprint: snapshot.fingerprint,
        fileSet: snapshot.fileSet
      )
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
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
