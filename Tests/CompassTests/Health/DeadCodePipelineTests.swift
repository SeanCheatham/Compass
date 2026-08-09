import Foundation
import Testing

@testable import CompassCore

@Suite("DeadCodeCandidates")
struct DeadCodeCandidateTests {
  @Test("parses rustc dead_code and unused_imports from cargo JSON")
  func parseDiagnostics() {
    let json = """
      {"reason":"compiler-message","message":{"code":{"code":"dead_code"},"level":"warning","message":"function `orphan_helper` is never used","spans":[{"file_name":"crates/core/src/lib.rs","line_start":40,"line_end":48,"is_primary":true}]}}
      {"reason":"compiler-message","message":{"code":{"code":"unused_imports"},"level":"warning","message":"unused import: `std::collections::HashMap`","spans":[{"file_name":"crates/core/src/lib.rs","line_start":3,"line_end":3,"is_primary":true}]}}
      {"reason":"compiler-message","message":{"code":{"code":"unused_macros"},"level":"warning","message":"unused macro definition: `debug_me`","spans":[{"file_name":"src/macros.rs","line_start":1,"line_end":5,"is_primary":true}]}}
      {"reason":"compiler-message","message":{"code":{"code":"unused_must_use"},"level":"warning","message":"unused `Result` that must be used","spans":[{"file_name":"src/lib.rs","line_start":9,"line_end":9,"is_primary":true}]}}
      {"reason":"build-finished","success":true}
      """
    let candidates = DeadCodeCandidateParser.parse(cargoJSONLines: json)
    #expect(candidates.count == 3)
    #expect(candidates.map(\.lint).sorted() == ["dead_code", "unused_imports", "unused_macros"])
    #expect(candidates.contains(where: { $0.symbol == "orphan_helper" && $0.startLine == 40 }))
    #expect(candidates.contains(where: { $0.symbol == "std::collections::HashMap" }))
    #expect(candidates.contains(where: { $0.symbol == "debug_me" && $0.file == "src/macros.rs" }))
  }

  @Test("normalizes absolute cargo paths to repo-relative")
  func normalizeAbsolute() {
    let json = """
      {"reason":"compiler-message","message":{"code":{"code":"dead_code"},"level":"warning","message":"struct `Gone` is never constructed","spans":[{"file_name":"/Users/dev/proj/crates/core/src/gone.rs","line_start":1,"line_end":4,"is_primary":true}]}}
      """
    let candidates = DeadCodeCandidateParser.parse(cargoJSONLines: json)
    #expect(candidates.count == 1)
    #expect(candidates[0].file == "crates/core/src/gone.rs")
    #expect(candidates[0].symbol == "Gone")
  }
}

@Suite("SpanEditor")
struct SpanEditorTests {
  @Test("deletes inclusive line ranges bottom-up per file")
  func deleteLines() {
    let text = """
      line1
      line2
      line3
      line4
      line5
      """
    let after = SpanEditor.deleteLines(in: text, startLine: 2, endLine: 3)
    #expect(after == "line1\nline4\nline5")

    let originals = ["src/lib.rs": text]
    let candidates = [
      DeadCodeCandidate(
        file: "src/lib.rs", startLine: 4, endLine: 4, lint: "dead_code", message: "x"),
      DeadCodeCandidate(
        file: "src/lib.rs", startLine: 1, endLine: 1, lint: "dead_code", message: "y"),
    ]
    let edited = SpanEditor.applyDeletions(originals: originals, candidates: candidates)
    #expect(edited["src/lib.rs"] == "line2\nline3\nline5")
  }

