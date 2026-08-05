import Foundation

/// Read-only, in-memory mirror of an agent session rendered as an IDE:
/// which file is open, what its buffer contains, and the terminal transcript.
/// Fed by `LiveLine.payload` emitted from tool start/end events; the buffer
/// replays the agent's exact tool payloads rather than watching the disk.
///
/// `buffers` is the source of truth. `presentationBuffers` is what the editor
/// shows and may lag during typewriter playback of writes/edits.
@MainActor
public final class StudioState: ObservableObject {
  public static let maxTerminalEntries = 500
  public static let maxRecentPaths = 12
  /// Changes larger than this snap instantly instead of typing out.
  public static let typewriterMaxChars = 800
  public static let typewriterMaxLines = 40
  /// Characters revealed per typewriter tick.
  public static let typewriterCharsPerTick = 3
  /// Delay between typewriter ticks.
  public static let typewriterTickNanoseconds: UInt64 = 40_000_000
  /// Output lines / tokens scanned per bash event when mining seen paths.
  public static let maxBashPathScanLines = 120
  public static let maxBashPathCandidates = 400

  /// Two-phase editor camera move used when the agent `read_file`s a span:
  /// jump quickly to `startLine`, then ease to `endLine`.
  public struct ScrollTour: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var startLine: Int
    public var endLine: Int

