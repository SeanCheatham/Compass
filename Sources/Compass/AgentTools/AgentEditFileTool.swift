import Foundation

/// Exact find/replace on an existing UTF-8 text file. The model passes an
/// ordered list of edits; each `oldString` must appear exactly once in the
/// file *at the moment its edit is applied* (or pass `replaceAll: true` to
/// substitute every occurrence). All edits succeed atomically — if any one
/// fails, the file is not written. A prior `read_file` for the path is
/// required so the model is always operating on contents it has actually
/// seen.
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
      case oldString
      case oldStringSnake = "old_string"
      case old
      case find
      case newString
      case newStringSnake = "new_string"
      case replacement
      case replace
      case replaceAll
      case replaceAllSnake = "replace_all"
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
        CodingKeys.oldString,
        .oldStringSnake,
        .old,
        .find,
        .newString,
        .newStringSnake,
        .replacement,
        .replace,
        .replaceAll,
        .replaceAllSnake,
      ].contains { container.contains($0) }
    }
  }

  struct EditOperation: Decodable {
    let oldString: String
    let newString: String
    let replaceAll: Bool?

    enum CodingKeys: String, CodingKey {
      case oldString
      case oldStringSnake = "old_string"
      case old
      case find
      case newString
      case newStringSnake = "new_string"
      case replacement
      case replace
      case replaceAll
      case replaceAllSnake = "replace_all"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      oldString = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .oldString,
        aliases: [.oldStringSnake, .old, .find],
        fieldName: "oldString"
      )
      newString = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .newString,
        aliases: [.newStringSnake, .replacement, .replace],
        fieldName: "newString"
      )
      replaceAll =
        FlexibleModelDecoder.decodeBool(from: container, forKey: .replaceAll)
        ?? FlexibleModelDecoder.decodeBool(from: container, forKey: .replaceAllSnake)
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
            "Ordered list of find/replace operations applied to the file. Each later edit sees the file as transformed by the earlier edits. All edits must succeed; if any fails the file is left unchanged.",
          "items": [
            "type": "object",
            "additionalProperties": false,
            "required": ["oldString", "newString"],
            "properties": [
              "oldString": [
                "type": "string",
                "description":
                  "Exact substring to replace. Must be unique in the file at the time this edit is applied unless replaceAll is true.",
              ],
              "newString": [
                "type": "string",
                "description": "Replacement text. Must be different from oldString.",
              ],
              "replaceAll": [
                "type": "boolean",
                "description":
                  "Replace every occurrence of oldString instead of requiring uniqueness. Defaults to false.",
              ],
            ],
          ],
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Apply one or more exact find/replace edits to a UTF-8 text file. Edits are applied in order against the running file content; each oldString must be unique at its turn unless replaceAll is set. All-or-nothing: a failing edit aborts the whole call without writing.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
    }

    guard !args.edits.isEmpty else {
      return .failure(
        .invalidArguments("edits is empty; pass at least one find/replace operation"))
    }

    for (idx, edit) in args.edits.enumerated() {
      if edit.oldString.isEmpty {
        return .failure(
          .invalidArguments(
            "edits[\(idx)].oldString is empty; use write_file to create a file from scratch"))
      }
      if edit.oldString == edit.newString {
        return .failure(
          .invalidArguments(
            "edits[\(idx)] oldString and newString are identical; no edit needed"))
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
          "edit_file requires a prior read_file for \(context.relativize(url)) in this session. Read the file first so you are editing contents you have actually seen."
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
    if originalData.prefix(8192).contains(0) {
      return .failure(.binaryFile(args.path))
    }

    var current = String(decoding: originalData, as: UTF8.self)
    var totalReplaced = 0
    let relative = context.relativize(url)

    for (idx, edit) in args.edits.enumerated() {
      let occurrences = current.ranges(of: edit.oldString).count
      let replaceAll = edit.replaceAll ?? false

      if occurrences == 0 {
        let hints = nearMissHints(for: edit.oldString, in: current)
        var message = "edits[\(idx)] oldString not found in \(relative)"
        if !hints.isEmpty {
          message += "\nLines that look similar:\n" + hints.joined(separator: "\n")
        }
        return .failure(.editConflict(message))
      }
      if occurrences > 1 && !replaceAll {
        return .failure(
          .editConflict(
            "edits[\(idx)] oldString matches \(occurrences) places in \(relative); include more surrounding context or set replaceAll: true"
          ))
      }

      if replaceAll {
        current = current.replacingOccurrences(of: edit.oldString, with: edit.newString)
        totalReplaced += occurrences
      } else if let range = current.range(of: edit.oldString) {
        current = current.replacingCharacters(in: range, with: edit.newString)
        totalReplaced += 1
      } else {
        return .failure(.editConflict("edits[\(idx)] oldString not found in \(relative)"))
      }
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

    await context.readTracker.markRead(url)
    let editPlural = args.edits.count == 1 ? "" : "s"
    let occPlural = totalReplaced == 1 ? "" : "s"
    return .ok(
      "applied \(args.edits.count) edit\(editPlural) to \(relative); replaced \(totalReplaced) occurrence\(occPlural)"
    )
  }

  /// Best-effort near-miss list when `oldString` is not found. Scores each
  /// file line by its longest common prefix with the first non-blank line of
  /// `oldString` (both trimmed) and returns the top three lines that clear a
  /// minimum threshold. Helps the model re-orient when the snippet drifted
  /// — usually because the file changed — without doing fuzzy matching that
  /// could quietly mask real staleness.
  private func nearMissHints(for oldString: String, in file: String) -> [String] {
    let needle =
      oldString
      .split(whereSeparator: \.isNewline)
      .lazy
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty }
    guard let needle, needle.count >= 8 else { return [] }

    let needleChars = Array(needle)
    let minScore = max(8, needle.count / 4)

    var scored: [(score: Int, lineNumber: Int, raw: String)] = []
    let lines = file.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (idx, line) in lines.enumerated() {
      let raw = String(line)
      let trimmedChars = Array(raw.trimmingCharacters(in: .whitespaces))
      let cap = min(needleChars.count, trimmedChars.count)
      var score = 0
      while score < cap && needleChars[score] == trimmedChars[score] { score += 1 }
      if score >= minScore {
        scored.append((score, idx + 1, raw))
      }
    }
    scored.sort { $0.score > $1.score }
    return scored.prefix(3).map { hit in
      let display = hit.raw.count > 160 ? String(hit.raw.prefix(160)) + "…" : hit.raw
      return "  line \(hit.lineNumber): \(display)"
    }
  }
}

extension String {
  /// Foundation's `ranges(of:)` is Swift 5.7+ but only on String<-->String
  /// search via `Substring` indices, so we implement a small finder that
  /// returns all non-overlapping ranges of `target`.
  fileprivate func ranges(of target: String) -> [Range<String.Index>] {
    guard !target.isEmpty else { return [] }
    var ranges: [Range<String.Index>] = []
    var searchStart = startIndex
    while searchStart < endIndex,
      let found = range(of: target, range: searchStart..<endIndex)
    {
      ranges.append(found)
      searchStart = found.upperBound
    }
    return ranges
  }
}