  @Test("expansion prefers unused_imports from check output")
  func expansion() {
    let existing = [
      DeadCodeCandidate(
        file: "src/lib.rs", startLine: 10, endLine: 20, lint: "dead_code", message: "fn")
    ]
    let json = """
      {"reason":"compiler-message","message":{"code":{"code":"unused_imports"},"level":"warning","message":"unused import: `foo`","spans":[{"file_name":"src/lib.rs","line_start":2,"line_end":2,"is_primary":true}]}}
      {"reason":"compiler-message","message":{"code":{"code":"dead_code"},"level":"warning","message":"function `big` is never used","spans":[{"file_name":"src/lib.rs","line_start":30,"line_end":80,"is_primary":true}]}}
      """
    let added = SpanEditor.expansionCandidates(from: json, excluding: existing)
    #expect(added.count == 1)
    #expect(added[0].lint == "unused_imports")
    #expect(added[0].startLine == 2)
  }
}

@Suite("DeletionTesterBatch")
struct DeletionTesterBatchTests {
  @Test("probe marks proven when check and test exit 0")
  func provenBatch() async {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "compass-deletion-proven-\(UUID().uuidString)")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let src = root.appending(path: "src")
    try! fm.createDirectory(at: src, withIntermediateDirectories: true)
    let file = src.appending(path: "lib.rs")
    let original = """
      fn live() {}
      fn dead() {}
      """
    try! original.write(to: file, atomically: true, encoding: .utf8)

    let candidate = DeadCodeCandidate(
      file: "src/lib.rs",
      startLine: 2,
      endLine: 2,
      symbol: "dead",
      lint: "dead_code",
      message: "function `dead` is never used"
    )
    let bash = ScriptedBashRunner(results: [
      ProcessResult(exitCode: 0, stdout: "", stderr: ""),  // check
      ProcessResult(exitCode: 0, stdout: "1 passed", stderr: ""),  // test
    ])
    let result = await DeletionTester.probe(
      repoURL: root,
      candidates: [candidate],
      bashRunner: bash,
      timeout: 30
    )
    #expect(result.proven.count == 1)
    #expect(result.live.isEmpty)
    #expect(result.tangled.isEmpty)
    // Always restored
    let restored = try! String(contentsOf: file, encoding: .utf8)
    #expect(restored == original)
  }

  @Test("probe marks live when tests fail after clean compile")
  func liveBatch() async {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "compass-deletion-live-\(UUID().uuidString)")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let src = root.appending(path: "src")
    try! fm.createDirectory(at: src, withIntermediateDirectories: true)
    let file = src.appending(path: "lib.rs")
    try! "fn a() {}\nfn b() {}\n".write(to: file, atomically: true, encoding: .utf8)

    let candidate = DeadCodeCandidate(
      file: "src/lib.rs", startLine: 2, endLine: 2, lint: "dead_code", message: "b"
    )
    let bash = ScriptedBashRunner(results: [
      ProcessResult(exitCode: 0, stdout: "", stderr: ""),
      ProcessResult(exitCode: 1, stdout: "1 failed", stderr: "boom"),
    ])
    let result = await DeletionTester.probe(
      repoURL: root,
      candidates: [candidate],
      bashRunner: bash,
      timeout: 30
    )
    #expect(result.live.count == 1)
    #expect(result.proven.isEmpty)
  }

  @Test("probe splits and marks tangled when compile stays red")
  func tangledSplit() async {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "compass-deletion-tangled-\(UUID().uuidString)")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let src = root.appending(path: "src")
    try! fm.createDirectory(at: src, withIntermediateDirectories: true)
    try! "fn a() {}\nfn b() {}\nfn c() {}\n".write(
      to: src.appending(path: "lib.rs"), atomically: true, encoding: .utf8)

    let candidates = [
      DeadCodeCandidate(
        file: "src/lib.rs", startLine: 1, endLine: 1, lint: "dead_code", message: "a"),
      DeadCodeCandidate(
        file: "src/lib.rs", startLine: 2, endLine: 2, lint: "dead_code", message: "b"),
    ]
    // Every check fails with no expandable unused_imports → tangled after split.
    let bash = ScriptedBashRunner(results: Array(
      repeating: ProcessResult(
        exitCode: 1,
        stdout: #"{"reason":"compiler-message","message":{"code":{"code":"E0425"},"level":"error","message":"cannot find value `x`","spans":[]}}"#,
        stderr: ""
      ),
      count: 20
    ))
    let result = await DeletionTester.probe(
      repoURL: root,
      candidates: candidates,
      bashRunner: bash,
      timeout: 30
    )
    #expect(result.tangled.count == 2)
    #expect(result.proven.isEmpty)
  }
}

