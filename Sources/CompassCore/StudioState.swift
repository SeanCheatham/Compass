import Foundation

/// Read-only, in-memory mirror of an agent session rendered as an IDE:
/// which file is open, what its buffer contains, and the terminal transcript.
/// Fed by `LiveLine.payload` emitted from tool start/end events; the buffer
/// replays the agent's exact tool payloads rather than watching the disk.
@MainActor
public final class StudioState: ObservableObject {
  public static let maxTerminalEntries = 500

  public struct FileBuffer: Equatable {
    public var lines: [String]
    /// 1-indexed lines changed by the most recent write/edit.
    public var highlightedLines: Set<Int>
    public var lastChangeAt: Date
    /// 1-indexed line the editor should scroll to.
    public var scrollToLine: Int?

    public init(
      lines: [String],
      highlightedLines: Set<Int> = [],
      lastChangeAt: Date = Date(),
      scrollToLine: Int? = nil
    ) {
      self.lines = lines
      self.highlightedLines = highlightedLines
      self.lastChangeAt = lastChangeAt
      self.scrollToLine = scrollToLine
    }
  }

  public struct TerminalEntry: Identifiable, Equatable {
    public let id: UUID
    public var command: String
    public var cwd: String?
    public var output: String?
    public var isError: Bool?
    public var correlationID: String?
    public var startedAt: Date

    public init(
      id: UUID = UUID(),
      command: String,
      cwd: String? = nil,
      output: String? = nil,
      isError: Bool? = nil,
      correlationID: String? = nil,
      startedAt: Date = Date()
    ) {
      self.id = id
      self.command = command
      self.cwd = cwd
      self.output = output
      self.isError = isError
      self.correlationID = correlationID
      self.startedAt = startedAt
    }
  }

  @Published public private(set) var openFile: String?
  @Published public private(set) var buffers: [String: FileBuffer] = [:]
  @Published public private(set) var terminalEntries: [TerminalEntry] = []
  @Published public private(set) var lastTouchedPath: String?
  @Published public private(set) var treeRefreshToken = 0
  @Published public private(set) var hasActivity = false

  /// Repo root used to seed editor buffers from disk when an edit targets a
  /// file the agent never read/wrote in this session. May be nil in tests.
  public let repoURL: URL?
  /// Agent-visible workspace prefix (e.g. `/workspace`) stripped from tool
  /// paths to produce repo-relative display paths.
  public let workspacePrefix: String

  public init(repoURL: URL? = nil, workspacePrefix: String = "/workspace") {
    self.repoURL = repoURL
    self.workspacePrefix = workspacePrefix
  }

  public func reset() {
    openFile = nil
    buffers = [:]
    terminalEntries = []
    lastTouchedPath = nil
    treeRefreshToken = 0
    hasActivity = false
  }

  // MARK: - Path normalization

  public func normalizePath(_ raw: String) -> String {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = workspacePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if !prefix.isEmpty, path.hasPrefix("/\(prefix)/") {
      path.removeFirst(prefix.count + 2)
    } else if path == "/\(prefix)" {
      path = ""
    }
    while path.hasPrefix("/") { path.removeFirst() }
    while path.hasPrefix("./") { path.removeFirst(2) }
    return path
  }

  // MARK: - Reducer

  public func apply(_ line: LiveLine) {
    guard let payload = line.payload else { return }
    hasActivity = true
    switch payload {
    case .readFile(let path, let offset, _, let content):
      let display = normalizePath(path)
      guard !display.isEmpty else { return }
      openFile = display
      lastTouchedPath = display
      let seeded = seedBufferIfMissing(for: display, content: content)
      setScroll(for: display, line: seeded ? 1 : max(offset ?? 1, 1))

    case .writeFile(let path, let content):
      let display = normalizePath(path)
      guard !display.isEmpty, line.status == .completed else { return }
      openFile = display
      lastTouchedPath = display
      let lines = content.components(separatedBy: "\n")
      buffers[display] = FileBuffer(
        lines: lines,
        highlightedLines: Set(1...max(lines.count, 1)),
        scrollToLine: 1
      )
      treeRefreshToken += 1

    case .editFileLineRange(let path, let edits):
      let display = normalizePath(path)
      guard !display.isEmpty, line.status == .completed else { return }
      openFile = display
      lastTouchedPath = display
      var buffer = bufferOrDiskSeed(for: display)
      let result = Self.applyingLineRangeEdits(to: buffer.lines, edits: edits)
      buffer.lines = result.lines
      buffer.highlightedLines = result.changed
      buffer.lastChangeAt = Date()
      buffer.scrollToLine = result.changed.min()
      buffers[display] = buffer
      treeRefreshToken += 1

    case .editFileStringReplace(let path, let edits):
      let display = normalizePath(path)
      guard !display.isEmpty, line.status == .completed else { return }
      openFile = display
      lastTouchedPath = display
      var buffer = bufferOrDiskSeed(for: display)
      let result = Self.applyingStringReplaceEdits(to: buffer.lines, edits: edits)
      buffer.lines = result.lines
      buffer.highlightedLines = result.changed
      buffer.lastChangeAt = Date()
      buffer.scrollToLine = result.changed.min()
      buffers[display] = buffer

    case .bash(let command, let cwd, let output, let isError):
      switch line.status {
      case .running:
        terminalEntries.append(
          TerminalEntry(
            command: command,
            cwd: cwd,
            correlationID: line.correlationID
          ))
        if terminalEntries.count > Self.maxTerminalEntries {
          terminalEntries.removeFirst(terminalEntries.count - Self.maxTerminalEntries)
        }
      case .completed, .failed:
        if let correlationID = line.correlationID,
          let index = terminalEntries.lastIndex(where: {
            $0.correlationID == correlationID && $0.output == nil
          })
        {
          terminalEntries[index].output = output
          terminalEntries[index].isError = isError
        } else {
          terminalEntries.append(
            TerminalEntry(
              command: command,
              cwd: cwd,
              output: output,
              isError: isError,
              correlationID: line.correlationID
            ))
        }
      case .none:
        break
      }
    }
  }

