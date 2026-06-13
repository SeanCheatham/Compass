import Foundation

/// Walks a working directory, parses each supported source file through
/// `SymbolExtractor`, and persists the results to a `CodemapStore`. Reading
/// is delegated to `AgentFilesystem` so the same indexer works on the host
/// and (eventually) over the containerized Linux runtime SSH route. Parsing itself runs
/// in-process — tree-sitter is fast enough that the IO dominates.
package struct CodemapIndexer: Sendable {
  /// Max file size to index. Anything larger almost always indicates a
  /// generated artifact, vendored bundle, or binary blob and isn't worth
  /// the parse time.
  package static let defaultMaxFileBytes = 1 * 1024 * 1024
  /// Files smaller than this are usually trivial stubs (`export * from`,
  /// `init.py` style re-exports). Skipped to keep the index focused.
  package static let defaultMinFileBytes = 80
  /// Cap on entries `AgentFilesystem.glob` walks before giving up. Picked
  /// generously so well-sized repos go through in one pass.
  package static let defaultWalkCap = 200_000
  /// Parallelism cap for the parse fan-out. Tree-sitter releases the GIL
  /// equivalent on every grammar boundary so more workers just push memory.
  package static let defaultParallelism = 8

  /// Summary returned from `indexAll(...)`. Counts mirror what the UI's
  /// status row needs to render; per-file detail is on disk in the store.
  package struct Result: Sendable, Equatable {
    package var indexed: Int
    package var unchanged: Int
    package var pruned: Int
    package var skipped: Int
    package var failed: Int
  }

  package let workingDirectory: URL
  package let filesystem: AgentFilesystem
  package let bashRunner: AgentBashRunner
  package let store: CodemapStore
  package let extractor: SymbolExtractor
  package let maxFileBytes: Int
  package let minFileBytes: Int
  package let walkCap: Int
  package let parallelism: Int

  package init(
    workingDirectory: URL,
    store: CodemapStore,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    extractor: SymbolExtractor = SymbolExtractor(),
    maxFileBytes: Int = CodemapIndexer.defaultMaxFileBytes,
    minFileBytes: Int = CodemapIndexer.defaultMinFileBytes,
    walkCap: Int = CodemapIndexer.defaultWalkCap,
    parallelism: Int = CodemapIndexer.defaultParallelism
  ) {
    self.workingDirectory = workingDirectory.standardizedFileURL
    self.store = store
    self.filesystem = filesystem
    self.bashRunner = bashRunner
    self.extractor = extractor
    self.maxFileBytes = maxFileBytes
    self.minFileBytes = minFileBytes
    self.walkCap = walkCap
    self.parallelism = max(1, parallelism)
  }

  /// Bring the on-disk codemap up to date with the working directory.
  /// Files whose content hash matches the cached entry are left alone;
  /// changed files are re-parsed; entries with no remaining source file
  /// are pruned.
  package func indexAll() async throws -> Result {
    let candidates = try await listCandidateFiles()
    let candidateSet = Set(candidates)

    var indexed = 0
    var unchanged = 0
    var skipped = 0
    var failed = 0

    try await withThrowingTaskGroup(of: PerFileOutcome.self) { group in
      var inFlight = 0
      var iterator = candidates.makeIterator()
      while let next = iterator.next() {
        if inFlight >= parallelism {
          if let outcome = try await group.next() {
            inFlight -= 1
            accumulate(
              outcome, indexed: &indexed, unchanged: &unchanged, skipped: &skipped, failed: &failed)
          }
        }
        let target = next
        group.addTask {
          await indexOne(relativePath: target)
        }
        inFlight += 1
      }
      while let outcome = try await group.next() {
        accumulate(
          outcome, indexed: &indexed, unchanged: &unchanged, skipped: &skipped, failed: &failed)
      }
    }

    let pruned = pruneEntries(notIn: candidateSet)

    return Result(
      indexed: indexed,
      unchanged: unchanged,
      pruned: pruned,
      skipped: skipped,
      failed: failed
    )
  }

  /// Read a single file, hash it, and re-parse / save when the hash
  /// differs from what's on disk. Exposed for the incremental refresher
  /// (Phase 4) and for tests; the bulk indexer fans out across this.
  package func indexOne(relativePath: String) async -> PerFileOutcome {
    guard let language = CodemapLanguage.forRelativePath(relativePath) else {
      return .skipped(.unsupportedExtension)
    }
    let absolute = workingDirectory.appendingPathComponent(relativePath)
    let data: Data
    do {
      data = try await filesystem.readFile(at: absolute)
    } catch {
      return .failed(error.localizedDescription)
    }

    if data.count < minFileBytes {
      return .skipped(.tooSmall)
    }
    if data.count > maxFileBytes {
      return .skipped(.tooLarge)
    }
    if data.prefix(8192).contains(0) {
      return .skipped(.binary)
    }

    let contentHash = CodemapHash.sha256Hex(data)
    let existing = store.loadEntry(forRelativePath: relativePath)
    if let existing,
      existing.contentHash == contentHash,
      existing.language == language
    {
      return .unchanged
    }

    let source = String(decoding: data, as: UTF8.self)
    let extraction: CodemapExtraction
    do {
      extraction = try extractor.extract(source: source, language: language)
    } catch {
      return .failed("parse failed: \(error.localizedDescription)")
    }

    let entry = CodemapEntry(
      relativePath: relativePath,
      language: language,
      contentHash: contentHash,
      sizeBytes: data.count,
      symbols: extraction.symbols,
      imports: extraction.imports,
      // Carry the existing summary forward only if the hash it was
      // generated against still matches the new content.
      summary: existing?.summaryContentHash == contentHash ? existing?.summary : nil,
      summaryModel: existing?.summaryContentHash == contentHash ? existing?.summaryModel : nil,
      summaryContentHash: existing?.summaryContentHash == contentHash
        ? existing?.summaryContentHash : nil,
      isGenerated: existing?.isGenerated ?? false
    )
    do {
      try store.saveEntry(entry)
    } catch {
      return .failed("save failed: \(error.localizedDescription)")
    }
    return .indexed
  }

  /// Remove on-disk entries whose `relativePath` no longer appears in the
  /// candidate set. Returns the number of files removed so the caller can
  /// surface it in a status row.
  package func pruneEntries(notIn keep: Set<String>) -> Int {
    var pruned = 0
    for entry in store.loadAllEntries() {
      if !keep.contains(entry.relativePath) {
        do {
          try store.deleteEntry(forRelativePath: entry.relativePath)
          pruned += 1
        } catch {
          // Swallow: a left-behind cache file is fine; we don't want to
          // fail the whole indexing pass over a stale entry we can't
          // delete.
        }
      }
    }
    return pruned
  }

  /// List relative paths that should be parsed. Uses
  /// `git ls-files --cached --others --exclude-standard` so the index
  /// respects `.gitignore` exactly the same way developers expect. Falls
  /// back to a recursive `glob("**/*")` when git isn't available.
  package func listCandidateFiles() async throws -> [String] {
    let gitListing = try? await runGitLsFiles()
    let allRelativePaths: [String]
    if let gitListing, !gitListing.isEmpty {
      allRelativePaths = gitListing
    } else {
      let matches = try await filesystem.glob(
        pattern: "**/*",
        under: workingDirectory,
        walkCap: walkCap
      )
      allRelativePaths = matches.compactMap { match in
        relativize(match.url)
      }
    }
    return
      allRelativePaths
      .filter {
        CodemapLanguage.forRelativePath($0) != nil
          && RepositoryWalkRules.shouldInclude(relativePath: $0)
      }
      .sorted()
  }

  private func runGitLsFiles() async throws -> [String] {
    let result = try await bashRunner.run(
      command: "git ls-files --cached --others --exclude-standard -z",
      workingDirectory: workingDirectory,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw GitListingError.gitFailed(result.stderr)
    }
    return result.stdout
      .split(separator: "\0", omittingEmptySubsequences: true)
      .map(String.init)
  }

  private func relativize(_ url: URL) -> String? {
    let workingPath = workingDirectory.path
    let absolutePath = url.standardizedFileURL.path
    if absolutePath == workingPath { return nil }
    let prefix = workingPath.hasSuffix("/") ? workingPath : workingPath + "/"
    guard absolutePath.hasPrefix(prefix) else { return nil }
    return String(absolutePath.dropFirst(prefix.count))
  }

  private func accumulate(
    _ outcome: PerFileOutcome,
    indexed: inout Int,
    unchanged: inout Int,
    skipped: inout Int,
    failed: inout Int
  ) {
    switch outcome {
    case .indexed: indexed += 1
    case .unchanged: unchanged += 1
    case .skipped: skipped += 1
    case .failed: failed += 1
    }
  }
}

package extension CodemapIndexer {
  enum PerFileOutcome: Sendable, Equatable {
    case indexed
    case unchanged
    case skipped(SkipReason)
    case failed(String)
  }

  enum SkipReason: Sendable, Equatable {
    case unsupportedExtension
    case tooSmall
    case tooLarge
    case binary
  }

  enum GitListingError: Error, LocalizedError {
    case gitFailed(String)

    package var errorDescription: String? {
      switch self {
      case .gitFailed(let stderr): return "git ls-files failed: \(stderr)"
      }
    }
  }
}