@Suite("HealthCleanupPrompt")
struct HealthCleanupPromptTests {
  @Test("cold files and proven cuts appear in cleanup prompt")
  func cleanupPromptSections() throws {
    let coverage = CoverageSnapshot(
      overallLineCoveragePercent: 40,
      files: [
        CoverageFileEntry(path: "crates/core/src/cold.rs", lineCoveragePercent: 0),
        CoverageFileEntry(path: "crates/core/src/hot.rs", lineCoveragePercent: 95),
        CoverageFileEntry(path: "crates/core/tests/it.rs", lineCoveragePercent: 0),
      ]
    )
    let recon = HealthReconResult(
      packageNames: ["core"],
      coverage: coverage,
      deadCodeCandidates: [
        DeadCodeCandidate(
          file: "crates/core/src/cold.rs",
          startLine: 10,
          endLine: 12,
          symbol: "unused_fn",
          lint: "dead_code",
          message: "function `unused_fn` is never used"
        )
      ]
    )
    let probe = DeletionProbeResult(
      items: [
        DeletionProbeItem(
          candidate: DeadCodeCandidate(
            file: "crates/core/src/cold.rs",
            startLine: 10,
            endLine: 12,
            symbol: "unused_fn",
            lint: "dead_code",
            message: "function `unused_fn` is never used"
          ),
          status: .proven
        ),
        DeletionProbeItem(
          candidate: DeadCodeCandidate(
            file: "crates/core/src/other.rs",
            startLine: 1,
            endLine: 8,
            symbol: "messy",
            lint: "dead_code",
            message: "function `messy` is never used"
          ),
          status: .tangled,
          detail: "error[E0425]: cannot find value `messy`"
        ),
      ]
    )
    let prompt = try Prompts.healthPrompt(
      recon: recon,
      focus: .cleanup,
      deletionProbe: probe,
      promptMode: .envelope
    )
    #expect(prompt.contains("Cold files"))
    #expect(prompt.contains("cold.rs"))
    #expect(prompt.contains("Proven cuts"))
    #expect(prompt.contains("deletion-tested"))
    #expect(prompt.contains("unused_fn"))
    #expect(prompt.contains("Tangled candidates"))
    #expect(prompt.contains("messy"))
    // Cold ranking prefers lowest coverage source files.
    if let coldRange = prompt.range(of: "Cold files"),
      let provenRange = prompt.range(of: "Proven cuts")
    {
      let coldSection = prompt[coldRange.lowerBound..<provenRange.lowerBound]
      #expect(coldSection.contains("cold.rs"))
      #expect(!coldSection.contains("tests/it.rs"))
    }
  }

  @Test("coldSourceFiles ranks lowest coverage and skips tests")
  func coldRanking() {
    let coverage = CoverageSnapshot(
      files: [
        CoverageFileEntry(path: "src/a.rs", lineCoveragePercent: 50),
        CoverageFileEntry(path: "src/b.rs", lineCoveragePercent: 10),
        CoverageFileEntry(path: "tests/t.rs", lineCoveragePercent: 0),
        CoverageFileEntry(path: "src/c.rs", lineCoveragePercent: 0),
      ]
    )
    let cold = HealthRecon.coldSourceFiles(from: coverage)
    #expect(cold.map(\.path) == ["src/c.rs", "src/b.rs", "src/a.rs"])
  }
}

private final class ScriptedBashRunner: AgentBashRunner, @unchecked Sendable {
  private var results: [ProcessResult]
  private var index = 0

  init(results: [ProcessResult]) {
    self.results = results
  }

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    if index >= results.count {
      return ProcessResult(exitCode: 1, stdout: "", stderr: "no scripted result for: \(command)")
    }
    let result = results[index]
    index += 1
    return result
  }
}