    public init(id: UUID = UUID(), startLine: Int, endLine: Int) {
      self.id = id
      self.startLine = max(startLine, 1)
      self.endLine = max(endLine, self.startLine)
    }
  }

  public struct FileBuffer: Equatable {
    public var lines: [String]
    /// 1-indexed lines changed by the most recent write/edit.
    public var highlightedLines: Set<Int>
    public var lastChangeAt: Date
    /// 1-indexed line the editor should scroll to.
    public var scrollToLine: Int?
    /// Optional skim tour from a `read_file` (jump to start, ease to end).
    public var scrollTour: ScrollTour?

    public init(
      lines: [String],
      highlightedLines: Set<Int> = [],
      lastChangeAt: Date = Date(),
      scrollToLine: Int? = nil,
      scrollTour: ScrollTour? = nil
    ) {
      self.lines = lines
      self.highlightedLines = highlightedLines
      self.lastChangeAt = lastChangeAt
      self.scrollToLine = scrollToLine
      self.scrollTour = scrollTour
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

  public struct ThinkingEntry: Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var startedAt: Date

    public init(id: UUID = UUID(), text: String, startedAt: Date = Date()) {
      self.id = id
      self.text = text
      self.startedAt = startedAt
    }
  }

  /// A file the agent is aware of this session: read, written, edited, or
  /// seen in bash output (e.g. `ls`, compiler diagnostics, `git status`).
  public struct KnownFile: Equatable {
    public var lastSeenAt: Date
    public var touchCount: Int
    /// True once the agent has written or edited the file.
    public var wasEdited: Bool

    public init(lastSeenAt: Date = Date(), touchCount: Int = 0, wasEdited: Bool = false) {
      self.lastSeenAt = lastSeenAt
      self.touchCount = touchCount
      self.wasEdited = wasEdited
    }
  }

  @Published public private(set) var openFile: String?
  @Published public private(set) var buffers: [String: FileBuffer] = [:]
  /// Display buffers — may animate toward `buffers` during typewriter playback.
  @Published public private(set) var presentationBuffers: [String: FileBuffer] = [:]
  @Published public private(set) var terminalEntries: [TerminalEntry] = []
  @Published public private(set) var thinkingEntries: [ThinkingEntry] = []
  @Published public private(set) var lastTouchedPath: String?
  @Published public private(set) var treeRefreshToken = 0
  @Published public private(set) var hasActivity = false
  /// When true, agent file events retake the camera. Peeking sets this false
  /// until the next agent file touch (or `resumeFollowing()`).
  @Published public private(set) var followAgent = true
  /// Recently touched / opened paths for the buffer strip (most recent last).
  @Published public private(set) var recentPaths: [String] = []
  /// Files the agent is aware of this session, keyed by repo-relative path.
  /// The Studio file tree renders only this set — the agent's context, not
  /// the whole repo.
  @Published public private(set) var knownFiles: [String: KnownFile] = [:]
  @Published public private(set) var isTypewriting = false
  /// Which pane should dominate the vertical split (screensaver camera).
  @Published public private(set) var paneFocus: StudioPaneFocus = .balanced

  public enum StudioPaneFocus: String, Equatable, Sendable {
    /// Default ~60/40 editor/terminal.
    case balanced
    /// Read / write / edit in flight (or typewriter playback) — editor ~75%.
    case editor
    /// Bash in flight — terminal ~75%.
    case terminal
  }

  /// Repo root used to seed editor buffers from disk when an edit targets a
  /// file the agent never read/wrote in this session. May be nil in tests.
  public let repoURL: URL?
  /// Agent-visible workspace prefix (e.g. `/workspace`) stripped from tool
  /// paths to produce repo-relative display paths.
  public let workspacePrefix: String

  /// Injected for tests — advances the typewriter without sleeping.
  public var typewriterTickHandler: (@MainActor () async -> Void)?

  private var typewriterTask: Task<Void, Never>?
  private var typewriterGeneration = 0
  private var runningBashIDs: Set<String> = []
  private var runningEditorIDs: Set<String> = []
  /// Disk-validation caches for bash path extraction (repo-relative paths).
  private var validatedKnownPaths: Set<String> = []
  private var rejectedKnownPaths: Set<String> = []

  public init(repoURL: URL? = nil, workspacePrefix: String = "/workspace") {
    self.repoURL = repoURL
    self.workspacePrefix = workspacePrefix
  }

  public func reset() {
    cancelTypewriter(snapOpenFileToTruth: false)
    openFile = nil
    buffers = [:]
    presentationBuffers = [:]
    terminalEntries = []
    thinkingEntries = []
    lastTouchedPath = nil
    treeRefreshToken = 0
    hasActivity = false
    followAgent = true
    recentPaths = []
    knownFiles = [:]
    validatedKnownPaths = []
    rejectedKnownPaths = []
    isTypewriting = false
    paneFocus = .balanced
    runningBashIDs = []
    runningEditorIDs = []
  }

  // MARK: - Follow / peek

  public func resumeFollowing() {
    followAgent = true
    if let lastTouchedPath, buffers[lastTouchedPath] != nil {
      openFile = lastTouchedPath
      snapPresentation(for: lastTouchedPath)
    }
  }

  /// Open a path from the tree or recent strip without editing. Loads from an
  /// existing buffer or disk. Disables follow until the agent touches a file.
  public func peek(_ rawPath: String) {
    let path = normalizePath(rawPath)
    guard !path.isEmpty else { return }
    followAgent = false
    if buffers[path] == nil {
      let buffer = FileBuffer(lines: diskLines(for: path) ?? [])
      setTruthBuffer(buffer, for: path)
      setPresentationBuffer(buffer, for: path)
    } else {
      snapPresentation(for: path)
    }
    openFile = path
    bumpRecent(path)
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
    // Focus after content mutations so a bash-first Studio open paints entries
    // before the terminal pane zooms.
    defer {
      trackPaneFocus(payload: payload, status: line.status, correlationID: line.correlationID)
    }
    switch payload {
    case .readFile(let path, let offset, let limit, let content):
      hasActivity = true
      let display = normalizePath(path)
      guard !display.isEmpty else { return }
      agentFocus(display)
      markKnown(display, edited: false)
      _ = seedBufferIfMissing(for: display, content: content)
      snapPresentation(for: display)
      // Prefer completed reads (have content); still skim on running if the
      // buffer already has lines (e.g. seeded from disk on tool-start).
      let lineCount = buffers[display]?.lines.count ?? 0
      guard lineCount > 0 else { return }
      let range = Self.readScrollRange(
        offset: offset,
        limit: limit,
        content: content,
        lineCount: lineCount
      )
      setScrollTour(for: display, startLine: range.start, endLine: range.end)

    case .writeFile(let path, let content):
      hasActivity = true
      let display = normalizePath(path)
      guard !display.isEmpty, line.status == .completed else { return }
      agentFocus(display)
      markKnown(display, edited: true)
      let previous = presentationBuffers[display]?.lines ?? buffers[display]?.lines ?? []
      let lines = content.components(separatedBy: "\n")
      let buffer = FileBuffer(
        lines: lines,
        highlightedLines: Set(1...max(lines.count, 1)),
        scrollToLine: 1,
        scrollTour: nil
      )
      setTruthBuffer(buffer, for: display)
      treeRefreshToken += 1
      beginTypewriter(
        path: display,
        previousLines: previous,
        newBuffer: buffer
      )

    case .editFileLineRange(let path, let edits):
      hasActivity = true
      let display = normalizePath(path)
      guard !display.isEmpty else { return }
      // Snapshot pre-edit bytes on tool-start — invoke has already written the
      // file by the time the completed event arrives, so disk seeding then is
      // too late for typewriter "previous" content.
      if line.status == .running {
        _ = bufferOrDiskSeed(for: display)
        return
      }
      guard line.status == .completed else { return }
      agentFocus(display)
      markKnown(display, edited: true)
      cancelTypewriter(snapOpenFileToTruth: true)
      var buffer = bufferOrDiskSeed(for: display)
      let previous = buffer.lines
      let result = Self.applyingLineRangeEdits(to: buffer.lines, edits: edits)
      buffer.lines = result.lines
      buffer.highlightedLines = result.changed
      buffer.lastChangeAt = Date()
      // Clear any prior read skim so scrollToLine / typewriter caret can fire.
      buffer.scrollTour = nil
      buffer.scrollToLine = result.changed.min()
      setTruthBuffer(buffer, for: display)
      treeRefreshToken += 1
      beginTypewriter(
        path: display,
        previousLines: previous,
        newBuffer: buffer
      )

    case .editFileStringReplace(let path, let edits):
      hasActivity = true
      let display = normalizePath(path)
      guard !display.isEmpty else { return }
      if line.status == .running {
        _ = bufferOrDiskSeed(for: display)
        return
      }
      guard line.status == .completed else { return }
      agentFocus(display)
      markKnown(display, edited: true)
      cancelTypewriter(snapOpenFileToTruth: true)
      var buffer = bufferOrDiskSeed(for: display)
      let previous = buffer.lines
      let result = Self.applyingStringReplaceEdits(to: buffer.lines, edits: edits)
      buffer.lines = result.lines
      buffer.highlightedLines = result.changed
      buffer.lastChangeAt = Date()
      // Clear any prior read skim so scrollToLine / typewriter caret can fire.
      buffer.scrollTour = nil
      buffer.scrollToLine = result.changed.min()
      setTruthBuffer(buffer, for: display)
      treeRefreshToken += 1
      beginTypewriter(
        path: display,
        previousLines: previous,
        newBuffer: buffer
      )

    case .bash(let command, let cwd, let output, let isError):
      hasActivity = true
      switch line.status {
      case .running:
        var entries = terminalEntries
        entries.append(
          TerminalEntry(
            command: command,
            cwd: cwd,
            correlationID: line.correlationID
          ))
        if entries.count > Self.maxTerminalEntries {
          entries.removeFirst(entries.count - Self.maxTerminalEntries)
        }
        // Reassign so `@Published` always fires (in-place Array mutation can miss).
        terminalEntries = entries
      case .completed, .failed:
        var entries = terminalEntries
        if let correlationID = line.correlationID,
          let index = entries.lastIndex(where: {
            $0.correlationID == correlationID && $0.output == nil
          })
        {
          entries[index].output = output
          entries[index].isError = isError
        } else {
          entries.append(
            TerminalEntry(
              command: command,
              cwd: cwd,
              output: output,
              isError: isError,
              correlationID: line.correlationID
            ))
        }
        terminalEntries = entries
        noteBashSeenPaths(command: command, cwd: cwd, output: output)
      case .none:
        break
      }

    case .thinking(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      hasActivity = true
      var entries = thinkingEntries
      entries.append(ThinkingEntry(text: trimmed))
      if entries.count > Self.maxTerminalEntries {
        entries.removeFirst(entries.count - Self.maxTerminalEntries)
      }
      thinkingEntries = entries
    }
  }

  // MARK: - Typewriter

  /// Force presentation to match truth for `path` (or all paths).
  public func snapPresentation(for path: String? = nil) {
    if let path {
      if let truth = buffers[path] {
        setPresentationBuffer(truth, for: path)
      }
      return
    }
    presentationBuffers = buffers
  }

  private func beginTypewriter(
    path: String,
    previousLines: [String],
    newBuffer: FileBuffer
  ) {
    cancelTypewriter(snapOpenFileToTruth: false)

    let plan = Self.makeTypewriterPlan(
      previousLines: previousLines,
      newLines: newBuffer.lines,
      highlightedLines: newBuffer.highlightedLines
    )

    guard let plan, !plan.targetSpan.isEmpty else {
      setPresentationBuffer(newBuffer, for: path)
      isTypewriting = false
      recomputePaneFocus()
      return
    }

    if plan.targetSpan.count > Self.typewriterMaxChars
      || plan.lineCount > Self.typewriterMaxLines
    {
      setPresentationBuffer(newBuffer, for: path)
      isTypewriting = false
      recomputePaneFocus()
      return
    }

    typewriterGeneration += 1
    let generation = typewriterGeneration
    isTypewriting = true
    recomputePaneFocus()

    // Start with an empty span so characters appear to type in.
    setPresentationBuffer(
      FileBuffer(
        lines: plan.lines(revealedCount: 0),
        highlightedLines: newBuffer.highlightedLines,
        lastChangeAt: newBuffer.lastChangeAt,
        scrollToLine: newBuffer.scrollToLine
      ),
      for: path
    )

    typewriterTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var revealed = 0
      while revealed < plan.targetSpan.count {
        if Task.isCancelled || generation != self.typewriterGeneration { return }
        if let handler = self.typewriterTickHandler {
          await handler()
        } else {
          try? await Task.sleep(nanoseconds: Self.typewriterTickNanoseconds)
        }
        if Task.isCancelled || generation != self.typewriterGeneration { return }
        revealed = min(revealed + Self.typewriterCharsPerTick, plan.targetSpan.count)
        var presented = FileBuffer(
          lines: plan.lines(revealedCount: revealed),
          highlightedLines: newBuffer.highlightedLines,
          lastChangeAt: newBuffer.lastChangeAt,
          scrollToLine: newBuffer.scrollToLine
        )
        // Keep scroll anchored near the typing caret line.
        let caretLine =
          plan.startLine
          + max(
            0,
            String(plan.targetSpan.prefix(revealed))
              .filter { $0 == "\n" }.count)
        presented.scrollToLine = caretLine
        self.setPresentationBuffer(presented, for: path)
      }
      if generation == self.typewriterGeneration {
        self.setPresentationBuffer(newBuffer, for: path)
        self.isTypewriting = false
        self.typewriterTask = nil
        self.recomputePaneFocus()
      }
    }
  }

  /// Reassign the dictionary so `@Published` always notifies (subscript
  /// mutation of a Dictionary can miss `objectWillChange`).
  private func setPresentationBuffer(_ buffer: FileBuffer, for path: String) {
    var next = presentationBuffers
    next[path] = buffer
    presentationBuffers = next
  }

  private func setTruthBuffer(_ buffer: FileBuffer, for path: String) {
    var next = buffers
    next[path] = buffer
    buffers = next
  }

  private func cancelTypewriter(snapOpenFileToTruth: Bool) {
    typewriterGeneration += 1
    typewriterTask?.cancel()
    typewriterTask = nil
    isTypewriting = false
    if snapOpenFileToTruth, let openFile {
      snapPresentation(for: openFile)
    }
    recomputePaneFocus()
  }

  private func trackPaneFocus(
    payload: LiveToolPayload,
    status: LiveLine.Status,
    correlationID: String?
  ) {
    let id = correlationID ?? "anon-\(payloadFocusKey(payload))"
    switch payload {
    case .bash:
      switch status {
      case .running: runningBashIDs.insert(id)
      case .completed, .failed: runningBashIDs.remove(id)
      case .none: break
      }
    case .readFile, .writeFile, .editFileLineRange, .editFileStringReplace:
      switch status {
      case .running: runningEditorIDs.insert(id)
      case .completed, .failed: runningEditorIDs.remove(id)
      case .none: break
      }
    case .thinking:
      break
    }
    recomputePaneFocus()
  }

  private func payloadFocusKey(_ payload: LiveToolPayload) -> String {
    switch payload {
    case .bash(let command, _, _, _): return "bash:\(command)"
    case .readFile(let path, _, _, _): return "read:\(path)"
    case .writeFile(let path, _): return "write:\(path)"
    case .editFileLineRange(let path, _): return "edit:\(path)"
    case .editFileStringReplace(let path, _): return "edit:\(path)"
    case .thinking: return "thinking"
    }
  }

  private func recomputePaneFocus() {
    // Bash wins while running so the terminal camera takes over.
    if !runningBashIDs.isEmpty {
      paneFocus = .terminal
    } else if !runningEditorIDs.isEmpty || isTypewriting {
      paneFocus = .editor
    } else {
      paneFocus = .balanced
    }
  }

  public struct TypewriterPlan: Equatable, Sendable {
    public var prefixLines: [String]
    public var suffixLines: [String]
    public var targetSpan: String
    public var startLine: Int  // 1-indexed

    public var lineCount: Int {
      guard !targetSpan.isEmpty else { return 0 }
      return targetSpan.filter { $0 == "\n" }.count + 1
    }

    public func lines(revealedCount: Int) -> [String] {
      let revealed = String(targetSpan.prefix(revealedCount))
      let spanLines = revealed.isEmpty ? [""] : revealed.components(separatedBy: "\n")
      return prefixLines + spanLines + suffixLines
    }
  }

  /// Build a typewriter plan that animates only the changed line span.
  public static func makeTypewriterPlan(
    previousLines: [String],
    newLines: [String],
    highlightedLines: Set<Int>
  ) -> TypewriterPlan? {
    guard !highlightedLines.isEmpty else {
      // Full replace with no highlight metadata — animate whole file when small.
      let span = newLines.joined(separator: "\n")
      return TypewriterPlan(
        prefixLines: [],
        suffixLines: [],
        targetSpan: span,
        startLine: 1
      )
    }
    let start = highlightedLines.min() ?? 1
    let end = highlightedLines.max() ?? start
    let startIndex = max(start - 1, 0)
    let endIndex = min(end - 1, max(newLines.count - 1, 0))
    guard startIndex < newLines.count else { return nil }

    let prefix = Array(newLines.prefix(startIndex))
    let spanSlice: ArraySlice<String>
    if endIndex >= startIndex {
      spanSlice = newLines[startIndex...min(endIndex, newLines.count - 1)]
    } else {
      spanSlice = []
    }
    let suffixStart = min(endIndex + 1, newLines.count)
    let suffix = Array(newLines[suffixStart...])
    let span = spanSlice.joined(separator: "\n")

    // If the change is a pure deletion, nothing to type.
    if span.isEmpty && previousLines.count > newLines.count {
      return nil
    }

    return TypewriterPlan(
      prefixLines: prefix,
      suffixLines: suffix,
      targetSpan: span,
      startLine: start
    )
  }

  // MARK: - Buffers

  private func agentFocus(_ path: String) {
    followAgent = true
    openFile = path
    lastTouchedPath = path
    bumpRecent(path)
  }

  private func bumpRecent(_ path: String) {
    recentPaths.removeAll { $0 == path }
    recentPaths.append(path)
    if recentPaths.count > Self.maxRecentPaths {
      recentPaths.removeFirst(recentPaths.count - Self.maxRecentPaths)
    }
  }

  // MARK: - Known files (agent context)

  private func markKnown(_ path: String, edited: Bool) {
    var entry = knownFiles[path] ?? KnownFile()
    entry.lastSeenAt = Date()
    entry.touchCount += 1
    entry.wasEdited = entry.wasEdited || edited
    var next = knownFiles
    next[path] = entry
    knownFiles = next
  }

  /// Mine a completed bash command (and its output) for repo-relative file
  /// paths so the tree reflects what the agent has seen — `ls` listings,
  /// compiler diagnostics, `git status`, `find` results, and direct path
  /// arguments like `cat src/main.rs`.
  private func noteBashSeenPaths(command: String, cwd: String?, output: String?) {
    guard repoURL != nil else { return }
    let baseDir = normalizePath(cwd ?? "")
    var bases: [String] = [baseDir]
    for dir in Self.lsTargetDirectories(command: command) {
      let resolved: String
      if dir == "." || dir == "./" {
        resolved = baseDir
      } else if dir.hasPrefix("/") {
        resolved = normalizePath(dir)
      } else {
        let normalized = normalizePath(dir)
        resolved = baseDir.isEmpty ? normalized : "\(baseDir)/\(normalized)"
      }
      if !bases.contains(resolved) { bases.append(resolved) }
    }
    if !bases.contains("") { bases.append("") }

    var tokens = Self.bashPathTokens(in: command)
    if let output {
      for outputLine in output.components(separatedBy: "\n").prefix(Self.maxBashPathScanLines) {
        tokens.append(contentsOf: Self.bashPathTokens(in: outputLine))
      }
    }

    var scanned = 0
    for token in tokens {
      guard scanned < Self.maxBashPathCandidates else { return }
      scanned += 1
      if token.hasPrefix("/") {
        let normalized = normalizePath(token)
        if isRepoFile(normalized) { markKnown(normalized, edited: false) }
        continue
      }
      for base in bases {
        let normalized = normalizePath(token)
        guard !normalized.isEmpty else { break }
        let candidate = base.isEmpty ? normalized : "\(base)/\(normalized)"
        if isRepoFile(candidate) {
          markKnown(candidate, edited: false)
          break
        }
      }
    }
  }

  /// Whether `path` (repo-relative) is an existing regular file, cached so
  /// noisy bash output cannot repeat disk stats.
  private func isRepoFile(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix(".compass"), !path.contains("..") else { return false }
    if validatedKnownPaths.contains(path) { return true }
    if rejectedKnownPaths.contains(path) { return false }
    guard let repoURL else { return false }
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: repoURL.appending(path: path).path, isDirectory: &isDirectory)
    let isFile = exists && !isDirectory.boolValue
    if isFile {
      validatedKnownPaths.insert(path)
    } else {
      rejectedKnownPaths.insert(path)
    }
    return isFile
  }

  private func seedBufferIfMissing(for path: String, content: String?) -> Bool {
    guard buffers[path] == nil else { return false }
    if let content {
      let parsed = Self.parseNumberedReadOutput(content)
      if !parsed.isEmpty {
        let buffer = FileBuffer(lines: parsed)
        setTruthBuffer(buffer, for: path)
        setPresentationBuffer(buffer, for: path)
        return true
      }
    }
    let buffer = FileBuffer(lines: diskLines(for: path) ?? [])
    setTruthBuffer(buffer, for: path)
    setPresentationBuffer(buffer, for: path)
    return true
  }

  private func bufferOrDiskSeed(for path: String) -> FileBuffer {
    if let existing = buffers[path] { return existing }
    let buffer = FileBuffer(lines: diskLines(for: path) ?? [])
    setTruthBuffer(buffer, for: path)
    setPresentationBuffer(buffer, for: path)
    return buffer
  }

  private func diskLines(for path: String) -> [String]? {
    guard let repoURL else { return nil }
    let url = repoURL.appending(path: path)
    guard let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .utf8)
    else { return nil }
    return text.components(separatedBy: "\n")
  }

  private func setScrollTour(for path: String, startLine: Int, endLine: Int) {
    guard var buffer = buffers[path] else { return }
    let lineCount = max(buffer.lines.count, 1)
    let start = max(min(startLine, lineCount), 1)
    let end = max(min(endLine, lineCount), start)
    let tour = ScrollTour(startLine: start, endLine: end)
    buffer.scrollToLine = start
    buffer.scrollTour = tour
    setTruthBuffer(buffer, for: path)
    if var presented = presentationBuffers[path] {
      presented.scrollToLine = start
      presented.scrollTour = tour
      setPresentationBuffer(presented, for: path)
    }
  }

  /// Resolve the camera range for a `read_file` payload.
  public static func readScrollRange(
    offset: Int?,
    limit: Int?,
    content: String?,
    lineCount: Int
  ) -> (start: Int, end: Int) {
    let cappedCount = max(lineCount, 1)
    let startFromContent = content.flatMap { firstNumberedLine(in: $0) }
    let endFromContent = content.flatMap { lastNumberedLine(in: $0) }
    let start = max(min(startFromContent ?? offset ?? 1, cappedCount), 1)
    let end: Int
    if let endFromContent {
      end = max(min(endFromContent, cappedCount), start)
    } else if let limit {
      end = max(min(start + max(limit, 1) - 1, cappedCount), start)
    } else {
      end = cappedCount
    }
    return (start, end)
  }

  public static func firstNumberedLine(in content: String) -> Int? {
    for line in content.components(separatedBy: "\n") {
      if let n = numberedLinePrefix(line) { return n }
    }
    return nil
  }

  public static func lastNumberedLine(in content: String) -> Int? {
    var last: Int?
    for line in content.components(separatedBy: "\n") {
      if let n = numberedLinePrefix(line) { last = n }
    }
    return last
  }

  private static func numberedLinePrefix(_ line: String) -> Int? {
    guard let tabIndex = line.firstIndex(of: "\t") else { return nil }
    let prefix = line[line.startIndex..<tabIndex]
    guard !prefix.isEmpty, prefix.allSatisfy({ $0 == " " || $0.isNumber }),
      prefix.contains(where: \.isNumber)
    else { return nil }
    return Int(prefix.trimmingCharacters(in: .whitespaces))
  }

  // MARK: - Pure transforms (testable)

  /// Recency-ranked heat per path: most recently seen file is 1.0, fading to
  /// 0 over `fadingRanks` ranks. Drives the file-tree heat tint.
  public static func heatByPath(
    _ knownFiles: [String: KnownFile],
    fadingRanks: Int = 5
  ) -> [String: Double] {
    let ranked = knownFiles.sorted { $0.value.lastSeenAt > $1.value.lastSeenAt }
    var heat: [String: Double] = [:]
    for (index, element) in ranked.enumerated() {
      heat[element.key] = max(0, 1 - Double(index) / Double(max(fadingRanks, 1)))
    }
    return heat
  }

  /// Candidate path tokens from a bash command or output chunk: whitespace
  /// separated, quote/paren stripped, diagnostic line:col suffixes removed.
  /// Flags, assignments, globs, URLs, and hidden files are excluded.
  public static func bashPathTokens(in text: String) -> [String] {
    text.components(separatedBy: .whitespacesAndNewlines).compactMap { raw in
      var token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>"))
      token = token.replacingOccurrences(
        of: #"(:\d+)+[:,]?"#, with: "", options: .regularExpression)
      while let last = token.last, ",;:".contains(last) { token.removeLast() }
      guard !token.isEmpty,
        !token.hasPrefix("-"),
        !token.hasPrefix("."),
        !token.contains("="),
        !token.contains("*"), !token.contains("?"),
        !token.contains("://"),
        !token.contains("$"), !token.contains("~"),
        Int(token) == nil
      else { return nil }
      return token
    }
  }

  /// Directories an `ls` invocation listed (handles `cd x && ls y` segments).
  public static func lsTargetDirectories(command: String) -> [String] {
    var dirs: [String] = []
    for segment in command.components(separatedBy: CharacterSet(charactersIn: ";|&")) {
      let tokens = segment.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
      guard let first = tokens.first, first == "ls" || first.hasSuffix("/ls") else { continue }
      dirs.append(
        contentsOf: tokens.dropFirst().filter { !$0.hasPrefix("-") }.map {
          $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        })
    }
    return dirs
  }

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
