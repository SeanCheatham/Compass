import CryptoKit
import Foundation

/// Content-addressed host↔guest workspace sync over vsock.
///
/// Replaces git-over-SSH and wipe-style tar as the primary wire format:
/// the host builds a path→hash manifest, transfers only missing file blobs
/// into a guest object store, then materializes the worktree **in place**
/// so gitignored build dirs (`target/`, `.build/`) survive. Pull walks the
/// guest worktree (excluding the same build dirs), hashes files, and
/// overlays changed content onto the host with scoped deletions.
///
/// See `docs/host-guest-cas-sync.md`.
public enum SharedCompassVMCASSync {
  public static let objectsDirectoryName = "objects"
  public static let manifestFileName = "manifest.json"
  /// Soft cap per blob transfer (same budget as the tar path).
  public static let maxBlobByteCount = SharedCompassVMWorktreeSync.maxTarByteCount

  enum SyncError: LocalizedError, CustomStringConvertible {
    case catalogFailure(detail: String)
    case fingerprintFailure(detail: String)
    case blobTooLarge(path: String, byteCount: Int)
    case guestCommandFailed(step: String, exitCode: Int32, stderr: String)
    case invalidManifest(detail: String)
    case hostReadFailed(path: String, detail: String)
    case guestReadFailed(path: String, detail: String)

    var description: String {
      switch self {
      case .catalogFailure(let detail):
        return "CAS sync catalog failure: \(detail)"
      case .fingerprintFailure(let detail):
        return "CAS sync fingerprint failure: \(detail)"
      case .blobTooLarge(let path, let byteCount):
        return "CAS blob for \(path) exceeds \(maxBlobByteCount) bytes (got \(byteCount))"
      case .guestCommandFailed(let step, let code, let stderr):
        return "CAS guest \(step) failed (exit \(code)): \(stderr)"
      case .invalidManifest(let detail):
        return "CAS manifest invalid: \(detail)"
      case .hostReadFailed(let path, let detail):
        return "CAS host read failed (\(path)): \(detail)"
      case .guestReadFailed(let path, let detail):
        return "CAS guest read failed (\(path)): \(detail)"
      }
    }

    var errorDescription: String? { description }
  }

  public struct Manifest: Codable, Equatable, Sendable {
    public var id: String
    public var entries: [Entry]

    public struct Entry: Codable, Equatable, Sendable {
      public var path: String
      public var hash: String
      /// `file` or `symlink`.
      public var kind: String
      public var symlinkTarget: String?

      public init(path: String, hash: String, kind: String, symlinkTarget: String? = nil) {
        self.path = path
        self.hash = hash
        self.kind = kind
        self.symlinkTarget = symlinkTarget
      }
    }

    public init(id: String, entries: [Entry]) {
      self.id = id
      self.entries = entries
    }

    public var pathSet: Set<String> { Set(entries.map(\.path)) }

    public func entryMap() -> [String: Entry] {
      Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    }
  }

  public struct GuestPaths: Equatable {
    public var workspaceRoot: String
    public var worktreePath: String
    public var objectsPath: String
    public var manifestPath: String
  }

  public static func guestPaths(workspaceID: String) -> GuestPaths {
    let root = "\(SharedCompassVMGuestLayout.current.reposRoot)/\(workspaceID)"
    return GuestPaths(
      workspaceRoot: root,
      worktreePath: SharedCompassVMGuestLayout.current.worktreePath(
        workspaceID: workspaceID,
        subdirectory: SharedCompassVMGuestWorkspaceCatalog.guestWorktreeSubdirectory
      ),
      objectsPath: "\(root)/\(objectsDirectoryName)",
      manifestPath: "\(root)/\(manifestFileName)"
    )
  }

  // MARK: - Manifest construction

