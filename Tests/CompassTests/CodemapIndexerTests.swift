import Foundation
import Testing

@testable import Compass

struct CodemapIndexerTests: ~Copyable {
  private var workingDirectory: URL!
  private var cacheDirectory: URL!

  init() throws {
    workingDirectory = try makeTempDir()
    cacheDirectory = workingDirectory.appendingPathComponent(".compass/codemap")
  }

  deinit {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
  }

  // MARK: - CodemapStore

  @Test func testStoreRoundTripsAnEntry() throws {
    let store = CodemapStore(directory: cacheDirectory, prettyPrint: true)
    let entry = CodemapEntry(
      relativePath: "Sources/Compass/Foo.swift",
      language: .swift,
      contentHash: String(repeating: "a", count: 64),
      sizeBytes: 1024,
      symbols: [
        CodemapSymbol(kind: .class, name: "Foo", line: 4, endLine: 12),
        CodemapSymbol(kind: .function, name: "bar", line: 7, endLine: 9),
      ],
      imports: [
        CodemapImport(raw: "Foundation", line: 1)
      ],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )

    try store.saveEntry(entry)

    let url = store.entryURL(forRelativePath: entry.relativePath)
    try #require(FileManager.default.fileExists(atPath: url.path))
    try #require(
      url.lastPathComponent == "\(CodemapHash.sha256Hex(entry.relativePath)).json"
    )

