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
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
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
    } else {
      message += "; use write_file to create the file from scratch"
    }
    return message
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

  private static func fileLines(from text: String) -> [String] {
    text.components(separatedBy: "\n")
  }

  private static func joinLines(_ lines: [String]) -> String {
    lines.joined(separator: "\n")
  }
}
