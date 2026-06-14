import Foundation

/// Line-range edits on an existing UTF-8 text file. The model passes an
/// ordered list of operations; each replaces the inclusive 1-indexed line
/// range `[startLine, endLine]` with `replacementLines` or common aliases
/// (or inserts when `endLine == startLine - 1`). All edits succeed atomically
/// — if any one fails, the file is not written. A prior `read_file` for the
/// path is required so line numbers come from content the model has actually
/// seen.
package struct AgentEditFileTool: AgentTool {
  package static let toolName = "edit_file"

  package struct Arguments: Decodable {
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
      case insertion
    }

    package init(from decoder: Decoder) throws {
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
        .insertion,
      ].contains { container.contains($0) }
    }
  }

  package struct EditOperation: Decodable {
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
      case insertion
    }

    package init(from decoder: Decoder) throws {
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
        .insertion,
      ] where container.contains(key) {
        if try container.decodeNil(forKey: key) {
          return []
        }
        if let values = try? container.decode([String].self, forKey: key) {
          return Self.normalizeReplacementLines(values.flatMap(Self.splitReplacementText))
        }
        if let value = try? container.decode(String.self, forKey: key) {
          return Self.normalizeReplacementLines(Self.splitReplacementText(value))
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

    private static func splitReplacementText(_ text: String) -> [String] {
      text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
    }

    private static func normalizeReplacementLines(_ lines: [String]) -> [String] {
      stripCopiedReadFileRows(from: lines) ?? lines
    }

    private static func stripCopiedReadFileRows(from lines: [String]) -> [String]? {
      var stripped: [String] = []
      var expectedNextNumber: Int?
      var sawNumberedRow = false

      for line in lines {
        if isReadFileFooter(line) {
          continue
        }
        guard let row = copiedReadFileRow(line) else {
          return nil
        }
        if let expectedNextNumber, row.number != expectedNextNumber {
          return nil
        }
        stripped.append(row.content)
        expectedNextNumber = row.number + 1
        sawNumberedRow = true
      }

      return sawNumberedRow ? stripped : nil
    }

    private static func isReadFileFooter(_ line: String) -> Bool {
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedLine.range(of: #"^\(total \d+ lines\)$"#, options: .regularExpression) != nil
    }

    private static func copiedReadFileRow(_ line: String) -> (number: Int, content: String)? {
      var index = line.startIndex
      var sawLeadingSpace = false
      while index < line.endIndex, line[index] == " " {
        sawLeadingSpace = true
        index = line.index(after: index)
      }
      guard sawLeadingSpace else { return nil }

      let digitsStart = index
      while index < line.endIndex, line[index].wholeNumberValue != nil {
        index = line.index(after: index)
      }
      guard digitsStart < index,
        index < line.endIndex,
        line[index] == "\t",
        let number = Int(line[digitsStart..<index])
      else {
        return nil
      }

      let contentStart = line.index(after: index)
      return (number, String(line[contentStart...]))
    }
  }

  private struct WriteFileRepairPayload: Encodable {
    let path: String
    let content: String
  }

  private struct EditFileContentRepairPayload: Encodable {
    let path: String
    let edits: [EditFileContentRepairEdit]
  }

  private struct EditFileContentRepairEdit: Encodable {
    let startLine: Int
    let endLine: Int
    let content: String
  }

  private struct EditFileInsertRepairPayload: Encodable {
    let path: String
    let edits: [EditFileInsertRepairEdit]
  }

  private struct EditFileInsertRepairEdit: Encodable {
    let startLine: Int
    let endLine: Int
    let insert: String
  }

  package let spec: AgentToolSpec

  package init() {
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
                  "Replacement lines without line-number prefixes. Use [] to delete the range. Newline-packed strings are split into source lines, and obvious copied read_file row prefixes are stripped.",
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

  package func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
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
        var message =
          "edits[\(idx)].startLine must be >= 1; got \(edit.startLine). Line numbers are 1-indexed; never use startLine=0."
        if edit.endLine == 0 {
          message += Self.editFileInsertRepairHint(
            path: args.path,
            startLine: 1,
            endLine: 0,
            content: Self.joinLines(edit.replacementLines),
            intro: "To insert before the first line, return `edit_file` with these arguments"
          )
        }
        return .failure(
          .invalidArguments(message))
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
            await missingEditTargetMessage(resolvedURL: url, edits: args.edits, context: context)
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
    var appliedEditCount = 0
    var noOpEditCount = 0
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
        if let testCode = Self.testCodeInNonTestSourceMessage(
          editIndex: idx,
          relativePath: relative,
          replacementLines: edit.replacementLines,
          isSourceFile: Self.isSourceFile(url),
          isTestFile: Self.isTestFile(url)
        ) {
          return .failure(.invalidArguments(testCode))
        }
        if let implementationCode = Self.implementationCodeInTestFileMessage(
          editIndex: idx,
          relativePath: relative,
          replacementLines: edit.replacementLines,
          isSourceFile: Self.isSourceFile(url),
          isTestFile: Self.isTestFile(url)
        ) {
          return .failure(.invalidArguments(implementationCode))
        }
        if let duplicateInsertion = Self.duplicateSourceInsertionMessage(
          editIndex: idx,
          edit: edit,
          relativePath: relative,
          lines: lines,
          isSourceFile: Self.isSourceFile(url)
        ) {
          return .failure(.invalidArguments(duplicateInsertion))
        }
        if let suspiciousInsertion = Self.suspiciousWholeFileInsertionMessage(
          editIndex: idx,
          edit: edit,
          relativePath: relative,
          lineCount: lineCount,
          isSourceFile: Self.isSourceFile(url)
        ) {
          return .failure(.invalidArguments(suspiciousInsertion))
        }
        if let misplacedImport = Self.misplacedTopLevelImportMessage(
          editIndex: idx,
          edit: edit,
          relativePath: relative,
          lines: lines,
          isSourceFile: Self.isSourceFile(url)
        ) {
          return .failure(.invalidArguments(misplacedImport))
        }
        lines.insert(contentsOf: edit.replacementLines, at: edit.startLine - 1)
        appliedEditCount += 1
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
      if let testCode = Self.testCodeInNonTestSourceMessage(
        editIndex: idx,
        relativePath: relative,
        replacementLines: edit.replacementLines,
        isSourceFile: Self.isSourceFile(url),
        isTestFile: Self.isTestFile(url)
      ) {
        return .failure(.invalidArguments(testCode))
      }
      if let implementationCode = Self.implementationCodeInTestFileMessage(
        editIndex: idx,
        relativePath: relative,
        replacementLines: edit.replacementLines,
        isSourceFile: Self.isSourceFile(url),
        isTestFile: Self.isTestFile(url)
      ) {
        return .failure(.invalidArguments(implementationCode))
      }
      if Self.isSourceFile(url),
        let commentOnlyReplacement = Self.commentOnlySourceReplacementMessage(
          editIndex: idx,
          relativePath: relative,
          existingLines: existing,
          replacementLines: edit.replacementLines,
          pathExtension: url.pathExtension
        )
      {
        return .failure(.invalidArguments(commentOnlyReplacement))
      }
      if let suspiciousExpansion = Self.suspiciousPartialRewriteMessage(
        editIndex: idx,
        edit: edit,
        relativePath: relative,
        existingLines: existing,
        remainingLines: Array(lines.dropFirst(endIndex + 1)),
        isSourceFile: Self.isSourceFile(url),
        lineCount: lineCount
      ) {
        return .failure(.invalidArguments(suspiciousExpansion))
      }
      if let declarationRemoval = Self.suspiciousDeclarationBodyReplacementMessage(
        editIndex: idx,
        edit: edit,
        relativePath: relative,
        existingLines: existing,
        allLines: lines,
        lineCount: lineCount
      ) {
        return .failure(.invalidArguments(declarationRemoval))
      }
      if let nestedTopLevel = Self.suspiciousNestedTopLevelDeclarationMessage(
        editIndex: idx,
        edit: edit,
        linesBeforeEdit: Array(lines.prefix(startIndex))
      ) {
        return .failure(.invalidArguments(nestedTopLevel))
      }
      if existing == edit.replacementLines {
        noOpEditCount += 1
        continue
      }
      if let duplicateReplacement = Self.duplicateSourceReplacementMessage(
        editIndex: idx,
        edit: edit,
        relativePath: relative,
        lines: lines,
        replacedRange: startIndex..<(endIndex + 1),
        isSourceFile: Self.isSourceFile(url)
      ) {
        return .failure(.invalidArguments(duplicateReplacement))
      }
      if let misplacedImport = Self.misplacedTopLevelImportMessage(
        editIndex: idx,
        edit: edit,
        relativePath: relative,
        lines: lines,
        isSourceFile: Self.isSourceFile(url)
      ) {
        return .failure(.invalidArguments(misplacedImport))
      }

      lines.replaceSubrange(startIndex...endIndex, with: edit.replacementLines)
      appliedEditCount += 1
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
    if Self.isSourceFile(url),
      let placeholder = Self.newPlaceholderImplementationMarker(
        originalText: originalText,
        editedText: current
      )
    {
      return .failure(
        .invalidArguments(
          "edit_file would introduce placeholder implementation code in \(relative) at line \(placeholder.lineNumber): \(placeholder.preview). Do not replace working source with TODO/not-implemented placeholders; provide the complete implementation now, or submit status=failed/status=blocked if you cannot."
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

    if current != originalText {
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
    }

    await context.readTracker.markRead(url, lineCount: lines.count)
    if appliedEditCount == 0 {
      let noOpPlural = noOpEditCount == 1 ? "" : "s"
      return .ok(
        "no changes needed for \(relative); \(noOpEditCount) edit\(noOpPlural) already matched the current file. Do not retry the identical edit; continue with the next required task, run verify if implementation is complete, or submit only when the plan is done."
      )
    }

    let editPlural = appliedEditCount == 1 ? "" : "s"
    var message =
      "applied \(appliedEditCount) edit\(editPlural) to \(relative); file now has \(lines.count) lines (touched \(totalLinesAffected) line\(totalLinesAffected == 1 ? "" : "s"))"
    if noOpEditCount > 0 {
      let noOpPlural = noOpEditCount == 1 ? "" : "s"
      message += "; skipped \(noOpEditCount) no-op edit\(noOpPlural) that already matched"
    }
    return .ok(
      message
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

  private func missingEditTargetMessage(
    resolvedURL: URL,
    edits: [EditOperation],
    context: AgentToolContext
  ) async -> String {
    let relativePath = context.relativize(resolvedURL)
    let creationHint = Self.writeFileCreationRepairHint(
      relativePath: relativePath,
      edits: edits
    )
    var message = "edit_file cannot edit \(relativePath) because the file does not exist."
    guard let nearest = await nearestExistingDirectory(from: resolvedURL, context: context) else {
      return message
        + " Use list_files or glob to discover current repo paths before creating a new file. Use write_file only when the plan explicitly requires creating \(relativePath).\(creationHint)"
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
    message += creationHint
    return message
  }

  private static func writeFileCreationRepairHint(
    relativePath: String,
    edits: [EditOperation]
  ) -> String {
    guard edits.count == 1, let edit = edits.first else { return "" }
    let content = joinLines(edit.replacementLines)
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
    let payload = WriteFileRepairPayload(path: relativePath, content: content)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return """

      If you intended to create this new file, return `write_file` with these arguments instead of retrying `edit_file`:
      ```json
      \(json)
      ```
      """
  }

  private static func editFileContentRepairHint(
    path: String,
    startLine: Int,
    endLine: Int,
    content: String,
    intro: String
  ) -> String {
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
    let payload = EditFileContentRepairPayload(
      path: path,
      edits: [
        EditFileContentRepairEdit(
          startLine: startLine,
          endLine: endLine,
          content: content
        )
      ]
    )
    return encodedEditFileRepairHint(payload: payload, intro: intro)
  }

  private static func editFileInsertRepairHint(
    path: String,
    startLine: Int,
    endLine: Int,
    content: String,
    intro: String
  ) -> String {
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
    let payload = EditFileInsertRepairPayload(
      path: path,
      edits: [
        EditFileInsertRepairEdit(
          startLine: startLine,
          endLine: endLine,
          insert: content
        )
      ]
    )
    return encodedEditFileRepairHint(payload: payload, intro: intro)
  }

  private static func encodedEditFileRepairHint<Payload: Encodable>(
    payload: Payload,
    intro: String
  ) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return """

      \(intro):
      ```json
      \(json)
      ```
      """
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

  private static func commentOnlySourceReplacementMessage(
    editIndex: Int,
    relativePath: String,
    existingLines: [String],
    replacementLines: [String],
    pathExtension: String
  ) -> String? {
    let nonEmptyReplacementLines =
      replacementLines
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !replacementLines.isEmpty,
      !nonEmptyReplacementLines.isEmpty,
      containsMeaningfulSource(existingLines, pathExtension: pathExtension),
      !containsMeaningfulSource(replacementLines, pathExtension: pathExtension)
    else {
      return nil
    }

    let preview =
      nonEmptyReplacementLines
      .first
      .map { linePreview($0) } ?? "comment-only replacement"
    return
      "edits[\(editIndex)] would replace working source lines in \(relativePath) with comment-only content: \(preview). Do not replace working source with TODO/comment-only placeholders; provide complete replacementLines, delete the range only if removal is intended, or submit status=failed/status=blocked if you cannot reconstruct it."
  }

  private static func testCodeInNonTestSourceMessage(
    editIndex: Int,
    relativePath: String,
    replacementLines: [String],
    isSourceFile: Bool,
    isTestFile: Bool
  ) -> String? {
    guard isSourceFile, !isTestFile,
      let marker = firstTestCodeMarker(in: replacementLines)
    else {
      return nil
    }

    return
      "edits[\(editIndex)] would introduce test code into non-test source file \(relativePath) at replacement line \(marker.lineNumber): \(marker.preview). Do not paste assertion blocks into implementation files. Put behavior checks in `tests/*.json`, and edit \(relativePath) with implementation code only."
  }

  private static func implementationCodeInTestFileMessage(
    editIndex: Int,
    relativePath: String,
    replacementLines: [String],
    isSourceFile: Bool,
    isTestFile: Bool
  ) -> String? {
    guard isSourceFile, isTestFile,
      let marker = firstArgumentParsingImplementationMarker(in: replacementLines)
    else {
      return nil
    }
    if let testMarker = firstTestCodeMarker(in: replacementLines),
      testMarker.lineNumber < marker.lineNumber
    {
      return nil
    }

    let implementationPath = probableImplementationPath(forTestPath: relativePath)
    return
      "edits[\(editIndex)] would introduce argument-parsing implementation code into test file \(relativePath) at replacement line \(marker.lineNumber): \(marker.preview). Do not repair production behavior by pasting `argv` parsing or return logic into a test file. Edit \(implementationPath) with the implementation, and keep test edits focused on `describe`/`it`/`test`/`expect` assertions or fixtures."
  }

  private struct TestCodeMarker {
    let lineNumber: Int
    let preview: String
  }

  private static func firstTestCodeMarker(in lines: [String]) -> TestCodeMarker? {
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.range(
        of: #"^(describe|it|test)\s*\("#,
        options: .regularExpression
      ) != nil
        || trimmed.range(of: #"^expect\s*\("#, options: .regularExpression) != nil
      {
        return TestCodeMarker(lineNumber: index + 1, preview: linePreview(trimmed))
      }
    }
    return nil
  }

  private static func firstArgumentParsingImplementationMarker(in lines: [String])
    -> TestCodeMarker?
  {
    let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard trimmedLines.contains(where: { line in
      line.range(of: #"\b(argv|process\.argv)\b"#, options: .regularExpression) != nil
    }),
      trimmedLines.contains(where: { line in
        line.range(of: #"^return\b"#, options: .regularExpression) != nil
      })
    else {
      return nil
    }

    for (index, line) in trimmedLines.enumerated() where !line.isEmpty {
      if line.range(of: #"\b(argv|process\.argv)\b"#, options: .regularExpression) != nil
        || line.range(of: #"^return\b"#, options: .regularExpression) != nil
      {
        return TestCodeMarker(lineNumber: index + 1, preview: linePreview(line))
      }
    }
    return nil
  }

  private static func probableImplementationPath(forTestPath relativePath: String) -> String {
    let implementationPath =
      relativePath
      .replacingOccurrences(of: ".test.", with: ".")
      .replacingOccurrences(of: ".spec.", with: ".")
    guard implementationPath != relativePath else {
      return "the implementation file imported by this test"
    }
    return implementationPath
  }

  private static func containsMeaningfulSource(
    _ lines: [String],
    pathExtension: String
  ) -> Bool {
    let stripped = sourceTextWithoutComments(
      lines.joined(separator: "\n"),
      pathExtension: pathExtension
    )
    return
      stripped
      .components(separatedBy: .newlines)
      .contains { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("#!")
      }
  }

  private static func sourceTextWithoutComments(
    _ text: String,
    pathExtension: String
  ) -> String {
    let ext = pathExtension.lowercased()
    var stripped = text

    if ["html"].contains(ext) {
      stripped = replacingMatches(
        in: stripped,
        pattern: #"<!--.*?-->"#,
        options: [.dotMatchesLineSeparators]
      )
    }
    if ["c", "cc", "cpp", "css", "go", "h", "hpp", "rs", "swift"].contains(ext) {
      stripped = replacingMatches(
        in: stripped,
        pattern: #"/\*.*?\*/"#,
        options: [.dotMatchesLineSeparators]
      )
      stripped = replacingMatches(in: stripped, pattern: #"(?m)//.*$"#)
    }
    if ["tes"].contains(ext) {
      stripped = replacingMatches(in: stripped, pattern: #"(?m);.*$"#)
    }
    if ["py", "rb"].contains(ext) {
      stripped = replacingMatches(
        in: stripped,
        pattern: #"'''.*?'''"#,
        options: [.dotMatchesLineSeparators]
      )
      stripped = replacingMatches(
        in: stripped,
        pattern: #""{3}.*?"{3}"#,
        options: [.dotMatchesLineSeparators]
      )
      stripped = replacingMatches(in: stripped, pattern: #"(?m)#.*$"#)
    }

    return stripped
  }

  private static func replacingMatches(
    in text: String,
    pattern: String,
    options: NSRegularExpression.Options = []
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
  }

  private static func suspiciousPartialRewriteMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    existingLines: [String],
    remainingLines: [String],
    isSourceFile: Bool,
    lineCount: Int
  ) -> String? {
    let replacedLineCount = edit.endLine - edit.startLine + 1
    let duplicateFunctionNames = Set(topLevelFunctionNames(in: edit.replacementLines))
      .intersection(topLevelFunctionNames(in: remainingLines))
    let looksLikeShortTopOfFileRewrite =
      isSourceFile
      && edit.startLine <= 2
      && edit.replacementLines.count >= 4
      && firstTopLevelDeclaration(in: edit.replacementLines) != nil
      && (existingLines.first?.hasPrefix("#!") == true || !duplicateFunctionNames.isEmpty)

    guard replacedLineCount == 1,
      lineCount > edit.endLine,
      edit.replacementLines.count >= 8 || looksLikeShortTopOfFileRewrite
    else {
      return nil
    }

    let repairHint = editFileContentRepairHint(
      path: relativePath,
      startLine: 1,
      endLine: lineCount,
      content: joinLines(edit.replacementLines),
      intro:
        "If this is the intended whole-file replacement, return `edit_file` with these arguments"
    )

    return
      "edits[\(editIndex)] replaces only line \(edit.startLine) with \(edit.replacementLines.count) lines while leaving \(lineCount - edit.endLine) existing lines after it. This looks like a partial whole-file rewrite. Do not retry startLine=\(edit.startLine), endLine=\(edit.endLine) with the same replacement, and do not fix this by shifting to another single-line range such as startLine=\(min(edit.startLine + 1, lineCount)), endLine=\(min(edit.endLine + 1, lineCount)). Your next edit_file call must use a different edit shape: if you intended to rewrite the whole file, use startLine=1, endLine=\(lineCount) and include the complete intended file content; if you intended to insert before line \(edit.startLine), use startLine=\(edit.startLine), endLine=\(edit.startLine - 1) with only the new lines to insert, not the whole file; otherwise replace the exact existing line range that should be removed. Do not submit failed/blocked until you have tried one of those different edit shapes."
      + repairHint
  }

  private static func suspiciousWholeFileInsertionMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    lineCount: Int,
    isSourceFile: Bool
  ) -> String? {
    guard isSourceFile,
      edit.startLine <= 2,
      lineCount > 0,
      edit.replacementLines.count >= 8,
      edit.replacementLines.count >= max(8, lineCount / 2)
    else {
      return nil
    }

    let repairHint = editFileContentRepairHint(
      path: relativePath,
      startLine: 1,
      endLine: lineCount,
      content: joinLines(edit.replacementLines),
      intro:
        "If this is the intended whole-file replacement, return `edit_file` with these arguments"
    )

    return
      "edits[\(editIndex)] inserts \(edit.replacementLines.count) lines before line \(edit.startLine) while leaving \(lineCount) existing lines after it. This looks like a whole-file rewrite expressed as an insertion. Do not retry startLine=\(edit.startLine), endLine=\(edit.endLine) with the same replacement. If you intended to rewrite the whole file, use startLine=1, endLine=\(lineCount). If you intended to add an import or header, insert only those new lines. Otherwise replace the exact line range that should be removed."
      + repairHint
  }

  private static func duplicateSourceInsertionMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    lines: [String],
    isSourceFile: Bool
  ) -> String? {
    guard isSourceFile,
      let block = trimmedInsertionBlock(edit.replacementLines),
      block.count >= 2,
      let existingRange = firstContiguousRange(of: block, in: lines)
    else {
      return nil
    }

    let replacementStart = existingRange.lowerBound + 1
    let replacementEnd = existingRange.upperBound
    return
      "edits[\(editIndex)] inserts \(edit.replacementLines.count) lines, but the same nonblank source block already exists in \(relativePath) at lines \(replacementStart)-\(replacementEnd). Do not insert this block again at any line; repeated duplicate insertions usually make verification failures worse. If the existing block is wrong, replace or remove lines \(replacementStart)-\(replacementEnd), or rewrite the enclosing function or whole file once with a single complete version."
  }

  private static func duplicateSourceReplacementMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    lines: [String],
    replacedRange: Range<Int>,
    isSourceFile: Bool
  ) -> String? {
    guard isSourceFile,
      let block = trimmedInsertionBlock(edit.replacementLines),
      block.count >= 2,
      let existingRange = firstContiguousRange(of: block, in: lines, excluding: replacedRange)
    else {
      return nil
    }

    let replacementStart = existingRange.lowerBound + 1
    let replacementEnd = existingRange.upperBound
    return
      "edits[\(editIndex)] replaces lines \(edit.startLine)-\(edit.endLine) with \(edit.replacementLines.count) lines, but the same nonblank source block already exists in \(relativePath) at lines \(replacementStart)-\(replacementEnd). Do not duplicate this block by replacing another line/range with it. If the existing block is wrong, replace or remove lines \(replacementStart)-\(replacementEnd); if the current range is wrong, read the verify error and edit the exact broken test structure or implementation structure instead."
  }

  private static func misplacedTopLevelImportMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    lines: [String],
    isSourceFile: Bool
  ) -> String? {
    guard isSourceFile,
      let importLine = firstTopLevelImportLine(in: edit.replacementLines),
      let bodyLine = firstNonHeaderLine(in: lines)
    else {
      return nil
    }

    let insertsBeforeBody = edit.endLine == edit.startLine - 1 && edit.startLine <= bodyLine
    let rewritesHeader = edit.startLine == 1 || edit.startLine < bodyLine
    guard !insertsBeforeBody, !rewritesHeader else {
      return nil
    }

    return
      "edits[\(editIndex)] starts at line \(edit.startLine) in \(relativePath), after the file header, but the replacement contains top-level import \(importLine). Do not paste imports into a function/body replacement; insert imports near the top of the file, or rewrite the whole file from line 1 if the import section must change."
  }

  private static func trimmedInsertionBlock(_ lines: [String]) -> [String]? {
    var start = 0
    var end = lines.count
    while start < end && lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      start += 1
    }
    while end > start && lines[end - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      end -= 1
    }
    guard start < end else { return nil }
    return Array(lines[start..<end])
  }

  private static func firstContiguousRange(
    of needle: [String],
    in haystack: [String],
    excluding excludedRange: Range<Int>? = nil
  ) -> Range<Int>? {
    guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
    let lastStart = haystack.count - needle.count
    for start in 0...lastStart {
      let end = start + needle.count
      if let excludedRange,
        start < excludedRange.upperBound,
        end > excludedRange.lowerBound
      {
        continue
      }
      if Array(haystack[start..<end]) == needle {
        return start..<end
      }
    }
    return nil
  }

  private struct FunctionDeclarationLine {
    let name: String
    let lineNumber: Int
  }

  private static func suspiciousDeclarationBodyReplacementMessage(
    editIndex: Int,
    edit: EditOperation,
    relativePath: String,
    existingLines: [String],
    allLines: [String],
    lineCount: Int
  ) -> String? {
    guard lineCount > edit.endLine,
      let declaration = firstFunctionDeclaration(
        in: existingLines,
        startLine: edit.startLine
      ),
      !replacementDeclaresFunction(named: declaration.name, in: edit.replacementLines),
      looksLikeFunctionBodyReplacement(edit.replacementLines)
    else {
      return nil
    }

    let functionEndLine = closingLineForBlock(in: allLines, startLine: declaration.lineNumber)
    let fullFunctionRange =
      functionEndLine.map {
        "use startLine=\(declaration.lineNumber), endLine=\($0), and include the complete `\(declaration.name)` function declaration, body, and closing brace"
      }
      ?? "include the complete `\(declaration.name)` function declaration, body, and closing brace in the replacement"
    let bodyRange: String
    if let functionEndLine, declaration.lineNumber + 1 <= functionEndLine - 1 {
      bodyRange =
        "or edit only the function body with startLine=\(declaration.lineNumber + 1), endLine=\(functionEndLine - 1)"
    } else {
      bodyRange = "or insert the intended body immediately after line \(declaration.lineNumber)"
    }
    let repairHint: String
    if let functionEndLine, functionEndLine <= allLines.count {
      let bodyLines = trimmedInsertionBlock(edit.replacementLines) ?? edit.replacementLines
      let fullFunctionLines =
        [allLines[declaration.lineNumber - 1]] + bodyLines + [allLines[functionEndLine - 1]]
      repairHint = editFileContentRepairHint(
        path: relativePath,
        startLine: declaration.lineNumber,
        endLine: functionEndLine,
        content: joinLines(fullFunctionLines),
        intro:
          "If your replacement lines are the new body for `\(declaration.name)`, return `edit_file` with these arguments next"
      )
    } else {
      repairHint = ""
    }

    return
      "edits[\(editIndex)] would remove the function declaration `\(declaration.name)` on line \(declaration.lineNumber) and replace it with body-only lines while leaving \(lineCount - edit.endLine) existing lines after the edit. This usually breaks the surrounding source structure. Your next edit_file call must use a different edit shape: \(fullFunctionRange); \(bodyRange). Because no edit was applied, do not call read_file again for \(relativePath) before attempting one of these shapes. Do not retry startLine=\(edit.startLine), endLine=\(edit.endLine) with body-only replacement lines."
      + repairHint
  }

  private struct OpenBlockLine {
    let lineNumber: Int
    let preview: String
  }

  private static func suspiciousNestedTopLevelDeclarationMessage(
    editIndex: Int,
    edit: EditOperation,
    linesBeforeEdit: [String]
  ) -> String? {
    guard let openBlock = innermostOpenBlock(before: linesBeforeEdit),
      let declaration = firstTopLevelDeclaration(in: edit.replacementLines)
    else {
      return nil
    }

    return
      "edits[\(editIndex)] starts inside an open block from line \(openBlock.lineNumber) (`\(openBlock.preview)`) but the replacement contains top-level \(declaration). This would nest an import/export/function declaration inside the existing block and usually causes a parse error. If you intended to rewrite the enclosing block, include line \(openBlock.lineNumber) in the edit range. If you intended to add an import, insert it near the top of the file instead."
  }

  private static func innermostOpenBlock(before lines: [String]) -> OpenBlockLine? {
    var stack: [OpenBlockLine] = []
    for (offset, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      for character in line {
        if character == "{" {
          stack.append(
            OpenBlockLine(
              lineNumber: offset + 1,
              preview: String(trimmed.prefix(120))
            ))
        } else if character == "}", !stack.isEmpty {
          _ = stack.removeLast()
        }
      }
    }
    return stack.last
  }

  private static func firstTopLevelDeclaration(in lines: [String]) -> String? {
    for line in lines {
      guard line.first?.isWhitespace != true else { continue }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if trimmed.hasPrefix("import ") {
        return "import `\(String(trimmed.prefix(120)))`"
      }
      if trimmed.hasPrefix("export ")
        || trimmed.hasPrefix("function ")
        || trimmed.hasPrefix("class ")
        || trimmed.hasPrefix("interface ")
        || trimmed.hasPrefix("type ")
      {
        return "declaration `\(String(trimmed.prefix(120)))`"
      }
    }
    return nil
  }

  private static func firstTopLevelImportLine(in lines: [String]) -> String? {
    for line in lines {
      guard line.first?.isWhitespace != true else { continue }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("import ") {
        return "`\(String(trimmed.prefix(120)))`"
      }
    }
    return nil
  }

  private static func firstNonHeaderLine(in lines: [String]) -> Int? {
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      guard !trimmed.hasPrefix("#!"),
        !trimmed.hasPrefix("import ")
      else {
        continue
      }
      return index + 1
    }
    return nil
  }

  private static func topLevelFunctionNames(in lines: [String]) -> [String] {
    var names: [String] = []
    for line in lines {
      guard line.first?.isWhitespace != true else { continue }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      for prefix in [
        "export default async function ",
        "export default function ",
        "export async function ",
        "export function ",
        "async function ",
        "function ",
      ] where trimmed.hasPrefix(prefix) {
        let remainder = trimmed.dropFirst(prefix.count)
        let name = remainder.prefix { character in
          character.isLetter || character.isNumber || character == "_" || character == "$"
        }
        if !name.isEmpty {
          names.append(String(name))
        }
        break
      }
    }
    return names
  }

  private static func firstFunctionDeclaration(
    in lines: [String],
    startLine: Int
  ) -> FunctionDeclarationLine? {
    for (offset, line) in lines.enumerated() {
      guard line.contains("{"),
        let name = firstCapture(
          in: line,
          pattern:
            #"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\b"#
        )
      else {
        continue
      }
      return FunctionDeclarationLine(name: name, lineNumber: startLine + offset)
    }
    return nil
  }

  private static func replacementDeclaresFunction(named name: String, in lines: [String]) -> Bool {
    lines.contains { line in
      firstCapture(
        in: line,
        pattern:
          #"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\b"#
      ) == name
    }
  }

  private static func closingLineForBlock(in lines: [String], startLine: Int) -> Int? {
    guard startLine >= 1, startLine <= lines.count else { return nil }
    var depth = 0
    var sawOpeningBrace = false
    for index in (startLine - 1)..<lines.count {
      for character in lines[index] {
        if character == "{" {
          depth += 1
          sawOpeningBrace = true
        } else if character == "}", sawOpeningBrace {
          depth -= 1
          if depth <= 0 {
            return index + 1
          }
        }
      }
    }
    return nil
  }

  private static func looksLikeIndentedBodyLine(_ line: String) -> Bool {
    guard line.first?.isWhitespace == true else { return false }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return !trimmed.hasPrefix("export ")
      && !trimmed.hasPrefix("import ")
      && !trimmed.hasPrefix("function ")
      && !trimmed.hasPrefix("class ")
      && !trimmed.hasPrefix("interface ")
      && !trimmed.hasPrefix("type ")
  }

  private static func looksLikeFunctionBodyReplacement(_ lines: [String]) -> Bool {
    guard let firstLine = firstMeaningfulReplacementLine(in: lines) else { return false }
    if looksLikeIndentedBodyLine(firstLine) { return true }

    let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if firstTopLevelDeclaration(in: [firstLine]) != nil || trimmed.hasPrefix("import ") {
      return false
    }
    if lines.contains(where: { line in
      line.trimmingCharacters(in: .whitespacesAndNewlines)
        .range(of: #"^return\b"#, options: .regularExpression) != nil
    }) {
      return true
    }
    return trimmed.range(
      of: #"^(const|let|var|if|for|while|switch|try|catch|await|return|throw)\b"#,
      options: .regularExpression
    ) != nil
  }

  private static func firstMeaningfulReplacementLine(in lines: [String]) -> String? {
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !isCommentOnlyLine(trimmed) else { continue }
      return line
    }
    return nil
  }

  private static func isCommentOnlyLine(_ trimmedLine: String) -> Bool {
    trimmedLine.hasPrefix("//")
      || trimmedLine.hasPrefix("/*")
      || trimmedLine.hasPrefix("*")
      || trimmedLine.hasPrefix("*/")
  }

  private struct MissingRelativeModuleReference {
    let specifier: String
    let expectedDescription: String
  }

  private struct PlaceholderImplementationMarker {
    let lineNumber: Int
    let preview: String
    let fingerprint: String
  }

  private static func newPlaceholderImplementationMarker(
    originalText: String,
    editedText: String
  ) -> PlaceholderImplementationMarker? {
    let originalFingerprints = Set(
      placeholderImplementationMarkers(in: originalText).map(\.fingerprint)
    )
    return placeholderImplementationMarkers(in: editedText).first {
      !originalFingerprints.contains($0.fingerprint)
    }
  }

  private static func placeholderImplementationMarkers(in text: String)
    -> [PlaceholderImplementationMarker]
  {
    text.components(separatedBy: "\n").enumerated().compactMap { offset, line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      let fingerprint = trimmed.lowercased()
      guard looksLikePlaceholderImplementation(fingerprint) else { return nil }
      return PlaceholderImplementationMarker(
        lineNumber: offset + 1,
        preview: "`\(String(trimmed.prefix(120)))`",
        fingerprint: fingerprint
      )
    }
  }

  private static func looksLikePlaceholderImplementation(_ lowercasedLine: String) -> Bool {
    (lowercasedLine.contains("todo")
      && (lowercasedLine.contains("implement") || lowercasedLine.contains("placeholder")))
      || lowercasedLine.contains("not implemented")
      || lowercasedLine.contains("unimplemented")
      || lowercasedLine.contains("placeholder implementation")
      || (lowercasedLine.contains("replace this with")
        && lowercasedLine.contains("implementation"))
      || lowercasedLine.contains("implement the logic")
      || lowercasedLine.contains("implement logic")
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
    let fileExtensions = ["json", "swift", "tes"]
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
      "py",
      "rs",
      "swift",
      "tes",
    ].contains(url.pathExtension.lowercased())
  }

  private static func isTestFile(_ url: URL) -> Bool {
    let path = url.path.lowercased()
    let filename = url.lastPathComponent.lowercased()
    return filename.contains(".test.")
      || filename.contains(".spec.")
      || path.contains("/__tests__/")
      || path.contains("/tests/")
  }

  private static func argumentRepairMessage(_ detail: String) -> String {
    """
    \(detail)
    edit_file requires path plus startLine, endLine, and replacement lines. Read the target file first, then use the returned line numbers.
    Example replace: {"path":"src/display-name.tes","startLine":1,"endLine":2,"replacementLines":["; new line"]}
    Example insert after line 6: {"path":"src/display-name.tes","startLine":7,"endLine":6,"insert":["; new line"]}
    Use write_file instead only when creating a new file.
    """
  }
}
