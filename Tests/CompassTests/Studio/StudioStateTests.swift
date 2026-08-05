import Foundation
import Testing

@testable import CompassCore

@Suite("StudioState")
@MainActor
struct StudioStateTests {
  private func line(
    status: LiveLine.Status,
    correlationID: String? = nil,
    payload: LiveToolPayload
  ) -> LiveLine {
    LiveLine(
      level: .info,
      text: "tool",
      kind: .lifecycle,
      status: status,
      correlationID: correlationID,
      payload: payload
    )
  }

  @Test
  func normalizesWorkspacePaths() {
    let state = StudioState(workspacePrefix: "/workspace")
    #expect(state.normalizePath("/workspace/crates/core/src/lib.rs") == "crates/core/src/lib.rs")
    #expect(state.normalizePath("crates/core/src/lib.rs") == "crates/core/src/lib.rs")
    #expect(state.normalizePath("./src/main.rs") == "src/main.rs")
    #expect(state.normalizePath("/abs/path.rs") == "abs/path.rs")
  }

  @Test
  func parsesNumberedReadOutput() {
    let content = """
      Lines are 1-indexed. Use these numbers with edit_file startLine/endLine.
           1\tfn main() {
           2\t    println!("hi");
           3\t}
      (total 3 lines)
      """
    #expect(
      StudioState.parseNumberedReadOutput(content) == [
        "fn main() {",
        "    println!(\"hi\");",
        "}",
      ])
  }

  @Test
  func readFileOpensAndSeedsFromContent() {
    let state = StudioState()
    let content = "     1\talpha\n     2\tbeta\n(total 2 lines)\n"
    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "/workspace/src/lib.rs", offset: 1, limit: nil, content: content)))
    #expect(state.openFile == "src/lib.rs")
    #expect(state.lastTouchedPath == "src/lib.rs")
    #expect(state.buffers["src/lib.rs"]?.lines == ["alpha", "beta"])
    #expect(state.hasActivity)
  }

  @Test
  func writeFileOnCompletionSetsBufferAndHighlightsAll() {
    let state = StudioState()
    state.apply(
      line(
        status: .running,
        payload: .writeFile(path: "new.rs", content: "one\ntwo")))
    #expect(state.buffers["new.rs"] == nil)
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "new.rs", content: "one\ntwo")))
    let buffer = state.buffers["new.rs"]
    #expect(buffer?.lines == ["one", "two"])
    #expect(buffer?.highlightedLines == [1, 2])
    #expect(state.openFile == "new.rs")
  }

  @Test
  func failedWriteDoesNotMutateBuffer() {
    let state = StudioState()
    state.apply(
      line(
        status: .failed,
        payload: .writeFile(path: "new.rs", content: "one")))
    #expect(state.buffers["new.rs"] == nil)
  }

  @Test
  func lineRangeEditsReplaceInsertAndDelete() {
    let (replaced, replacedChanged) = StudioState.applyingLineRangeEdits(
      to: ["a", "b", "c"],
      edits: [LiveLineRangeEdit(startLine: 2, endLine: 2, replacementLines: ["B1", "B2"])]
    )
    #expect(replaced == ["a", "B1", "B2", "c"])
    #expect(replacedChanged == [2, 3])

    let (inserted, insertChanged) = StudioState.applyingLineRangeEdits(
      to: ["a", "b"],
      edits: [LiveLineRangeEdit(startLine: 2, endLine: 1, replacementLines: ["x"])])
    #expect(inserted == ["a", "x", "b"])
    #expect(insertChanged == [2])

    let (deleted, deleteChanged) = StudioState.applyingLineRangeEdits(
      to: ["a", "b", "c"],
      edits: [LiveLineRangeEdit(startLine: 2, endLine: 2, replacementLines: [])])
    #expect(deleted == ["a", "c"])
    #expect(deleteChanged.isEmpty)
  }

  @Test
  func lineRangeEditsApplySequentially() {
    let (lines, _) = StudioState.applyingLineRangeEdits(
      to: ["a", "b", "c"],
      edits: [
        LiveLineRangeEdit(startLine: 1, endLine: 1, replacementLines: ["z", "y"]),
        LiveLineRangeEdit(startLine: 4, endLine: 4, replacementLines: ["w"]),
      ]
    )
    #expect(lines == ["z", "y", "b", "w"])
  }

  @Test
  func outOfRangeLineEditsAreSkipped() {
    let (lines, changed) = StudioState.applyingLineRangeEdits(
      to: ["a"],
      edits: [LiveLineRangeEdit(startLine: 5, endLine: 6, replacementLines: ["x"])])
    #expect(lines == ["a"])
    #expect(changed.isEmpty)
  }

  @Test
  func stringReplaceEditsHighlightNewStringLocation() {
    let (lines, changed) = StudioState.applyingStringReplaceEdits(
      to: ["fn a() {}", "fn b() {", "  old();", "}"],
      edits: [LiveStringReplaceEdit(oldString: "old();", newString: "new();", replaceAll: false)]
    )
    #expect(lines == ["fn a() {}", "fn b() {", "  new();", "}"])
    #expect(changed == [3])
  }

  @Test
  func stringReplaceAllEditsEveryOccurrence() {
    let (lines, _) = StudioState.applyingStringReplaceEdits(
      to: ["foo", "bar", "foo"],
      edits: [LiveStringReplaceEdit(oldString: "foo", newString: "baz", replaceAll: true)]
    )
    #expect(lines == ["baz", "bar", "baz"])
  }

  @Test
  func stringReplaceEditSeedsBufferFromDiskWhenMissing() throws {
    let repo = FileManager.default.temporaryDirectory
      .appending(path: "studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    try "line1\nline2\n".write(
      to: repo.appending(path: "seed.rs"), atomically: true, encoding: .utf8)

    let state = StudioState(repoURL: repo)
    state.apply(
      line(
        status: .completed,
        payload: .editFileStringReplace(
          path: "seed.rs",
          edits: [
            LiveStringReplaceEdit(oldString: "line2", newString: "edited", replaceAll: false)
          ]
        )))
    #expect(state.buffers["seed.rs"]?.lines == ["line1", "edited", ""])
    #expect(state.buffers["seed.rs"]?.highlightedLines == [2])
  }

  @Test
  func bashEntriesStartRunningThenComplete() {
    let state = StudioState()
    state.apply(
      line(
        status: .running,
        correlationID: "c1",
        payload: .bash(command: "cargo test", cwd: nil, output: nil, isError: nil)))
    #expect(state.terminalEntries.count == 1)
    #expect(state.terminalEntries[0].output == nil)

    state.apply(
      line(
        status: .completed,
        correlationID: "c1",
        payload: .bash(command: "cargo test", cwd: nil, output: "ok", isError: false)))
    #expect(state.terminalEntries.count == 1)
    #expect(state.terminalEntries[0].output == "ok")
    #expect(state.terminalEntries[0].isError == false)
  }

  @Test
  func bashCompletionWithoutStartAppendsEntry() {
    let state = StudioState()
    state.apply(
      line(
        status: .completed,
        correlationID: "c9",
        payload: .bash(command: "ls", cwd: nil, output: "files", isError: false)))
    #expect(state.terminalEntries.count == 1)
    #expect(state.terminalEntries[0].output == "files")
  }

  @Test
  func terminalEntriesAreCapped() {
    let state = StudioState()
    for i in 0..<(StudioState.maxTerminalEntries + 25) {
      state.apply(
        line(
          status: .running,
          correlationID: "c\(i)",
          payload: .bash(command: "cmd \(i)", cwd: nil, output: nil, isError: nil)))
    }
    #expect(state.terminalEntries.count == StudioState.maxTerminalEntries)
    #expect(state.terminalEntries.last?.command == "cmd \(StudioState.maxTerminalEntries + 24)")
  }

  @Test
  func resetClearsEverything() {
    let state = StudioState()
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "x")))
    state.reset()
    #expect(state.openFile == nil)
    #expect(state.buffers.isEmpty)
    #expect(state.terminalEntries.isEmpty)
    #expect(state.knownFiles.isEmpty)
    #expect(!state.hasActivity)
  }

  @Test
  func readsAndWritesMarkKnownFiles() {
    let state = StudioState()
    #expect(state.knownFiles.isEmpty)
    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "/workspace/src/lib.rs", offset: 1, limit: nil, content: "     1\tx\n")))
    #expect(state.knownFiles["src/lib.rs"]?.wasEdited == false)

    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "new.rs", content: "one")))
    #expect(state.knownFiles["new.rs"]?.wasEdited == true)
    #expect(state.knownFiles.count == 2)

    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "/workspace/src/lib.rs", offset: 1, limit: nil, content: "     1\tx\n")))
    #expect(state.knownFiles["src/lib.rs"]?.touchCount == 2)
  }

  @Test
  func bashLsOutputMarksSeenFiles() throws {
    let repo = FileManager.default.temporaryDirectory
      .appending(path: "studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: repo.appending(path: "src"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    try "fn main() {}\n".write(
      to: repo.appending(path: "src/main.rs"), atomically: true, encoding: .utf8)
    try "pub fn u() {}\n".write(
      to: repo.appending(path: "src/util.rs"), atomically: true, encoding: .utf8)

    let state = StudioState(repoURL: repo)
    state.apply(
      line(
        status: .completed,
        payload: .bash(
          command: "ls src", cwd: "/workspace",
          output: "main.rs  util.rs", isError: false)))
    #expect(state.knownFiles["src/main.rs"] != nil)
    #expect(state.knownFiles["src/util.rs"] != nil)
    #expect(state.knownFiles["src"] == nil)
  }

  @Test
  func bashDiagnosticsResolveAgainstCwd() throws {
    let repo = FileManager.default.temporaryDirectory
      .appending(path: "studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: repo.appending(path: "crates/core"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    try "x\n".write(
      to: repo.appending(path: "crates/core/lib.rs"), atomically: true, encoding: .utf8)

    let state = StudioState(repoURL: repo)
    state.apply(
      line(
        status: .failed,
        payload: .bash(
          command: "cargo build", cwd: "/workspace/crates/core",
          output: "error[E0308]: mismatch\n  --> lib.rs:1:4", isError: true)))
    #expect(state.knownFiles["crates/core/lib.rs"] != nil)
  }

  @Test
  func bashOutputDoesNotInventMissingFiles() throws {
    let repo = FileManager.default.temporaryDirectory
      .appending(path: "studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }

    let state = StudioState(repoURL: repo)
    state.apply(
      line(
        status: .completed,
        payload: .bash(
          command: "ls", cwd: "/workspace",
          output: "ghost.rs  nothing.txt", isError: false)))
    #expect(state.knownFiles.isEmpty)
  }

  @Test
  func bashPathTokensStripNoise() {
    let tokens = StudioState.bashPathTokens(
      in: "cat \"src/main.rs\" -n KEY=value src/lib.rs:10:2 https://example.com *.swift 42")
    #expect(tokens.contains("cat"))
    #expect(tokens.contains("src/main.rs"))
    #expect(tokens.contains("src/lib.rs"))
    #expect(!tokens.contains("-n"))
    #expect(!tokens.contains("KEY=value"))
    #expect(!tokens.contains("*.swift"))
    #expect(!tokens.contains("42"))
  }

  @Test
  func lsTargetDirectoriesParseCompoundCommands() {
    #expect(StudioState.lsTargetDirectories(command: "ls") == [])
    #expect(StudioState.lsTargetDirectories(command: "ls -la src crates") == ["src", "crates"])
    #expect(StudioState.lsTargetDirectories(command: "cd src && ls ./core") == ["./core"])
    #expect(StudioState.lsTargetDirectories(command: "cargo test") == [])
  }

  @Test
  func heatRanksMostRecentlySeen() {
    var known: [String: StudioState.KnownFile] = [:]
    let base = Date(timeIntervalSince1970: 1_000)
    for (index, path) in ["a.rs", "b.rs", "c.rs"].enumerated() {
      known[path] = StudioState.KnownFile(
        lastSeenAt: base.addingTimeInterval(Double(index)), touchCount: 1)
    }
    let heat = StudioState.heatByPath(known, fadingRanks: 4)
    #expect(heat["c.rs"] == 1)
    #expect(heat["b.rs"] == 0.75)
    #expect(heat["a.rs"] == 0.5)
  }
}
