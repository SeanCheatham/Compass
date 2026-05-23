import Foundation

/// Reads and writes per-file `CodemapEntry` JSON documents under
/// `.compass/codemap/`. Path-keyed: the on-disk filename is the SHA-256 of
/// the entry's `relativePath`, so two files with similar names never
/// collide. Concurrent indexers can write different entries in parallel
/// without coordinating.
struct CodemapStore: Sendable {
  /// Directory the store owns. Created lazily on first write.
  let directory: URL
  /// Set to true in tests to assert structured logging when entries change.
  let prettyPrint: Bool

  init(directory: URL, prettyPrint: Bool = false) {
    self.directory = directory.standardizedFileURL
    self.prettyPrint = prettyPrint
  }

  /// Default location: `<workspaceCompass>/codemap/`. The store mirrors the
  /// rest of `.compass/` so the cache moves with whatever storage root the
  /// workspace picks.
  static func defaultDirectory(forWorkspace workspace: CompassWorkspace) -> URL {
    workspace.compassURL
      .appending(path: "codemap", directoryHint: .isDirectory)
      .standardizedFileURL
  }

  /// Absolute path the entry for `relativePath` lives at, whether or not
  /// the file currently exists.
  func entryURL(forRelativePath relativePath: String) -> URL {
    directory.appending(path: filename(for: relativePath))
  }

  /// Disk filename for `relativePath`. Public so tests can verify naming.
  func filename(for relativePath: String) -> String {
    "\(CodemapHash.sha256Hex(relativePath)).json"
  }

  /// Load the entry for `relativePath`, or nil if absent / unreadable.
  /// Decode failures (corrupt JSON, schema mismatch from an older build)
  /// return nil rather than throwing so a stale cache file silently
  /// triggers a re-parse.
  func loadEntry(forRelativePath relativePath: String) -> CodemapEntry? {
    let url = entryURL(forRelativePath: relativePath)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }
    return try? Self.decoder.decode(CodemapEntry.self, from: data)
  }

  /// Atomically replace the on-disk entry for `entry.relativePath`. Creates
  /// the codemap directory on first write.
  func saveEntry(_ entry: CodemapEntry) throws {
    try ensureDirectoryExists()
    let url = entryURL(forRelativePath: entry.relativePath)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [
      .sortedKeys, .withoutEscapingSlashes,
      prettyPrint ? .prettyPrinted : [],
    ]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(entry)
    try data.write(to: url, options: .atomic)
  }

  /// Delete the entry for `relativePath`. Idempotent — missing files are
  /// silently OK.
  func deleteEntry(forRelativePath relativePath: String) throws {
    let url = entryURL(forRelativePath: relativePath)
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) {
      try fm.removeItem(at: url)
    }
  }

  /// Iterate every entry on disk. Returns lazily-loaded pairs so a caller
  /// pruning stale entries doesn't have to hold them all in memory.
  func allEntryURLs() -> [URL] {
    let fm = FileManager.default
    guard
      let names = try? fm.contentsOfDirectory(atPath: directory.path)
    else { return [] }
    return names.filter { $0.hasSuffix(".json") }
      .map { directory.appending(path: $0) }
  }

  /// Decode every entry currently on disk. Skips files that fail to
  /// decode; callers that need to detect corruption should iterate
  /// `allEntryURLs()` directly.
  func loadAllEntries() -> [CodemapEntry] {
    allEntryURLs().compactMap { url in
      guard let data = try? Data(contentsOf: url), !data.isEmpty else {
        return nil
      }
      return try? Self.decoder.decode(CodemapEntry.self, from: data)
    }
  }

  func ensureDirectoryExists() throws {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    if fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
      if !isDirectory.boolValue {
        throw CocoaError(.fileWriteFileExists)
      }
      return
    }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  fileprivate static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()
}