  /// Builds a manifest for the host worktree (gitignore-aware syncable set).
  public static func buildHostManifest(at hostWorktreeURL: URL) throws -> Manifest {
    let paths = try SharedCompassVMWorktreeSync.syncableRelativePaths(in: hostWorktreeURL)
    var entries: [Manifest.Entry] = []
    entries.reserveCapacity(paths.count)
    for relative in paths.sorted() {
      let url = hostWorktreeURL.appendingPathComponent(relative)
      let hash = try SharedCompassVMHostFingerprint.hashContent(at: url, relativePath: relative)
      let kind = try SharedCompassVMHostFingerprint.contentKind(at: url, relativePath: relative)
      switch kind {
      case .file:
        entries.append(Manifest.Entry(path: relative, hash: hash, kind: "file"))
      case .symlink(let target):
        entries.append(
          Manifest.Entry(path: relative, hash: hash, kind: "symlink", symlinkTarget: target))
      case .nonRegular:
        // Skip sockets/devices — fingerprint still sees them for drift, but
        // they are not transferable sync payload.
        continue
      }
    }
    return Manifest(id: manifestID(for: entries), entries: entries)
  }

  public static func manifestID(for entries: [Manifest.Entry]) -> String {
    var combined = Data()
    for entry in entries.sorted(by: { $0.path < $1.path }) {
      combined.append(Data(entry.path.utf8))
      combined.append(0)
      combined.append(Data(entry.hash.utf8))
      combined.append(0)
      combined.append(Data(entry.kind.utf8))
      combined.append(0)
      if let target = entry.symlinkTarget {
        combined.append(Data(target.utf8))
      }
      combined.append(0)
    }
    return CodemapHash.sha256Hex(combined)
  }

  public static func objectRelativePath(forHash hash: String) -> String {
    precondition(hash.count >= 4)
    let prefix = String(hash.prefix(2))
    let rest = String(hash.dropFirst(2))
    return "\(objectsDirectoryName)/\(prefix)/\(rest)"
  }

  // MARK: - Push

  /// Pushes the host repo into the guest via CAS and returns the guest
  /// worktree path. When `forceRefresh` is true, applies even if the
  /// guest manifest id already matches.
  public static func syncToGuest(
    hostRepoURL: URL,
    client: AgentVsockClient,
    forceRefresh: Bool = false
  ) async throws -> String {
    let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: hostRepoURL)
    let paths = guestPaths(workspaceID: entry.id)
    try SharedCompassVMWorktreeSync.validateGuestPath(paths.worktreePath)

    try await ensureGuestLayout(paths: paths, client: client)

    let manifest = try buildHostManifest(at: hostRepoURL)
    if !forceRefresh, let existing = try await readGuestManifest(paths: paths, client: client),
      existing.id == manifest.id
    {
      try recordCatalog(hostRepoURL: hostRepoURL)
      return paths.worktreePath
    }

