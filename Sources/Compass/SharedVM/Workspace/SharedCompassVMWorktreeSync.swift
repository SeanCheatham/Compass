import Foundation

/// Streams a host git working tree to the guest (and back) over vsock.
///
/// macOS guests TCC-block `AppleVirtIOFS` reads from every process —
/// including LaunchAgents in the GUI session and even root via
/// LaunchDaemon — so a shared VirtioFS directory is not a viable
/// transport for the agent's file operations. Compass instead keeps a
/// guest-local copy of each repo under the `SharedCompassVMGuestLayout`
/// worktree root (allocated by `SharedCompassVMGuestWorkspaceCatalog`) and
/// synchronises via
/// gitignore-aware tar streamed over the existing vsock RPC
/// (`writeFile`, `readFile`, `bash`). No CLT/git is required on the
/// guest because the host owns gitignore filtering on the push side
/// and a small hard-coded exclude list on the pull side covers the
/// heavyweight build dirs (`.build`, `target`, `node_modules`,
/// `dist-newstyle`, `.stack-work`, `build`, `dist`) that dominate
/// working-tree size.
enum SharedCompassVMWorktreeSync {
  /// Maximum bytes a single sync tar may occupy (after base64 in the
  /// JSON frame). The RPC framing caps total frame size at 1.5 GiB
  /// (see `AgentRPCFraming.maxFrameByteCount`); allowing ~1 GiB of
  /// binary tar leaves room for base64 inflation (1.33×) and JSON
  /// envelope overhead. Repos pushing past this need the chunked
  /// transfer path (tracked separately) — failing loudly here beats
  /// truncating a real repo into something the guest agent then
  /// tries to operate on.
  static let maxTarByteCount = 1024 * 1024 * 1024

  /// Directory names skipped when packaging the guest's working tree
  /// on the pull side, and also filtered out of the host push tar and
  /// fingerprint even when a repo's `.gitignore` omits them. SwiftPM
  /// writes `.build/` as untracked output; without this filter a
  /// single local `swift build` balloons the vsock push to thousands
  /// of object files and the Plan agent looks hung while sync runs.
  static let pullSideExcludeDirs: [String] = [
    ".git", ".build", "target", "node_modules", "dist-newstyle", ".stack-work", "build", "dist",
    ".swiftpm",
  ]

  /// True when `relative` lies under a `pullSideExcludeDirs` entry.
  static func excludesSyncPath(_ relative: String) -> Bool {
    for dir in pullSideExcludeDirs {
      if relative == dir || relative.hasPrefix(dir + "/") {
        return true
      }
    }
    return false
  }

  /// Gitignore-respecting host paths eligible for push and fingerprint.
  static func syncableRelativePaths(in worktree: URL) throws -> Set<String> {
    let enumerated = try gitTrackedAndUntracked(in: worktree)
    return enumerated.filter { relative in
      !excludesSyncPath(relative)
        && FileManager.default.fileExists(
          atPath: worktree.appendingPathComponent(relative).path
        )
    }
  }

  enum SyncError: LocalizedError, CustomStringConvertible {
    case hostListFailed(stderr: String)
    case hostTarFailed(stderr: String)
    case hostExtractFailed(stderr: String)
    case guestExtractFailed(exitCode: Int32, stderr: String)
    case guestTarFailed(exitCode: Int32, stderr: String)
    case missingHostWorktree(URL)
    case tarTooLarge(byteCount: Int)
    case invalidGuestPath(String)
    case invalidHostMirrorPath(String)

    var description: String {
      switch self {
      case .hostListFailed(let s): return "host git ls-files failed: \(s)"
      case .hostTarFailed(let s): return "host tar failed: \(s)"
      case .hostExtractFailed(let s): return "host tar extract failed: \(s)"
      case .guestExtractFailed(let code, let s): return "guest extract failed (exit \(code)): \(s)"
      case .guestTarFailed(let code, let s): return "guest tar failed (exit \(code)): \(s)"
      case .missingHostWorktree(let url): return "host worktree does not exist: \(url.path)"
      case .tarTooLarge(let n): return "sync tar exceeded \(maxTarByteCount) bytes (got \(n))"
      case .invalidGuestPath(let p): return "refusing to sync into suspicious guest path: \(p)"
      case .invalidHostMirrorPath(let p):
        return "refusing to refresh suspicious host mirror path: \(p)"
      }
    }