    let loaded = try #require(
      store.loadEntry(forRelativePath: entry.relativePath)
    )
    try #require(loaded == entry)
  }

  @Test func testStoreDeletesAndIgnoresMissing() throws {
    let store = CodemapStore(directory: cacheDirectory)
    let entry = CodemapEntry(
      relativePath: "lib.rs",
      language: .rust,
      contentHash: "deadbeef",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)
    try #require(store.loadEntry(forRelativePath: "lib.rs") != nil)
    try store.deleteEntry(forRelativePath: "lib.rs")
    try #require(store.loadEntry(forRelativePath: "lib.rs") == nil)
    // Idempotent.
    try store.deleteEntry(forRelativePath: "lib.rs")
  }

  @Test func testStoreSkipsCorruptEntries() throws {
    let store = CodemapStore(directory: cacheDirectory)
    try store.ensureDirectoryExists()
    let corrupt = store.entryURL(forRelativePath: "broken.swift")
    try "{not json".data(using: .utf8)!.write(to: corrupt)
    try #require(store.loadEntry(forRelativePath: "broken.swift") == nil)
  }

  // MARK: - Indexer

  @Test func testIndexerWritesEntriesForSupportedFiles() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("nested/beta.py", contents: pythonFixture)
    try writeFile("ignored.bin", contents: "\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}")
    try writeFile("README.md", contents: "# title")

    let indexer = makeIndexer(usingGit: false)
    let result = try await indexer.indexAll()

    try #require(result.indexed == 2)
    try #require(result.failed == 0)
    try #require(result.pruned == 0)

    let store = indexer.store
    let alpha = try #require(store.loadEntry(forRelativePath: "alpha.swift"))
    try #require(alpha.language == .swift)
    try #require(alpha.symbols.contains { $0.name == "Greeter" })
    let beta = try #require(store.loadEntry(forRelativePath: "nested/beta.py"))
    try #require(beta.language == .python)
    try #require(beta.symbols.contains { $0.name == "shout" })
  }

  @Test func testIndexerSurvivesACacheRoundTrip() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)

    let indexer = makeIndexer(usingGit: false)
    _ = try await indexer.indexAll()

    // Spawning a fresh indexer over the same store should observe the
    // existing entry and treat it as unchanged.
    let second = makeIndexer(usingGit: false)
    let result = try await second.indexAll()
    try #require(result.indexed == 0)
    try #require(result.unchanged == 1)
  }

  @Test func testIndexerReParsesOnlyChangedFiles() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("beta.swift", contents: swiftFixture)

    let indexer = makeIndexer(usingGit: false)
    _ = try await indexer.indexAll()

    // Mutate beta only.
    try writeFile(
      "beta.swift",
      contents: swiftFixture + "\nfunc newlyAdded() {}\n"
    )

    let result = try await indexer.indexAll()
    try #require(result.unchanged == 1)
    try #require(result.indexed == 1)

    let updated = try #require(
      indexer.store.loadEntry(forRelativePath: "beta.swift")
    )
    try #require(updated.symbols.contains { $0.name == "newlyAdded" })
  }

  @Test func testIndexerPrunesEntriesForDeletedFiles() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("beta.swift", contents: swiftFixture)

    let indexer = makeIndexer(usingGit: false)
    _ = try await indexer.indexAll()
    try #require(indexer.store.loadEntry(forRelativePath: "beta.swift") != nil)

    try FileManager.default.removeItem(
      at: workingDirectory.appendingPathComponent("beta.swift")
    )

    let result = try await indexer.indexAll()
    try #require(result.pruned == 1)
    try #require(indexer.store.loadEntry(forRelativePath: "beta.swift") == nil)
    try #require(indexer.store.loadEntry(forRelativePath: "alpha.swift") != nil)
  }

  @Test func testIndexerSkipsFilesAboveSizeCap() async throws {
    let huge = String(repeating: "// padding\n", count: 200_000)
    try writeFile("huge.swift", contents: huge)
    try writeFile("alpha.swift", contents: swiftFixture)

    let indexer = makeIndexer(
      usingGit: false,
      maxFileBytes: 10_000  // forces huge.swift to skip
    )
    let result = try await indexer.indexAll()
    try #require(result.indexed == 1)
    try #require(result.skipped == 1)
    try #require(indexer.store.loadEntry(forRelativePath: "huge.swift") == nil)
  }

  @Test func testIndexerHonorsGitignoreWhenInsideARepo() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("ignored.swift", contents: swiftFixture)
    try writeFile(".gitignore", contents: "ignored.swift\n")

    let initStatus = runShell(
      "git init -q && git add alpha.swift .gitignore && git -c user.email=t@t -c user.name=t commit -q -m init"
    )
    try #require(initStatus, "git is not available; skipping")

    let indexer = makeIndexer(usingGit: true)
    let result = try await indexer.indexAll()
    try #require(result.indexed == 1)
    try #require(indexer.store.loadEntry(forRelativePath: "alpha.swift") != nil)
    try #require(indexer.store.loadEntry(forRelativePath: "ignored.swift") == nil)
  }

  // MARK: - Helpers

  private func makeIndexer(
    usingGit: Bool,
    maxFileBytes: Int = CodemapIndexer.defaultMaxFileBytes
  ) -> CodemapIndexer {
    let store = CodemapStore(directory: cacheDirectory)
    return CodemapIndexer(
      workingDirectory: workingDirectory,
      store: store,
      filesystem: AgentHostFilesystem(),
      bashRunner: usingGit ? AgentHostBashRunner() : DisabledBashRunner(),
      maxFileBytes: maxFileBytes,
      minFileBytes: 0,
      parallelism: 4
    )
  }

  private func writeFile(_ relative: String, contents: String) throws {
    let url = workingDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  @discardableResult
  private func runShell(_ command: String) -> Bool {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  private let swiftFixture = """
    import Foundation

    class Greeter {
      func hi() -> String { "hi" }
    }

    func topLevel() {}
    """

  private let pythonFixture = """
    import os

    def shout(name):
        return name.upper()

    class Echo:
        def call(self): ...
    """
}

/// Stand-in bash runner that always fails so tests can assert the indexer
/// falls back to the filesystem walk when git isn't available.
private struct DisabledBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    ProcessResult(exitCode: 127, stdout: "", stderr: "git disabled in test")
  }
}