  // MARK: - Buffers

  private func seedBufferIfMissing(for path: String, content: String?) -> Bool {
    guard buffers[path] == nil else { return false }
    if let content {
      let parsed = Self.parseNumberedReadOutput(content)
      if !parsed.isEmpty {
        buffers[path] = FileBuffer(lines: parsed)
        return true
      }
    }
    buffers[path] = FileBuffer(lines: diskLines(for: path) ?? [])
    return true
  }

  private func bufferOrDiskSeed(for path: String) -> FileBuffer {
    buffers[path] ?? FileBuffer(lines: diskLines(for: path) ?? [])
  }

  private func diskLines(for path: String) -> [String]? {
    guard let repoURL else { return nil }
    let url = repoURL.appending(path: path)
    guard let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .utf8)
    else { return nil }
    return text.components(separatedBy: "\n")
  }

  private func setScroll(for path: String, line: Int) {
    guard var buffer = buffers[path] else { return }
    buffer.scrollToLine = max(min(line, max(buffer.lines.count, 1)), 1)
    buffers[path] = buffer
  }

  // MARK: - Pure transforms (testable)

  /// Parse `read_file` tool output (`%6d\tline` rows plus header/footer)
  /// back into raw source lines.
  public static func parseNumberedReadOutput(_ content: String) -> [String] {
    content.components(separatedBy: "\n").compactMap { line in
      guard let tabIndex = line.firstIndex(of: "\t") else { return nil }
      let prefix = line[line.startIndex..<tabIndex]
      guard !prefix.isEmpty, prefix.allSatisfy({ $0 == " " || $0.isNumber }),
        prefix.contains(where: \.isNumber)
      else { return nil }
      return String(line[line.index(after: tabIndex)...])
    }
  }

  /// Apply line-range edits the same way `AgentEditFileTool` does: edits in
  /// order, insertion when `endLine == startLine - 1`, otherwise replace the
  /// inclusive 1-indexed range. Out-of-range edits are clamped/skipped —
  /// this is a display replay, not an enforcement point.
  public static func applyingLineRangeEdits(
    to lines: [String],
    edits: [LiveLineRangeEdit]
  ) -> (lines: [String], changed: Set<Int>) {
    var current = lines
    var changed: Set<Int> = []
    for edit in edits {
      guard edit.startLine >= 1 else { continue }
      if edit.endLine == edit.startLine - 1 {
        guard edit.startLine <= current.count + 1 else { continue }
        current.insert(contentsOf: edit.replacementLines, at: edit.startLine - 1)
        if !edit.replacementLines.isEmpty {
          changed.formUnion(edit.startLine...(edit.startLine + edit.replacementLines.count - 1))
        }
        continue
      }
      guard edit.startLine <= current.count, edit.endLine <= current.count,
        edit.endLine >= edit.startLine
      else { continue }
      let startIndex = edit.startLine - 1
      let endIndex = edit.endLine - 1
      current.replaceSubrange(startIndex...endIndex, with: edit.replacementLines)
      if !edit.replacementLines.isEmpty {
        changed.formUnion(edit.startLine...(edit.startLine + edit.replacementLines.count - 1))
      }
    }
    return (current, changed)
  }

  /// Apply string-replacement edits the same way `AgentEditFileTextTool`
  /// does: exact match, single occurrence unless `replaceAll`, in order.
  /// Edits whose `oldString` does not match are skipped.
  public static func applyingStringReplaceEdits(
    to lines: [String],
    edits: [LiveStringReplaceEdit]
  ) -> (lines: [String], changed: Set<Int>) {
    var text = lines.joined(separator: "\n")
    var changed: Set<Int> = []
    for edit in edits where !edit.oldString.isEmpty {
      if edit.replaceAll {
        guard text.contains(edit.oldString) else { continue }
        text = text.replacingOccurrences(of: edit.oldString, with: edit.newString)
        changed.formUnion(highlightedLines(forNewString: edit.newString, in: text))
      } else if let range = text.range(of: edit.oldString) {
        let insertionOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: edit.newString)
        let insertionIndex = text.index(text.startIndex, offsetBy: insertionOffset)
        changed.formUnion(
          highlightedLines(forNewString: edit.newString, in: text, from: insertionIndex))
      }
    }
    return (text.components(separatedBy: "\n"), changed)
  }

  private static func highlightedLines(
    forNewString newString: String,
    in text: String,
    from startIndex: String.Index? = nil
  ) -> Set<Int> {
    guard
      let range = text.range(of: newString, range: (startIndex ?? text.startIndex)..<text.endIndex)
    else { return [] }
    let lineOfStart = text[..<range.lowerBound].filter { $0 == "\n" }.count + 1
    let newLineCount = newString.filter { $0 == "\n" }.count + 1
    return Set(lineOfStart...(lineOfStart + newLineCount - 1))
  }
}
