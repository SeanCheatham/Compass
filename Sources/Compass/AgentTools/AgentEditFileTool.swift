import Foundation

/// Line-range edits on an existing UTF-8 text file. The model passes an
/// ordered list of operations; each replaces the inclusive 1-indexed line
/// range `[startLine, endLine]` with `replacementLines` (or inserts when
/// `endLine == startLine - 1`). All edits succeed atomically — if any one
/// fails, the file is not written. A prior `read_file` for the path is
/// required so line numbers come from content the model has actually seen.
struct AgentEditFileTool: AgentTool {
  static let toolName = "edit_file"

  struct Arguments: Decodable {
    let path: String
    let edits: [EditOperation]

    enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case edits
      case changes
      case operations
      case startLine
      case startLineSnake = "start_line"
      case start
      case endLine
      case endLineSnake = "end_line"
      case end
      case replacementLines
      case replacementLinesSnake = "replacement_lines"
      case lines
      case newString
      case newStringSnake = "new_string"
      case replacement
      case replace
      case content
      case insert
      case insertSnake = "_insert"
      case insertText
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      edits = try Self.decodeEdits(from: container, decoder: decoder)
    }

    private static func decodeEdits(
      from container: KeyedDecodingContainer<CodingKeys>,
      decoder: Decoder
    ) throws -> [EditOperation] {
      var sawPresentKey = false
      var firstTypeError: Error?

      for key in [CodingKeys.edits, .changes, .operations] where container.contains(key) {
        sawPresentKey = true
        do {
          if let edits = try? container.decodeIfPresent([EditOperation].self, forKey: key) {
            return edits
          }
          if let edit = try? container.decodeIfPresent(EditOperation.self, forKey: key) {
            return [edit]
          }
          _ = try container.decode([EditOperation].self, forKey: key)
        } catch {
          firstTypeError = firstTypeError ?? error
        }
      }

      if containsTopLevelEditOperation(in: container) {
        return [try EditOperation(from: decoder)]
      }

      if !sawPresentKey {
        throw DecodingError.keyNotFound(
          CodingKeys.edits,
          .init(
            codingPath: container.codingPath,
            debugDescription: "Missing required edits field."
          )
        )
      }
      if let firstTypeError {
        throw firstTypeError
      }
      throw DecodingError.valueNotFound(
        [EditOperation].self,
        .init(
          codingPath: container.codingPath + [CodingKeys.edits],
          debugDescription: "Expected non-null edits."
        )
      )
    }