    let previous = try await readGuestManifest(paths: paths, client: client)
    try await transferMissingBlobs(
      hostRepoURL: hostRepoURL,
      manifest: manifest,
      previous: previous,
      paths: paths,
      client: client
    )
    try await materializeWorktree(
      manifest: manifest,
      previous: previous,
      paths: paths,
      client: client
    )
    try await writeGuestManifest(manifest, paths: paths, client: client)
    try recordCatalog(hostRepoURL: hostRepoURL)
    return paths.worktreePath
  }

  // MARK: - Pull

  /// Pulls guest worktree edits back onto the host with scoped deletions.
  public static func pullFromGuest(
    hostRepoURL: URL,
    client: AgentVsockClient
  ) async throws {
    let entry: SharedCompassVMGuestWorkspaceCatalog.CatalogEntry
    do {
      guard let loaded = try SharedCompassVMGuestWorkspaceCatalog.loadEntry(forRepoURL: hostRepoURL)
      else {
        throw SyncError.catalogFailure(
          detail: "no catalog entry for host repo \(hostRepoURL.path)")
      }
      entry = loaded
    } catch let error as SyncError {
      throw error
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
    }

    let paths = guestPaths(workspaceID: entry.id)
    try SharedCompassVMWorktreeSync.validateGuestPath(paths.worktreePath)

    let guestManifest = try await scanGuestWorktree(paths: paths, client: client)
    let previous = try await readGuestManifest(paths: paths, client: client)
    let previousMap = previous?.entryMap() ?? [:]
    let host = hostRepoURL.standardizedFileURL

    let deletionScope: Set<String>?
    do {
      deletionScope = try SharedCompassVMGuestWorkspaceCatalog.loadLastSyncedFileSet(
        forRepoURL: hostRepoURL)
    } catch {
      throw SyncError.catalogFailure(detail: "\(error)")
    }

    let hostPaths = (try? SharedCompassVMWorktreeSync.syncableRelativePaths(in: host)) ?? []
    let deletions = SharedCompassVMWorktreeSync.computeDeletions(
      host: hostPaths,
      guest: guestManifest.pathSet,
      scope: deletionScope
    )
    for relative in deletions {
      try? FileManager.default.removeItem(at: host.appendingPathComponent(relative))
    }

    for entry in guestManifest.entries {
      if let prior = previousMap[entry.path], prior.hash == entry.hash,
        FileManager.default.fileExists(atPath: host.appendingPathComponent(entry.path).path)
      {
        // Unchanged since last sync and still present on host — skip transfer.
        // Still rewrite if host drifted; compare host hash when present.
        let hostURL = host.appendingPathComponent(entry.path)
        if let hostHash = try? SharedCompassVMHostFingerprint.hashContent(
          at: hostURL, relativePath: entry.path), hostHash == entry.hash
        {
          continue
        }
      }
      try await pullEntry(entry, paths: paths, host: host, client: client)
    }

    try await writeGuestManifest(guestManifest, paths: paths, client: client)
    try recordCatalog(hostRepoURL: hostRepoURL)
  }

  // MARK: - Internals

  private static func ensureGuestLayout(
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws {
    let script = """
      set -e
      mkdir -p \(quote(paths.worktreePath))
      mkdir -p \(quote(paths.objectsPath))
      """
    try await runGuest(script, client: client, step: "layout")
  }

  private static func readGuestManifest(
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws -> Manifest? {
    do {
      let data = try await client.readFile(at: URL(fileURLWithPath: paths.manifestPath))
      guard !data.isEmpty else { return nil }
      return try JSONDecoder().decode(Manifest.self, from: data)
    } catch {
      // Missing file is the common cold-start case.
      return nil
    }
  }

  private static func writeGuestManifest(
    _ manifest: Manifest,
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws {
    let data = try JSONEncoder().encode(manifest)
    try await client.writeFile(data, at: URL(fileURLWithPath: paths.manifestPath))
  }

  private static func transferMissingBlobs(
    hostRepoURL: URL,
    manifest: Manifest,
    previous: Manifest?,
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws {
    let previousMap = previous?.entryMap() ?? [:]
    var neededHashes: [String: String] = [:]  // hash → path (for errors)
    for entry in manifest.entries where entry.kind == "file" {
      if let prior = previousMap[entry.path], prior.hash == entry.hash { continue }
      neededHashes[entry.hash] = entry.path
    }
    guard !neededHashes.isEmpty else { return }

    let missing = try await missingBlobHashes(
      Array(neededHashes.keys), paths: paths, client: client)
    for hash in missing {
      let relative = neededHashes[hash] ?? hash
      let hostFile = hostRepoURL.appendingPathComponent(relative)
      let data: Data
      do {
        data = try Data(contentsOf: hostFile, options: [.mappedIfSafe])
      } catch {
        throw SyncError.hostReadFailed(path: relative, detail: "\(error)")
      }
      guard data.count <= maxBlobByteCount else {
        throw SyncError.blobTooLarge(path: relative, byteCount: data.count)
      }
      let objectPath = "\(paths.workspaceRoot)/\(objectRelativePath(forHash: hash))"
      let dir = (objectPath as NSString).deletingLastPathComponent
      try await runGuest("mkdir -p \(quote(dir))", client: client, step: "mkdir-object")
      try await client.writeFile(data, at: URL(fileURLWithPath: objectPath))
    }
  }

  private static func missingBlobHashes(
    _ hashes: [String],
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws -> [String] {
    guard !hashes.isEmpty else { return [] }
    let listPath = SharedCompassVMWorktreeSync.guestSyncStagingPath(
      nearGuestWorktreePath: paths.worktreePath,
      name: "compass-cas-have-\(UUID().uuidString).txt"
    )
    let listData = Data(hashes.joined(separator: "\n").utf8) + Data("\n".utf8)
    try await client.writeFile(listData, at: URL(fileURLWithPath: listPath))
    let script = """
      set -e
      missing=""
      while IFS= read -r hash; do
        [ -z "$hash" ] && continue
        prefix=$(printf '%s' "$hash" | cut -c1-2)
        rest=$(printf '%s' "$hash" | cut -c3-)
        obj=\(quote(paths.objectsPath))/"$prefix"/"$rest"
        if [ ! -f "$obj" ]; then
          printf '%s\\n' "$hash"
        fi
      done < \(quote(listPath))
      rm -f \(quote(listPath))
      """
    let result = try await client.run(
      command: script,
      workingDirectory: URL(fileURLWithPath: paths.workspaceRoot),
      timeout: 180
    )
    guard result.exitCode == 0 else {
      throw SyncError.guestCommandFailed(
        step: "have-blobs", exitCode: result.exitCode, stderr: result.stderr)
    }
    return result.stdout
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  private static func materializeWorktree(
    manifest: Manifest,
    previous: Manifest?,
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws {
    let previousMap = previous?.entryMap() ?? [:]
    let newMap = manifest.entryMap()

    // Deletions: in previous but not in new (syncable paths only).
    let deleted = previousMap.keys.filter { newMap[$0] == nil }
    if !deleted.isEmpty {
      var rmScript = "set -e\ncd \(quote(paths.worktreePath))\n"
      for relative in deleted {
        guard !SharedCompassVMWorktreeSync.excludesSyncPath(relative) else { continue }
        rmScript += "rm -rf -- \(quote(relative))\n"
      }
      try await runGuest(rmScript, client: client, step: "delete")
    }

    var linkCommands: [String] = ["set -e", "cd \(quote(paths.worktreePath))"]
    var copyCommands: [String] = ["set -e", "cd \(quote(paths.worktreePath))"]

    for entry in manifest.entries {
      if let prior = previousMap[entry.path], prior.hash == entry.hash,
        prior.kind == entry.kind, prior.symlinkTarget == entry.symlinkTarget
      {
        continue
      }
      let parent = (entry.path as NSString).deletingLastPathComponent
      if !parent.isEmpty && parent != "." {
        linkCommands.append("mkdir -p \(quote(parent))")
        copyCommands.append("mkdir -p \(quote(parent))")
      }
      if entry.kind == "symlink" {
        let target = entry.symlinkTarget ?? ""
        linkCommands.append("rm -rf -- \(quote(entry.path))")
        linkCommands.append("ln -s \(quote(target)) \(quote(entry.path))")
      } else {
        let objectPath = "\(paths.workspaceRoot)/\(objectRelativePath(forHash: entry.hash))"
        copyCommands.append("rm -rf -- \(quote(entry.path))")
        copyCommands.append("cp \(quote(objectPath)) \(quote(entry.path))")
      }
    }

    if linkCommands.count > 2 {
      try await runGuest(linkCommands.joined(separator: "\n"), client: client, step: "symlinks")
    }
    if copyCommands.count > 2 {
      try await runGuest(copyCommands.joined(separator: "\n"), client: client, step: "materialize")
    }
  }

  private static func scanGuestWorktree(
    paths: GuestPaths,
    client: AgentVsockClient
  ) async throws -> Manifest {
    let listPath = SharedCompassVMWorktreeSync.guestSyncStagingPath(
      nearGuestWorktreePath: paths.worktreePath,
      name: "compass-cas-scan-\(UUID().uuidString).txt"
    )
    let findPredicates =
      SharedCompassVMWorktreeSync.pullSideExcludeDirs
      .map { "-name '\($0)'" }
      .joined(separator: " -o ")
    let script = """
      set -e
      cd \(quote(paths.worktreePath))
      : > \(quote(listPath))
      find . -type d \\( \(findPredicates) \\) -prune -o \\( -type f -o -type l \\) -print0 \
        | while IFS= read -r -d '' f; do
            rel="${f#./}"
            case "$rel" in
              "") continue ;;
            esac
            if [ -L "$f" ]; then
              target=$(readlink "$f")
              # Hash matches host fingerprint: SHA-256 of "symlink:" + target.
              hash=$(printf 'symlink:%s' "$target" | shasum -a 256 | awk '{print $1}')
              printf 'symlink\\t%s\\t%s\\t%s\\n' "$rel" "$hash" "$target" >> \(quote(listPath))
            elif [ -f "$f" ]; then
              hash=$(shasum -a 256 "$f" | awk '{print $1}')
              printf 'file\\t%s\\t%s\\n' "$rel" "$hash" >> \(quote(listPath))
            fi
          done
      """
    try await runGuest(script, client: client, step: "scan")
    let data = try await client.readFile(at: URL(fileURLWithPath: listPath))
    _ = try await client.run(
      command: "rm -f \(quote(listPath))",
      workingDirectory: URL(fileURLWithPath: paths.workspaceRoot),
      timeout: 30
    )

    var entries: [Manifest.Entry] = []
    let text = String(decoding: data, as: UTF8.self)
    for line in text.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 3 else { continue }
      let kind = parts[0]
      let path = parts[1]
      let hash = parts[2]
      if SharedCompassVMWorktreeSync.excludesSyncPath(path) { continue }
      if kind == "symlink" {
        let target = parts.count > 3 ? parts[3] : ""
        entries.append(
          Manifest.Entry(path: path, hash: hash, kind: "symlink", symlinkTarget: target))
      } else {
        entries.append(Manifest.Entry(path: path, hash: hash, kind: "file"))
      }
    }
    entries.sort { $0.path < $1.path }
    return Manifest(id: manifestID(for: entries), entries: entries)
  }

  private static func pullEntry(
    _ entry: Manifest.Entry,
    paths: GuestPaths,
    host: URL,
    client: AgentVsockClient
  ) async throws {
    let hostURL = host.appendingPathComponent(entry.path)
    let parent = hostURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    if entry.kind == "symlink" {
      let target = entry.symlinkTarget ?? ""
      try? FileManager.default.removeItem(at: hostURL)
      try FileManager.default.createSymbolicLink(
        atPath: hostURL.path, withDestinationPath: target)
      return
    }

    let guestFile = "\(paths.worktreePath)/\(entry.path)"
    let data: Data
    do {
      data = try await client.readFile(at: URL(fileURLWithPath: guestFile))
    } catch {
      throw SyncError.guestReadFailed(path: entry.path, detail: "\(error)")
    }
    guard data.count <= maxBlobByteCount else {
      throw SyncError.blobTooLarge(path: entry.path, byteCount: data.count)
    }
    try? FileManager.default.removeItem(at: hostURL)
    try data.write(to: hostURL, options: .atomic)
  }

  private static func recordCatalog(hostRepoURL: URL) throws {
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
      throw SyncError.guestCommandFailed(
        step: step, exitCode: result.exitCode, stderr: result.stderr)
    }
  }

  private static func quote(_ path: String) -> String {
    SharedCompassVMGuestBridge.posixQuote(path)
  }
}