    // LocalizedError — surfaces the actual reason in `localizedDescription`
    // (and therefore in NSError-style UI alerts) instead of the
    // unhelpful "The operation couldn't be completed. (… error N.)"
    // default that bridges in when only `Error` is conformed.
    var errorDescription: String? { description }
  }

  // MARK: - Push (host -> guest)

  /// Wipes (or creates) the guest worktree at `guestWorktreePath` and
  /// re-populates it from a gitignore-aware tar of `hostWorktreeURL`.
  /// Requires the guest agent to be running and the host worktree to
  /// be a git working tree.
  static func push(
    hostWorktreeURL: URL,
    guestWorktreePath: String,
    client: AgentVsockClient
  ) async throws {
    try validateGuestPath(guestWorktreePath)
    let host = hostWorktreeURL.standardizedFileURL
    guard FileManager.default.fileExists(atPath: host.path) else {
      throw SyncError.missingHostWorktree(host)
    }

    let tarData = try buildHostTar(at: host)
    guard tarData.count <= maxTarByteCount else {
      throw SyncError.tarTooLarge(byteCount: tarData.count)
    }

    let tmp = "/tmp/compass-sync-in-\(UUID().uuidString).tar"
    try await client.writeFile(tarData, at: URL(fileURLWithPath: tmp))

    let script = """
      set -e
      mkdir -p '\(guestWorktreePath)'.stage
      rm -rf '\(guestWorktreePath)'.stage
      mkdir -p '\(guestWorktreePath)'.stage
      /usr/bin/tar -xf '\(tmp)' -C '\(guestWorktreePath)'.stage
      rm -rf '\(guestWorktreePath)'
      mkdir -p "$(dirname '\(guestWorktreePath)')"
      mv '\(guestWorktreePath)'.stage '\(guestWorktreePath)'
      rm -f '\(tmp)'
      """
    let result = try await client.run(
      command: script,
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 180
    )
    if result.exitCode != 0 {
      throw SyncError.guestExtractFailed(exitCode: result.exitCode, stderr: result.stderr)
    }
  }

  // MARK: - Pull (guest -> host)

