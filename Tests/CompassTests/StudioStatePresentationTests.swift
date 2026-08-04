import Foundation
import Testing

@testable import CompassCore

@Suite("StudioState typewriter and follow")
@MainActor
struct StudioStatePresentationTests {
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
  func readFileDoesNotAnimate() {
    let state = StudioState()
    state.typewriterTickHandler = {}
    let content = "     1\talpha\n     2\tbeta\n(total 2 lines)\n"
    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "/workspace/src/lib.rs", offset: 1, limit: nil, content: content)))
    #expect(!state.isTypewriting)
    #expect(state.presentationBuffers["src/lib.rs"]?.lines == ["alpha", "beta"])
    #expect(state.buffers["src/lib.rs"]?.lines == ["alpha", "beta"])
  }

  @Test
  func editTypewriterReplaysFromPreEditSnapshot() async {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("studio-typewriter-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let fileURL = dir.appendingPathComponent("a.rs")
    try! "hello world\n".write(to: fileURL, atomically: true, encoding: .utf8)

    let state = StudioState(repoURL: dir)
    var seenLengths: [Int] = []
    state.typewriterTickHandler = {
      if let lines = state.presentationBuffers["a.rs"]?.lines {
        seenLengths.append(lines.joined(separator: "\n").count)
      }
    }

    // Tool-start must capture pre-edit disk content.
    state.apply(
      line(
        status: .running,
        correlationID: "e1",
        payload: .editFileStringReplace(
          path: "a.rs",
          edits: [
            LiveStringReplaceEdit(oldString: "world", newString: "there", replaceAll: false)
          ]
        )))
    #expect(state.buffers["a.rs"]?.lines == ["hello world", ""])

    // Simulate the tool writing disk before completion is logged.
    try! "hello there\n".write(to: fileURL, atomically: true, encoding: .utf8)

    state.apply(
      line(
        status: .completed,
        correlationID: "e1",
        payload: .editFileStringReplace(
          path: "a.rs",
          edits: [
            LiveStringReplaceEdit(oldString: "world", newString: "there", replaceAll: false)
          ]
        )))
    #expect(state.isTypewriting)
    #expect(state.buffers["a.rs"]?.lines == ["hello there", ""])

    for _ in 0..<80 {
      if !state.isTypewriting { break }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(!state.isTypewriting)
    #expect(state.presentationBuffers["a.rs"]?.lines == ["hello there", ""])
    // Intermediate ticks should have published growing content, not just the final snap.
    #expect(seenLengths.contains { $0 < "hello there\n".count })
  }

  @Test
  func writeFileTypewriterCatchesUpToTruth() async {
    let state = StudioState()
    var ticks = 0
    state.typewriterTickHandler = {
      ticks += 1
    }
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "new.rs", content: "ab")))
    #expect(state.buffers["new.rs"]?.lines == ["ab"])
    // Wait for typewriter task to finish (2 chars / 3 per tick => 1 tick).
    for _ in 0..<40 {
      if !state.isTypewriting { break }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(!state.isTypewriting)
    #expect(state.presentationBuffers["new.rs"]?.lines == ["ab"])
    #expect(ticks >= 1)
  }

  @Test
  func hugeWriteSnapsWithoutTypewriting() {
    let state = StudioState()
    let big = String(repeating: "x", count: StudioState.typewriterMaxChars + 50)
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "big.rs", content: big)))
    #expect(!state.isTypewriting)
    #expect(state.presentationBuffers["big.rs"]?.lines == [big])
  }

  @Test
  func overlappingEditCancelsPriorAnimation() async {
    let state = StudioState()
    state.typewriterTickHandler = {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "one")))
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "two")))
    for _ in 0..<50 {
      if !state.isTypewriting { break }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(state.buffers["a.rs"]?.lines == ["two"])
    #expect(state.presentationBuffers["a.rs"]?.lines == ["two"])
  }

  @Test
  func peekDisablesFollowUntilAgentTouch() {
    let state = StudioState()
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "a")))
    // Snap immediately for peek test.
    state.snapPresentation(for: "a.rs")
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "b.rs", content: "b")))
    state.snapPresentation(for: "b.rs")

    state.peek("a.rs")
    #expect(!state.followAgent)
    #expect(state.openFile == "a.rs")

    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "b.rs", offset: 1, limit: nil, content: "     1\tb\n")))
    #expect(state.followAgent)
    #expect(state.openFile == "b.rs")
  }

  @Test
  func stringReplaceBumpsTreeRefreshToken() {
    let state = StudioState()
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "old")))
    let token = state.treeRefreshToken
    state.snapPresentation(for: "a.rs")
    state.apply(
      line(
        status: .completed,
        payload: .editFileStringReplace(
          path: "a.rs",
          edits: [
            LiveStringReplaceEdit(oldString: "old", newString: "new", replaceAll: false)
          ]
        )))
    #expect(state.treeRefreshToken == token + 1)
  }

  @Test
  func typewriterPlanAnimatesChangedSpanOnly() {
    let plan = StudioState.makeTypewriterPlan(
      previousLines: ["a", "b", "c"],
      newLines: ["a", "B1", "B2", "c"],
      highlightedLines: [2, 3]
    )
    #expect(plan?.prefixLines == ["a"])
    #expect(plan?.suffixLines == ["c"])
    #expect(plan?.targetSpan == "B1\nB2")
    #expect(plan?.lines(revealedCount: plan?.targetSpan.count ?? 0) == ["a", "B1", "B2", "c"])
  }

  @Test
  func recentPathsTrackAgentFocus() {
    let state = StudioState()
    state.apply(
      line(status: .completed, payload: .writeFile(path: "a.rs", content: "a")))
    state.apply(
      line(status: .completed, payload: .writeFile(path: "b.rs", content: "b")))
    #expect(state.recentPaths == ["a.rs", "b.rs"])
  }

  @Test
  func readFileSetsScrollTourFromOffsetAndLimit() {
    let state = StudioState()
    let lines = (1...100).map { "line\($0)" }.joined(separator: "\n")
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "big.rs", content: lines)))
    state.snapPresentation(for: "big.rs")

    let numbered = (40...55).map { String(format: "%6d\tline%d", $0, $0) }.joined(separator: "\n")
    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "big.rs", offset: 40, limit: 16, content: numbered)))
    let tour = state.presentationBuffers["big.rs"]?.scrollTour
    #expect(tour?.startLine == 40)
    #expect(tour?.endLine == 55)
    #expect(state.presentationBuffers["big.rs"]?.scrollToLine == 40)
  }

  @Test
  func readScrollRangePrefersNumberedContent() {
    let content = """
           10\ta
           11\tb
           12\tc
      """
    let range = StudioState.readScrollRange(
      offset: 1, limit: 100, content: content, lineCount: 50)
    #expect(range.start == 10)
    #expect(range.end == 12)
  }

  @Test
  func readScrollRangeFallsBackToOffsetLimit() {
    let range = StudioState.readScrollRange(
      offset: 20, limit: 10, content: nil, lineCount: 100)
    #expect(range.start == 20)
    #expect(range.end == 29)
  }

  @Test
  func readScrollRangeSkimsToEofWithoutLimit() {
    let range = StudioState.readScrollRange(
      offset: nil, limit: nil, content: nil, lineCount: 80)
    #expect(range.start == 1)
    #expect(range.end == 80)
  }

  @Test
  func editClearsPriorReadScrollTour() {
    let state = StudioState()
    state.apply(
      line(
        status: .completed,
        payload: .writeFile(path: "a.rs", content: "old\nline2\nline3")))
    state.snapPresentation(for: "a.rs")
    state.apply(
      line(
        status: .completed,
        payload: .readFile(
          path: "a.rs", offset: 1, limit: 2, content: "     1\told\n     2\tline2\n")))
    #expect(state.buffers["a.rs"]?.scrollTour != nil)

    state.apply(
      line(
        status: .completed,
        payload: .editFileStringReplace(
          path: "a.rs",
          edits: [
            LiveStringReplaceEdit(oldString: "old", newString: "new", replaceAll: false)
          ]
        )))
    #expect(state.buffers["a.rs"]?.scrollTour == nil)
    #expect(state.buffers["a.rs"]?.scrollToLine == 1)
    #expect(state.presentationBuffers["a.rs"]?.scrollTour == nil)
  }

  @Test
  func paneFocusTracksBashVersusEditorTools() {
    let state = StudioState()
    #expect(state.paneFocus == .balanced)

    state.apply(
      line(
        status: .running,
        correlationID: "r1",
        payload: .readFile(path: "a.rs", offset: 1, limit: nil, content: nil)))
    #expect(state.paneFocus == .editor)

    state.apply(
      line(
        status: .running,
        correlationID: "b1",
        payload: .bash(command: "ls", cwd: nil, output: nil, isError: nil)))
    #expect(state.paneFocus == .terminal)

    state.apply(
      line(
        status: .completed,
        correlationID: "b1",
        payload: .bash(command: "ls", cwd: nil, output: "ok", isError: false)))
    #expect(state.paneFocus == .editor)

    state.apply(
      line(
        status: .completed,
        correlationID: "r1",
        payload: .readFile(
          path: "a.rs", offset: 1, limit: nil, content: "     1\tx\n")))
    #expect(state.paneFocus == .balanced)
  }
}
