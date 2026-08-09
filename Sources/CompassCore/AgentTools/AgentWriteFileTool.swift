import Foundation

/// Create a UTF-8 text file. Intermediate directories are
/// created automatically. The model uses this for net-new files; existing file
/// edits should go through `AgentEditFileTool`, which preserves the rest of
/// the file and uses line ranges from `read_file`.
public struct AgentWriteFileTool: AgentTool {
  public static let toolName = "write_file"

  public struct Arguments: Decodable {
    public let path: String
    public let content: String

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case content
      case contents
      case text
      case body
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file],
        fieldName: "path"
      )
      content = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .content,
        aliases: [.contents, .text, .body],
        fieldName: "content"
      )
    }
  }

  private struct EditFileRepairPayload: Encodable {
    public let path: String
    public let edits: [EditFileRepairEdit]
  }

  private struct EditFileRepairEdit: Encodable {
    public let oldString: String
    public let newString: String

    enum CodingKeys: String, CodingKey {
      case oldString = "old_string"
      case newString = "new_string"
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["path", "content"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Destination path. May be absolute (must resolve inside the working directory) or relative to it. Intermediate directories are created automatically.",
        ],
        "content": [
          "type": "string",
          "description":
            "UTF-8 contents for a new file. Existing files are refused; use edit_file.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Create a new UTF-8 text file at the given path. Intermediate directories are created. Use `edit_file` for existing files.",
      parameters: schema
    )
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let existing: FileMetadata?
    do {
      existing = try await context.filesystem.metadata(of: url)
    } catch let error as AgentFilesystemError {
      return .failure(.ioFailure(error.errorDescription ?? "stat failed"))
    } catch {
      return .failure(.ioFailure("stat failed: \(error.localizedDescription)"))
    }
    if let existing, existing.isRegularFile {
      let relative = context.relativize(url)
      let wasRead = await context.readTracker.wasRead(url)
      let repairHint = Self.editFileRepairHint(
        relativePath: relative,
        content: args.content
      )
      let guidance =
        "write_file refused to overwrite \(relative) because it already exists. Use edit_file for existing files. \(wasRead ? "Reuse text from the prior read_file" : "Call read_file on \(relative) first"), then call edit_file with exact old_string/new_string replacements (old_string must match the current file uniquely).\(repairHint)"
      if wasRead {
        return .failure(.invalidArguments(guidance))
      }
      return .failure(
        .readNotTracked(
          guidance
        ))
    }
    if existing == nil,
      let conflict = await crateEntryPointConflict(forNewURL: url, context: context)
    {
      return .failure(
        .invalidArguments(
          "write_file refused to create \(context.relativize(url)) because \(conflict.manifestPath) \(conflict.field) already points at existing entry point \(conflict.declaredPath). Edit \(conflict.declaredPath) instead, or update the crate manifest before creating a replacement binary entry point."
        ))
    }
    if existing == nil,
      let selfReference = Self.selfRelativeModuleReference(in: args.content, sourceURL: url)
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because its content imports or exports self-referential relative module \(selfReference.specifier). A file cannot import or export from itself; define the symbol directly in \(relative), or import it from a different existing module."
        ))
    }
    if existing == nil,
      AgentEditSafety.isSourceFile(url),
      url.pathExtension.lowercased() == "rs",
      !AgentEditSafety.isTestFile(url),
      let inappropriateTest = AgentEditSafety.inappropriateBareRustTestCode(in: args.content)
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because \(inappropriateTest). Do not paste bare `#[test]` functions or `mod tests` blocks into production crate sources. Put tests in `crates/*/tests/` integration files, or wrap unit tests in `#[cfg(test)] mod tests { ... }`."
        ))
    }
    if existing == nil,
      AgentEditSafety.isSourceFile(url),
      let missingReference = await Self.missingRelativeModuleReference(
        in: args.content,
        sourceURL: url,
        context: context
      )
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because its content imports unresolved relative module \(missingReference.specifier). Compass could not find \(missingReference.expectedDescription). Create the referenced module first, use an existing relative path, or define the implementation directly in \(relative)."
        ))
    }
    if existing == nil,
      AgentEditSafety.isSourceFile(url),
      let skeleton = Self.emptyOrCommentOnlySourceContent(
        in: args.content,
        pathExtension: url.pathExtension
      )
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because source files cannot be empty or comment-only: \(skeleton.preview). Provide the complete implementation in this write_file call, including imports/exports/functions/classes/tests as needed, or submit status=failed/status=blocked if you cannot."
        ))
    }
    if existing == nil,
      AgentEditSafety.isSourceFile(url),
      let placeholder = AgentEditSafety.newPlaceholderImplementationMarker(
        originalText: "",
        editedText: args.content
      )
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because line \(placeholder.lineNumber) looks like placeholder implementation code: \(placeholder.preview). Do not leave TODO/not-implemented placeholders in source files; provide the complete implementation now, or submit status=failed/status=blocked if you cannot."
        ))
    }
    let newFileSiblingHint: String?
    if existing == nil {
      newFileSiblingHint = await newFileHint(for: url, context: context)
    } else {
      newFileSiblingHint = nil
    }

    let data = Data(args.content.utf8)
    do {
      try await context.filesystem.writeFile(data, at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notRegularFile:
        return .failure(.notRegularFile(args.path))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
      }
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }

    await context.readTracker.markRead(url)
    let relative = context.relativize(url)
    var message =
      "created \(relative) (\(data.count) bytes)\nFuture changes to \(relative) must use read_file/edit_file; write_file only creates new files."
    if let newFileSiblingHint {
      message += "\n\(newFileSiblingHint)"
    }
    return .ok(message)
  }

  private struct CrateEntryPointConflict {
    public let manifestPath: String
    public let declaredPath: String
    public let field: String
  }

  private func crateEntryPointConflict(forNewURL url: URL, context: AgentToolContext) async
    -> CrateEntryPointConflict?
  {
    guard isEntryPointAlias(url) else { return nil }
    let workingDirectory = context.workingDirectory.standardizedFileURL
    let workingPath = workingDirectory.path
    var candidate = url.deletingLastPathComponent().standardizedFileURL

    while candidate.path.hasPrefix(workingPath) {
      let manifestURL = candidate.appending(path: "Cargo.toml")
      if let metadata = try? await context.filesystem.metadata(of: manifestURL),
        metadata.isRegularFile
      {
        for entryPoint in Self.defaultCrateEntryPoints {
          let entryURL = candidate.appending(path: entryPoint.path).standardizedFileURL
          guard entryURL.path != url.standardizedFileURL.path,
            let entryMeta = try? await context.filesystem.metadata(of: entryURL),
            entryMeta.isRegularFile
          else {
            continue
          }
          return CrateEntryPointConflict(
            manifestPath: context.relativize(manifestURL),
            declaredPath: context.relativize(entryURL),
            field: entryPoint.field
          )
        }
      }

      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private func isEntryPointAlias(_ url: URL) -> Bool {
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
    return ["app", "cli", "index", "main", "server"].contains(stem)
  }

  private static let defaultCrateEntryPoints: [(field: String, path: String)] = [
    ("bin", "src/main.rs"),
    ("lib", "src/lib.rs"),
  ]

  private static func editFileRepairHint(
    relativePath: String,
    content: String
  ) -> String {
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return ""
    }
    let payload = EditFileRepairPayload(
      path: relativePath,
      edits: [
        EditFileRepairEdit(
          oldString: "<paste the full current file contents from read_file here>",
          newString: content
        )
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return """

      To replace the existing file with the attempted content, return `edit_file` with these arguments (set old_string to the exact current file text):
      ```json
      \(json)
      ```
      """
  }

  private struct SelfRelativeModuleReference {
    public let specifier: String
  }

  private struct MissingRelativeModuleReference {
    public let specifier: String
    public let expectedDescription: String
  }

  private static func selfRelativeModuleReference(
    in text: String,
    sourceURL: URL
  ) -> SelfRelativeModuleReference? {
    for specifier in relativeModuleReferences(in: text) {
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

  private static func missingRelativeModuleReference(
    in text: String,
    sourceURL: URL,
    context: AgentToolContext
  ) async -> MissingRelativeModuleReference? {
    for specifier in relativeModuleReferences(in: text) {
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

  private static func relativeModuleReferences(in text: String) -> Set<String> {
    var references: Set<String> = []
    for line in text.components(separatedBy: "\n") {
      if let name = firstCapture(in: line, pattern: #"^\s*(?:pub\s+)?mod\s+(\w+)\s*;"#) {
        references.insert(name)
      }
      if let name = firstCapture(in: line, pattern: #"^\s*use\s+super::(\w+)"#) {
        references.insert(name)
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
    if !baseURL.pathExtension.isEmpty {
      return [baseURL]
    }
    return [
      baseURL.appendingPathExtension("rs"),
      baseURL.appending(path: "mod.rs"),
      baseURL,
    ]
  }

  private struct EmptyOrCommentOnlySourceContent {
    public let preview: String
  }

  private static func emptyOrCommentOnlySourceContent(
    in text: String,
    pathExtension: String
  ) -> EmptyOrCommentOnlySourceContent? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return EmptyOrCommentOnlySourceContent(preview: "empty content")
    }

    let stripped = sourceTextWithoutComments(trimmed, pathExtension: pathExtension)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard stripped.isEmpty else { return nil }

    let firstLine =
      trimmed.components(separatedBy: "\n").first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return EmptyOrCommentOnlySourceContent(
      preview: "`\(String(firstLine.prefix(120)))`"
    )
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
    if [
      "c", "cc", "cpp", "css", "go", "h", "hpp", "js", "jsx", "mjs", "mts", "rs", "swift",
      "ts", "tsx",
    ].contains(ext) {
      stripped = replacingMatches(
        in: stripped,
        pattern: #"/\*.*?\*/"#,
        options: [.dotMatchesLineSeparators]
      )
      stripped = replacingMatches(in: stripped, pattern: #"(?m)//.*$"#)
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

  private func newFileHint(for url: URL, context: AgentToolContext) async -> String? {
    let parent = url.deletingLastPathComponent().standardizedFileURL
    guard let entries = try? await context.filesystem.listDirectory(at: parent) else {
      return nil
    }
    let targetName = url.lastPathComponent
    let visibleEntries =
      entries
      .map { entry in entry.isDirectory ? "\(entry.name)/" : entry.name }
      .filter { !$0.hasPrefix(".") && $0 != targetName }
      .sorted()
    guard !visibleEntries.isEmpty else { return nil }

    var message =
      "Created a new file in existing directory \(context.relativize(parent)). Existing entries there before this write:"
    message += AgentToolMessageFormat.directoryEntriesPreview(visibleEntries)
    message +=
      "\nIf the plan was to update one of those files, stop using \(context.relativize(url)) and use read_file/edit_file on the existing path instead."
    return message
  }
}