  /// Captures the guest worktree's current state (filtering out
  /// well-known build directories) and applies it onto the host
  /// worktree, deleting files that were on the host at last push but
  /// are no longer present in the guest.
  ///
  /// `deletionScope` is the set of host-relative paths captured at the
  /// last successful sync. The deletion step is intersected with this
  /// set so that user-added files between sessions — which the agent
  /// has never been asked to track — survive the cleanup. When the
  /// scope is nil (no sync recorded yet) the legacy behaviour applies:
  /// delete any host-tracked file missing from the guest. Callers that
  /// have a recorded scope (i.e. went through
  /// `SharedCompassVMRepoWorkspaceSync`) should always pass it.
  static func pull(
    hostWorktreeURL: URL,
    guestWorktreePath: String,
    client: AgentVsockClient,
    deletionScope: Set<String>? = nil
  ) async throws {
    try validateGuestPath(guestWorktreePath)
    let host = hostWorktreeURL.standardizedFileURL

    let suffix = UUID().uuidString
    let tarTmp = "/tmp/compass-sync-out-\(suffix).tar"
    let listTmp = "/tmp/compass-sync-out-\(suffix).list"

    let findPredicates =
      pullSideExcludeDirs
      .map { "-name '\($0)'" }
      .joined(separator: " -o ")
    let script = """
      set -e
      cd '\(guestWorktreePath)'
      find . -type d \\( \(findPredicates) \\) -prune -o -type f -print0 > '\(listTmp)'
      < '\(listTmp)' /usr/bin/tar --null -T - -cf '\(tarTmp)'
      """
    let result = try await client.run(
      command: script,
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 180
    )
    if result.exitCode != 0 {
      throw SyncError.guestTarFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    let tarData = try await client.readFile(at: URL(fileURLWithPath: tarTmp))
    let listData = try await client.readFile(at: URL(fileURLWithPath: listTmp))

    _ = try await client.run(
      command: "rm -f '\(tarTmp)' '\(listTmp)'",
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 30
    )

    let guestRelativePaths = parseFindNullList(listData)
    let hostRelativePaths = (try? gitTrackedAndUntracked(in: host)) ?? []
    let deletions = computeDeletions(
      host: hostRelativePaths,
      guest: guestRelativePaths,
      scope: deletionScope
    )
    for relative in deletions {
      let url = host.appendingPathComponent(relative)
      try? FileManager.default.removeItem(at: url)
    }

    try extractTarOnHost(tarData, into: host)
  }

  // MARK: - Host mirror (guest -> host, no git metadata)

  /// Refreshes a Compass-owned host mirror from the current guest worktree.
  /// Used by the host Xcode bridge so `xcodebuild` can run on the host
  /// against the same source state the Shared VM agent just edited,
  /// without pulling failed attempts into the user's real checkout.
  static func refreshHostMirror(
    guestWorktreePath: String,
    hostMirrorURL: URL,
    client: AgentVsockClient
  ) async throws {
    try validateGuestPath(guestWorktreePath)
    try validateHostMirrorPath(hostMirrorURL)

    let suffix = UUID().uuidString
    let tarTmp = "/tmp/compass-host-xcode-\(suffix).tar"
    let listTmp = "/tmp/compass-host-xcode-\(suffix).list"
    let quotedGuest = SharedCompassVMGuestBridge.posixQuote(guestWorktreePath)
    let quotedTar = SharedCompassVMGuestBridge.posixQuote(tarTmp)
    let quotedList = SharedCompassVMGuestBridge.posixQuote(listTmp)
    let findPredicates =
      pullSideExcludeDirs
      .map { "-name '\($0)'" }
      .joined(separator: " -o ")
    let script = """
      set -e
      cd \(quotedGuest)
      find . -type d \\( \(findPredicates) \\) -prune -o -type f -print0 > \(quotedList)
      < \(quotedList) /usr/bin/tar --null -T - -cf \(quotedTar)
      """
    let result = try await client.run(
      command: script,
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 180
    )
    if result.exitCode != 0 {
      throw SyncError.guestTarFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    let tarData = try await client.readFile(at: URL(fileURLWithPath: tarTmp))
    _ = try await client.run(
      command: "rm -f \(quotedTar) \(quotedList)",
      workingDirectory: URL(fileURLWithPath: "/tmp"),
      timeout: 30
    )

    let mirror = hostMirrorURL.standardizedFileURL
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: mirror.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if fileManager.fileExists(atPath: mirror.path) {
      try fileManager.removeItem(at: mirror)
    }
    try fileManager.createDirectory(at: mirror, withIntermediateDirectories: true)
    try extractTarOnHost(tarData, into: mirror)
  }

  // MARK: - Deletion scope

  /// Eligible deletions = files that were on the host last time we
  /// pushed (so the agent saw them and could have intentionally
  /// removed them) AND are still on the host now (something is there
  /// to delete) AND are no longer in the guest (the agent did remove
  /// them). When `scope` is nil — i.e. no recorded sync yet, typically
  /// a catalog written by a pre-fingerprint build — fall back to
  /// `host − guest` so legacy state still pulls correctly.
  ///
  /// Internal-visible for unit-testing the deletion arithmetic
  /// directly. The real `pull` path computes both `host` and `guest`
  /// from live transports, so the function is pure on inputs to keep
  /// the policy reviewable in isolation.
  static func computeDeletions(
    host: Set<String>,
    guest: Set<String>,
    scope: Set<String>?
  ) -> Set<String> {
    let baseline = scope ?? host
    return baseline.intersection(host).subtracting(guest)
  }

  // MARK: - Internals

  /// Allow-listed guest-side prefixes Compass is willing to sync into.
  /// The sync script's `rm -rf` is wrapped in `validateGuestPath` so
  /// this list is the security boundary — anything not under one of
  /// these roots gets rejected before any guest-side mutation happens.
  ///
  /// Today this is just the persistent per-repo root used by
  /// `SharedCompassVMGuestWorkspaceCatalog`; the root is supplied by
  /// `SharedCompassVMGuestLayout` so a future Linux guest can move it under
  /// `/home/compass` without weakening the allow-list boundary.
  static let allowedGuestPathPrefixes: [String] = [
    SharedCompassVMGuestWorkspaceCatalog.guestReposRoot
  ]

  /// Validates that the guest worktree path is under one of the
  /// allow-listed guest workspaces roots. Defence in depth: prevents
  /// a malformed path from causing the sync script's `rm -rf` to wipe
  /// the wrong directory in the guest.
  private static func validateGuestPath(_ path: String) throws {
    let standardized = (path as NSString).standardizingPath
    guard !standardized.contains("..") else {
      throw SyncError.invalidGuestPath(path)
    }
    for root in allowedGuestPathPrefixes {
      let prefix = root.hasSuffix("/") ? root : root + "/"
      if standardized.hasPrefix(prefix) {
        return
      }
    }
    throw SyncError.invalidGuestPath(path)
  }

  private static func validateHostMirrorPath(_ url: URL) throws {
    let path = url.standardizedFileURL.path
    guard path != "/", !path.isEmpty, !path.contains("..") else {
      throw SyncError.invalidHostMirrorPath(url.path)
    }
  }

  /// Tars the host's tracked + untracked-not-ignored files into a
  /// single in-memory `Data`. Filters out paths that don't currently
  /// exist on disk (e.g. deleted-but-still-staged entries) so tar
  /// doesn't bail with `No such file or directory`.
  private static func buildHostTar(at worktree: URL) throws -> Data {
    let existing = try syncableRelativePaths(in: worktree)

    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["--null", "-T", "-", "-cf", "-"]
    tar.currentDirectoryURL = worktree
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    tar.standardInput = stdin
    tar.standardOutput = stdout
    tar.standardError = stderr

    try tar.run()

    // Feed the NUL-separated relative paths to tar's --null -T -.
    // Writing on a background thread isn't necessary here because
    // tar buffers in libarchive's internal queue and the path list
    // is small even for huge worktrees.
    let listData =
      existing
      .map { Data(($0).utf8) + Data([0]) }
      .reduce(Data(), +)
    do {
      try stdin.fileHandleForWriting.write(contentsOf: listData)
      try stdin.fileHandleForWriting.close()
    } catch {
      tar.terminate()
      tar.waitUntilExit()
      throw SyncError.hostTarFailed(stderr: error.localizedDescription)
    }

    let tarData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
    let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
    tar.waitUntilExit()
    if tar.terminationStatus != 0 {
      throw SyncError.hostTarFailed(stderr: String(decoding: errData, as: UTF8.self))
    }
    return tarData
  }

  /// Runs `git ls-files --cached --others --exclude-standard -z`
  /// in the host worktree and returns the (gitignore-respecting)
  /// path set as relative paths.
  ///
  /// Internal-visible so `SharedCompassVMHostFingerprint` can share the
  /// exact enumeration the push tar uses — fingerprint coverage has to
  /// match push coverage byte-for-byte or drift detection produces
  /// spurious mismatches.
  static func gitTrackedAndUntracked(in worktree: URL) throws -> Set<String> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = [
      "-C", worktree.path,
      "ls-files",
      "--cached", "--others",
      "--exclude-standard",
      "-z",
    ]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
    let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      throw SyncError.hostListFailed(stderr: String(decoding: errData, as: UTF8.self))
    }
    let text = String(decoding: outData, as: UTF8.self)
    let parts = text.split(separator: "\0", omittingEmptySubsequences: true)
    return Set(parts.map(String.init))
  }

  /// Parses the NUL-separated `find ... -print0` output emitted by
  /// the guest's pull script. Paths come in as `./<relative>` form;
  /// the leading `./` is stripped before returning.
  private static func parseFindNullList(_ data: Data) -> Set<String> {
    let text = String(decoding: data, as: UTF8.self)
    let parts = text.split(separator: "\0", omittingEmptySubsequences: true)
    return Set(
      parts.map { raw -> String in
        let s = String(raw)
        if s.hasPrefix("./") { return String(s.dropFirst(2)) }
        return s
      })
  }

  /// Writes the supplied tar bytes to a temp file and runs `tar -xf`
  /// rooted at `target`, overwriting any existing files. The caller
  /// is responsible for having pre-deleted host files that the
  /// guest no longer has.
  private static func extractTarOnHost(_ data: Data, into target: URL) throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-sync-pull-\(UUID().uuidString).tar")
    try data.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-xf", tempURL.path, "-C", target.path]
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      throw SyncError.hostExtractFailed(stderr: String(decoding: errData, as: UTF8.self))
    }
  }
}
