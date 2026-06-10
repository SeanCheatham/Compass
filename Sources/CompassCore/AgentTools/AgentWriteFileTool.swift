import Foundation

/// Create a UTF-8 text file. Intermediate directories are
/// created automatically. The model uses this for net-new files; existing file
/// edits should go through `AgentEditFileTool`, which preserves the rest of
/// the file and uses line ranges from `read_file`.
struct AgentWriteFileTool: AgentTool {
  static let toolName = "write_file"

  struct Arguments: Decodable {
    let path: String
    let content: String

    enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case content
      case contents
      case text
      case body
    }

    init(from decoder: Decoder) throws {
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

  let spec: AgentToolSpec

  init() {
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

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
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
      let wholeFileRange: String
      if let lineCount = await context.readTracker.lineCount(for: url) {
        wholeFileRange = "startLine=1, endLine=\(lineCount)"
      } else {
        wholeFileRange = "startLine=1, endLine=<last line from read_file>"
      }
      let guidance =
        "write_file refused to overwrite \(relative) because it already exists. Use edit_file for existing files. \(wasRead ? "Use the line numbers from the prior read_file" : "Call read_file on \(relative) first"), then call edit_file with startLine/endLine and replacement lines. For a whole-file replacement, use edit_file with \(wholeFileRange)."
      if wasRead {
        return .failure(.invalidArguments(guidance))
      }
      return .failure(
        .readNotTracked(
          guidance
        ))
    }
    if existing == nil,
      let conflict = await packageEntryPointConflict(forNewURL: url, context: context)
    {
      return .failure(
        .invalidArguments(
          "write_file refused to create \(context.relativize(url)) because \(conflict.manifestPath) \(conflict.field) already points at existing entry point \(conflict.declaredPath). Edit \(conflict.declaredPath) instead, or update the manifest to point at \(context.relativize(url)) before creating a replacement entry point."
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
      Self.isSourceFile(url),
      let unsupportedVitestImport = Self.unsupportedVitestJestImport(in: args.content)
    {
      let relative = context.relativize(url)
      return .failure(
        .invalidArguments(
          "write_file refused to create \(relative) because \(unsupportedVitestImport) is not a Vitest package import. Use `import { describe, expect, it } from \"vitest\"` or `import { describe, expect, test } from \"vitest\"` instead."
        ))
    }
    if existing == nil,
      Self.isSourceFile(url),
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
      Self.isSourceFile(url),
      let placeholder = Self.placeholderImplementationMarker(in: args.content)
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

  private struct PackageEntryPointConflict {
    let manifestPath: String
    let declaredPath: String
    let field: String
  }

  private func packageEntryPointConflict(forNewURL url: URL, context: AgentToolContext) async
    -> PackageEntryPointConflict?
  {
    guard isEntryPointAlias(url) else { return nil }
    let workingDirectory = context.workingDirectory.standardizedFileURL
    let workingPath = workingDirectory.path
    var candidate = url.deletingLastPathComponent().standardizedFileURL

    while candidate.path.hasPrefix(workingPath) {
      let manifestURL = candidate.appending(path: "package.json")
      if let data = try? await context.filesystem.readFile(at: manifestURL),
        let entryPoints = packageEntryPoints(from: data)
      {
        for entryPoint in entryPoints {
          let entryURL = candidate.appending(path: entryPoint.path).standardizedFileURL
          guard entryURL.path != url.standardizedFileURL.path,
            let metadata = try? await context.filesystem.metadata(of: entryURL),
            metadata.isRegularFile
          else {
            continue
          }
          return PackageEntryPointConflict(
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

  private func packageEntryPoints(from data: Data) -> [(field: String, path: String)]? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    var entryPoints: [(field: String, path: String)] = []
    for field in ["main", "module", "browser", "types", "typings"] {
      if let raw = object[field] as? String,
        let normalized = normalizedPackageEntryPoint(raw)
      {
        entryPoints.append((field, normalized))
      }
    }
    if let raw = object["bin"] as? String,
      let normalized = normalizedPackageEntryPoint(raw)
    {
      entryPoints.append(("bin", normalized))
    } else if let bin = object["bin"] as? [String: Any] {
      for key in bin.keys.sorted() {
        if let raw = bin[key] as? String,
          let normalized = normalizedPackageEntryPoint(raw)
        {
          entryPoints.append(("bin.\(key)", normalized))
        }
      }
    }
    return entryPoints
  }

  private func normalizedPackageEntryPoint(_ raw: String) -> String? {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, !path.hasPrefix("#"), !path.contains("://") else { return nil }
    while path.hasPrefix("./") {
      path.removeFirst(2)
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.isEmpty, !path.hasPrefix("../") else { return nil }
    return path
  }

  private struct SelfRelativeModuleReference {
    let specifier: String
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

  private struct PlaceholderImplementationMarker {
    let lineNumber: Int
    let preview: String
  }

  private struct EmptyOrCommentOnlySourceContent {
    let preview: String
  }

  private static func unsupportedVitestJestImport(in text: String) -> String? {
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("import ") else { continue }
      for pattern in [
        #"from\s+["'](@?vitest/jest)["']"#,
        #"^\s*import\s+["'](@?vitest/jest)["']"#,
      ] {
        if let specifier = firstCapture(in: trimmed, pattern: pattern) {
          return "`\(specifier)`"
        }
      }
    }
    return nil
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

    let firstLine = trimmed.components(separatedBy: "\n").first?
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

  private static func placeholderImplementationMarker(in text: String)
    -> PlaceholderImplementationMarker?
  {
    text.components(separatedBy: "\n").enumerated().compactMap { offset, line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard looksLikePlaceholderImplementation(trimmed.lowercased()) else { return nil }
      return PlaceholderImplementationMarker(
        lineNumber: offset + 1,
        preview: "`\(String(trimmed.prefix(120)))`"
      )
    }.first
  }

  private static func looksLikePlaceholderImplementation(_ lowercasedLine: String) -> Bool {
    (lowercasedLine.contains("todo")
      && (lowercasedLine.contains("implement") || lowercasedLine.contains("placeholder")))
      || lowercasedLine.contains("not implemented")
      || lowercasedLine.contains("unimplemented")
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
    message += visibleEntries.prefix(12).map { "\n- \($0)" }.joined()
    if visibleEntries.count > 12 {
      message += "\n- ... \(visibleEntries.count - 12) more"
    }
    message +=
      "\nIf the plan was to update one of those files, stop using \(context.relativize(url)) and use read_file/edit_file on the existing path instead."
    return message
  }
}