    private static func containsTopLevelEditOperation(
      in container: KeyedDecodingContainer<CodingKeys>
    ) -> Bool {
      [
        CodingKeys.startLine,
        .startLineSnake,
        .start,
        .endLine,
        .endLineSnake,
        .end,
        .replacementLines,
        .replacementLinesSnake,
        .lines,
        .newString,
        .newStringSnake,
        .replacement,
        .replace,
        .content,
        .insert,
        .insertSnake,
        .insertText,
      ].contains { container.contains($0) }
    }
  }

  struct EditOperation: Decodable {
    let startLine: Int
    let endLine: Int
    let replacementLines: [String]

    enum CodingKeys: String, CodingKey {
      case startLine
      case startLineSnake = "start_line"
      case start
      case endLine
      case endLineSnake = "end_line"
      case end
      case replacementLines
      case replacementLinesSnake = "replacement_lines"
      case lines
      case newString
      case newStringSnake = "new_string"
      case replacement
      case replace
      case content
      case insert
      case insertSnake = "_insert"
      case insertText
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      startLine = try Self.decodeRequiredLine(
        from: container,
        preferredKey: .startLine,
        aliases: [.startLineSnake, .start],
        fieldName: "startLine"
      )
      endLine = try Self.decodeRequiredLine(
        from: container,
        preferredKey: .endLine,
        aliases: [.endLineSnake, .end],
        fieldName: "endLine"
      )
      replacementLines = try Self.decodeReplacementLines(from: container)
    }

    private static func decodeRequiredLine<Key: CodingKey>(
      from container: KeyedDecodingContainer<Key>,
      preferredKey: Key,
      aliases: [Key],
      fieldName: String
    ) throws -> Int {
      var sawPresentKey = false
      var firstTypeError: Error?

      for key in [preferredKey] + aliases where container.contains(key) {
        sawPresentKey = true
        do {
          if let value = try decodeLine(from: container, forKey: key) {
            return value
          }
        } catch {
          firstTypeError = firstTypeError ?? error
        }
      }

      if !sawPresentKey {
        throw DecodingError.keyNotFound(
          preferredKey,
          .init(
            codingPath: container.codingPath,
            debugDescription: "Missing required \(fieldName) field."
          )
        )
      }
      if let firstTypeError {
        throw firstTypeError
      }
      throw DecodingError.valueNotFound(
        Int.self,
        .init(
          codingPath: container.codingPath,
          debugDescription: "Expected integer \(fieldName)."
        )
      )
    }

    private static func decodeLine<Key: CodingKey>(
      from container: KeyedDecodingContainer<Key>,
      forKey key: Key
    ) throws -> Int? {
      if let value = try? container.decode(Int.self, forKey: key) {
        return value
      }
      if let value = try? container.decode(Double.self, forKey: key) {
        return Int(value)
      }
      if let rawValue = try? container.decode(String.self, forKey: key) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) {
          return value
        }
        if let value = Double(trimmed) {
          return Int(value)
        }
      }
      return nil
    }

    private static func decodeReplacementLines(
      from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
      for key in [
        CodingKeys.replacementLines,
        .replacementLinesSnake,
        .lines,
        .newString,
        .newStringSnake,
        .replacement,
        .replace,
        .content,
        .insert,
        .insertSnake,
        .insertText,
      ] where container.contains(key) {
        if try container.decodeNil(forKey: key) {
          return []
        }
        if let values = try? container.decode([String].self, forKey: key) {
          return values
        }
        if let value = try? container.decode(String.self, forKey: key) {
          return value.components(separatedBy: "\n")
        }
      }
      throw DecodingError.keyNotFound(
        CodingKeys.replacementLines,
        .init(
          codingPath: container.codingPath,
          debugDescription: "Missing required replacementLines field."
        )
      )
    }
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["path", "edits"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Path to the existing file to edit. May be absolute (must resolve inside the working directory) or relative to it. The file must have been read with read_file earlier in this session.",
        ],
        "edits": [
          "type": "array",
          "minItems": 1,
          "description":
            "Ordered list of line-range operations applied to the file. Each later edit sees the file as transformed by earlier edits. All edits must succeed; if any fails the file is left unchanged.",
          "items": [
            "type": "object",
            "additionalProperties": false,
            "required": ["startLine", "endLine", "replacementLines"],
            "properties": [
              "startLine": [
                "type": "integer",
                "minimum": 1,
                "description":
                  "1-indexed first line affected. Use the line numbers from read_file output.",
              ],
              "endLine": [
                "type": "integer",
                "minimum": 0,
                "description":
                  "1-indexed last line replaced, inclusive. Set endLine to startLine - 1 to insert without deleting lines.",
              ],
              "replacementLines": [
                "type": "array",
                "items": ["type": "string"],
                "description":
                  "Replacement lines without line-number prefixes. Use [] to delete the range.",
              ],
            ],
          ],
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Apply one or more line-range edits to a UTF-8 text file. Replace inclusive lines [startLine, endLine] with replacementLines, or insert when endLine is startLine - 1. Edits are applied in order; later line numbers refer to the file after earlier edits. All-or-nothing: a failing edit aborts the whole call without writing. Requires a prior read_file for the path.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(
        .invalidArguments(Self.argumentRepairMessage(agentToolDecodingErrorDescription(error))))
    }

    guard !args.edits.isEmpty else {
      return .failure(
        .invalidArguments("edits is empty; pass at least one line-range operation"))
    }

    for (idx, edit) in args.edits.enumerated() {
      if edit.startLine < 1 {
        return .failure(
          .invalidArguments("edits[\(idx)].startLine must be >= 1; got \(edit.startLine)"))
      }
      if edit.endLine < edit.startLine - 1 {
        return .failure(
          .invalidArguments(
            "edits[\(idx)].endLine must be >= startLine - 1; got startLine=\(edit.startLine), endLine=\(edit.endLine)"
          ))
      }
      if let embeddedNewline = Self.embeddedNewline(in: edit.replacementLines) {
        return .failure(
          .invalidArguments(
            "edits[\(idx)].replacementLines[\(embeddedNewline.lineIndex)] contains embedded newline characters: \(embeddedNewline.preview). Pass replacementLines as an array with one source line per string, for example [\"line one\", \"line two\"], instead of packing multiple source lines into one array entry."
          ))
      }
      if let contamination = Self.replacementLineContamination(in: edit.replacementLines) {
        return .failure(
          .invalidArguments(
            "edits[\(idx)].replacementLines appears to include \(contamination.kind) copied from read_file output at replacement line \(contamination.lineNumber): \(contamination.preview). Remove read_file line-number prefixes and footer text; pass only source text."
          ))
      }
    }

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    if await !context.readTracker.wasRead(url) {
      if !FileManager.default.fileExists(atPath: url.path) {
        return .failure(
          .readNotTracked(
            await missingEditTargetMessage(resolvedURL: url, context: context)
          ))
      }
      return .failure(
        .readNotTracked(
          "edit_file requires a prior read_file for \(context.relativize(url)) in this session. Read the file first and use the returned line numbers for startLine/endLine."
        ))
    }

    let originalData: Data
    do {
      originalData = try await context.filesystem.readFile(at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notFound:
        return .failure(.fileNotFound(args.path))
      case .notRegularFile:
        return .failure(.notRegularFile(args.path))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "filesystem error"))
      }
    } catch {
      return .failure(.ioFailure("read failed: \(error.localizedDescription)"))
    }
    var current: String
    switch AgentTextFile.decodeUTF8(originalData, path: args.path) {
    case .success(let decoded):
      current = decoded
    case .failure(let error):
      return .failure(error)
    }

    let originalText = current
    var lines = Self.fileLines(from: current)
    let relative = context.relativize(url)
    var totalLinesAffected = 0

    for (idx, edit) in args.edits.enumerated() {
      let lineCount = lines.count
      if edit.endLine == edit.startLine - 1 {
        guard edit.startLine <= lineCount + 1 else {
          return .failure(
            .editConflict(
              outOfRangeMessage(
                editIndex: idx,
                relativePath: relative,
                startLine: edit.startLine,
                endLine: edit.endLine,
                lines: lines
              )))
        }
        if edit.replacementLines.isEmpty {
          return .failure(
            .invalidArguments(
              "edits[\(idx)] inserts nothing; provide replacementLines or use a replace range"))
        }
        lines.insert(contentsOf: edit.replacementLines, at: edit.startLine - 1)
        totalLinesAffected += edit.replacementLines.count
        continue
      }

      guard edit.startLine <= lineCount, edit.endLine <= lineCount else {
        return .failure(
          .editConflict(
            outOfRangeMessage(
              editIndex: idx,
              relativePath: relative,
              startLine: edit.startLine,
              endLine: edit.endLine,
              lines: lines
            )))
      }

      let startIndex = edit.startLine - 1
      let endIndex = edit.endLine - 1
      let existing = Array(lines[startIndex...endIndex])
      if let suspiciousExpansion = Self.suspiciousPartialRewriteMessage(
        editIndex: idx,
        edit: edit,
        lineCount: lineCount
      ) {
        return .failure(.invalidArguments(suspiciousExpansion))
      }
      if existing == edit.replacementLines {
        return .failure(
          .invalidArguments(
            "edits[\(idx)] replacementLines are identical to the current lines \(edit.startLine)-\(edit.endLine); no edit needed"
          ))
      }

      lines.replaceSubrange(startIndex...endIndex, with: edit.replacementLines)
      totalLinesAffected += max(existing.count, edit.replacementLines.count)
    }

    current = Self.joinLines(lines)
    if Self.isSourceFile(url),
      !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return .failure(
        .invalidArguments(
          "edit_file would leave \(relative) empty after editing a non-empty source file. Do not clear a source file as a placeholder; provide complete replacementLines for the implementation, or submit status=failed/status=blocked if you cannot reconstruct it."
        ))
    }
    if let selfReference = Self.newSelfRelativeModuleReference(
      originalText: originalText,
      editedText: current,
      sourceURL: url
    ) {
      return .failure(
        .invalidArguments(
          "edit_file would introduce self-referential relative module \(selfReference.specifier) in \(relative). A file cannot import or export from itself; define the symbol directly in \(relative), or move it to a separate file and import that file."
        ))
    }
    if let missingReference = await Self.newMissingRelativeModuleReference(
      originalText: originalText,
      editedText: current,
      sourceURL: url,
      context: context
    ) {
      return .failure(
        .invalidArguments(
          "edit_file would introduce unresolved relative module \(missingReference.specifier) in \(relative). Compass could not find \(missingReference.expectedDescription). Create the referenced module first, use an existing relative path, or keep the implementation inside \(relative)."
        ))
    }

    do {
      try await context.filesystem.writeFile(Data(current.utf8), at: url)
    } catch let error as AgentFilesystemError {
      if case .transportFailure(let detail) = error {
        return .failure(.rpcFailure(detail))
      }
      return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }

    await context.readTracker.markRead(url, lineCount: lines.count)
    let editPlural = args.edits.count == 1 ? "" : "s"
    return .ok(
      "applied \(args.edits.count) edit\(editPlural) to \(relative); file now has \(lines.count) lines (touched \(totalLinesAffected) line\(totalLinesAffected == 1 ? "" : "s"))"
    )
  }

  private func outOfRangeMessage(
    editIndex: Int,
    relativePath: String,
    startLine: Int,
    endLine: Int,
    lines: [String]
  ) -> String {
    let lineCount = lines.count
    var message =
      "edits[\(editIndex)] line range \(startLine)-\(endLine) is out of range for \(relativePath) (file has \(lineCount) lines)"
    if lineCount > 0 {
      let preview = Self.nearbyLineHints(around: startLine, in: lines)
      message +=
        "\nReread the file — line numbers may have shifted:\n" + preview.joined(separator: "\n")
      message +=
        "\nFor this file, replace the last line with startLine=\(lineCount), endLine=\(lineCount). To insert after the last line, use startLine=\(lineCount + 1), endLine=\(lineCount). Do not retry the same out-of-range range."
    } else {
      message += "; use write_file to create the file from scratch"
    }
    return message
  }

  private func missingEditTargetMessage(resolvedURL: URL, context: AgentToolContext) async -> String
  {
    let relativePath = context.relativize(resolvedURL)
    var message = "edit_file cannot edit \(relativePath) because the file does not exist."
    guard let nearest = await nearestExistingDirectory(from: resolvedURL, context: context) else {
      return message
        + " Use list_files or glob to discover current repo paths before creating a new file. Use write_file only when the plan explicitly requires creating \(relativePath)."
    }

    message += "\nNearest existing directory: \(context.relativize(nearest.url))"
    if !nearest.entries.isEmpty {
      message += "\nExisting entries there:"
      message += nearest.entries.prefix(12).map { "\n- \($0)" }.joined()
      if nearest.entries.count > 12 {
        message += "\n- ... \(nearest.entries.count - 12) more"
      }
    }
    message +=
      "\nIf you meant to change an existing file, call read_file on one of these paths and edit that file. Use write_file for \(relativePath) only when the plan explicitly requires creating that exact new file."
    return message
  }

  private func nearestExistingDirectory(
    from url: URL,
    context: AgentToolContext
  ) async -> (url: URL, entries: [String])? {
    let workingDirectory = context.workingDirectory.standardizedFileURL
    let workingPath = workingDirectory.path
    var candidate = url.deletingLastPathComponent().standardizedFileURL

    while candidate.path.hasPrefix(workingPath) {
      do {
        let entries = try await context.filesystem.listDirectory(at: candidate)
          .map { entry in entry.isDirectory ? "\(entry.name)/" : entry.name }
          .filter { !$0.hasPrefix(".") }
          .sorted()
        if !entries.isEmpty || candidate.path == workingPath {
          return (candidate, entries)
        }
      } catch {
        let parent = candidate.deletingLastPathComponent().standardizedFileURL
        if parent.path == candidate.path { break }
        candidate = parent
        continue
      }
      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private static func nearbyLineHints(around lineNumber: Int, in lines: [String]) -> [String] {
    let lineCount = lines.count
    let center = min(max(lineNumber, 1), lineCount)
    let lower = max(center - 1, 1)
    let upper = min(center + 1, lineCount)
    return (lower...upper).map { number in
      let raw = lines[number - 1]
      let display = raw.count > 160 ? String(raw.prefix(160)) + "…" : raw
      return "  line \(number): \(display)"
    }
  }

  private struct ReplacementLineContamination {
    let kind: String
    let lineNumber: Int
    let preview: String
  }

  private static func replacementLineContamination(in lines: [String])
    -> ReplacementLineContamination?
  {
    for (index, line) in lines.enumerated() {
      let trimmedWhitespace = line.trimmingCharacters(in: .whitespaces)
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedWhitespace.range(of: #"^\d+\t"#, options: .regularExpression) != nil {
        return ReplacementLineContamination(
          kind: "line-number prefixes",
          lineNumber: index + 1,
          preview: linePreview(line)
        )
      }
      if trimmedLine.range(of: #"^\(total \d+ lines\)$"#, options: .regularExpression) != nil {
        return ReplacementLineContamination(
          kind: "read_file footer text",
          lineNumber: index + 1,
          preview: linePreview(line)
        )
      }
    }
    return nil
  }

  private static func linePreview(_ line: String) -> String {
    let display = line.count > 80 ? String(line.prefix(80)) + "..." : line
    return "`\(display)`"
  }

  private struct EmbeddedNewline {
    let lineIndex: Int
    let preview: String
  }

  private static func embeddedNewline(in lines: [String]) -> EmbeddedNewline? {
    for (index, line) in lines.enumerated()
    where line.contains("\n") || line.contains("\r") {
      let escaped =
        line
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
      return EmbeddedNewline(lineIndex: index, preview: linePreview(escaped))
    }
    return nil
  }

  private static func suspiciousPartialRewriteMessage(
    editIndex: Int,
    edit: EditOperation,
    lineCount: Int
  ) -> String? {
    let replacedLineCount = edit.endLine - edit.startLine + 1
    guard replacedLineCount == 1,
      edit.replacementLines.count >= 8,
      lineCount > edit.endLine
    else {
      return nil
    }

    return
      "edits[\(editIndex)] replaces only line \(edit.startLine) with \(edit.replacementLines.count) lines while leaving \(lineCount - edit.endLine) existing lines after it. This looks like a partial whole-file rewrite. Do not retry startLine=\(edit.startLine), endLine=\(edit.endLine) with the same replacement. If you intended to rewrite the whole file, use startLine=1, endLine=\(lineCount). If you intended to insert before line \(edit.startLine), use startLine=\(edit.startLine), endLine=\(edit.startLine - 1). Otherwise replace the exact line range that should be removed."
  }

  private struct MissingRelativeModuleReference {
    let specifier: String
    let expectedDescription: String
  }

  private static func newMissingRelativeModuleReference(
    originalText: String,
    editedText: String,
    sourceURL: URL,
    context: AgentToolContext
  ) async -> MissingRelativeModuleReference? {
    let originalReferences = relativeModuleReferences(in: originalText)
    for specifier in relativeModuleReferences(in: editedText)
    where !originalReferences.contains(specifier) {
      guard
        let expected = await missingRelativeModuleDescription(
          specifier: specifier,
          sourceURL: sourceURL,
          context: context
        )
      else {
        continue
      }
      return MissingRelativeModuleReference(
        specifier: "`\(specifier)`",
        expectedDescription: expected
      )
    }
    return nil
  }

  private struct SelfRelativeModuleReference {
    let specifier: String
  }

  private static func newSelfRelativeModuleReference(
    originalText: String,
    editedText: String,
    sourceURL: URL
  ) -> SelfRelativeModuleReference? {
    let originalReferences = relativeModuleReferences(in: originalText)
    for specifier in relativeModuleReferences(in: editedText)
    where !originalReferences.contains(specifier) {
      let baseURL = sourceURL.deletingLastPathComponent()
        .appending(path: specifier)
        .standardizedFileURL
      let sourcePath = sourceURL.standardizedFileURL.path
      if moduleResolutionCandidates(for: baseURL).contains(where: {
        $0.standardizedFileURL.path == sourcePath
      }) {
        return SelfRelativeModuleReference(specifier: "`\(specifier)`")
      }
    }
    return nil
  }

  private static func relativeModuleReferences(in text: String) -> Set<String> {
    var references: Set<String> = []
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("export ") else { continue }
      for pattern in [
        #"from\s+["'](\.{1,2}/[^"']+)["']"#,
        #"^\s*import\s+["'](\.{1,2}/[^"']+)["']"#,
        #"^\s*export\s+["'](\.{1,2}/[^"']+)["']"#,
      ] {
        if let specifier = firstCapture(in: line, pattern: pattern) {
          references.insert(specifier)
        }
      }
    }
    return references
  }

  private static func firstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: nsRange),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[range])
  }

  private static func missingRelativeModuleDescription(
    specifier: String,
    sourceURL: URL,
    context: AgentToolContext
  ) async -> String? {
    let baseURL = sourceURL.deletingLastPathComponent()
      .appending(path: specifier)
      .standardizedFileURL
    let candidates = moduleResolutionCandidates(for: baseURL)
    for candidate in candidates {
      if let metadata = try? await context.filesystem.metadata(of: candidate),
        metadata.isRegularFile
      {
        return nil
      }
    }
    let relativeCandidates =
      candidates
      .prefix(6)
      .map { context.relativize($0) }
      .joined(separator: ", ")
    return relativeCandidates.isEmpty ? context.relativize(baseURL) : relativeCandidates
  }

  private static func moduleResolutionCandidates(for baseURL: URL) -> [URL] {
    let fileExtensions = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs", "json"]
    if !baseURL.pathExtension.isEmpty {
      return [baseURL]
    }
    var candidates = [baseURL]
    candidates += fileExtensions.map { baseURL.appendingPathExtension($0) }
    candidates += fileExtensions.map {
      baseURL
        .appending(path: "index")
        .appendingPathExtension($0)
    }
    return candidates
  }

  private static func fileLines(from text: String) -> [String] {
    text.components(separatedBy: "\n")
  }

  private static func joinLines(_ lines: [String]) -> String {
    lines.joined(separator: "\n")
  }

  private static func isSourceFile(_ url: URL) -> Bool {
    [
      "c",
      "cc",
      "cpp",
      "css",
      "go",
      "h",
      "hpp",
      "html",
      "js",
      "jsx",
      "mjs",
      "mts",
      "py",
      "rs",
      "swift",
      "ts",
      "tsx",
    ].contains(url.pathExtension.lowercased())
  }

  private static func argumentRepairMessage(_ detail: String) -> String {
    """
    \(detail)
    edit_file requires path plus startLine, endLine, and replacement lines. Read the target file first, then use the returned line numbers.
    Example replace: {"path":"packages/cli/src/main.ts","startLine":4,"endLine":6,"insert":["new line"]}
    Example insert after line 6: {"path":"packages/cli/src/main.ts","startLine":7,"endLine":6,"insert":["new line"]}
    Use write_file instead only when creating a new file.
    """
  }
}
