import Foundation

/// Best-effort reverse-lookup: list codemap entries whose imports appear
/// to reference the supplied file. Approximate by design — the codemap
/// stores the literal source string of each `import` / `from`
/// statement, not the resolved path, so this matches loosely against the
/// target file's basename and extensionless path. Useful for the question
/// "who depends on this?" without modeling each language's module
/// resolution rules.
public struct AgentImportersOfTool: AgentTool {
  public static let toolName = "importers_of"
  public static let maxResults = 200

  public struct Arguments: Decodable {
    public let path: String

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case relativePath
      case relativePathSnake = "relative_path"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file, .relativePath, .relativePathSnake],
        fieldName: "path"
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["path"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Repo-relative path of the file to look up importers for. Must match a path the codemap has indexed.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Best-effort reverse import lookup: list files whose import statements reference the target file. Matches against the target's filename and extensionless path — does not resolve aliased imports, package re-exports, or language module hierarchies. Use `grep` to verify a specific call site.",
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
    let normalized = AgentCodemapPath.normalize(
      args.path, workingDirectory: context.workingDirectory)
    guard !normalized.isEmpty else {
      return .failure(.invalidArguments("`path` resolves to an empty string."))
    }
    let store = context.codemapStore()
    guard let target = store.loadEntry(forRelativePath: normalized) else {
      return .failure(
        .invalidArguments(
          "No codemap entry for '\(normalized)'. The reverse lookup needs the target to be indexed too."
        )
      )
    }

    let candidates = Self.candidates(for: target.relativePath)
    let candidateSet = Set(candidates.map { $0.lowercased() })

    var hits: [(importer: String, importLine: Int, raw: String)] = []
    for entry in store.loadAllEntries() where entry.relativePath != target.relativePath {
      for imp in entry.imports {
        let normalizedImport = AgentCodemapPath.normalizeImportSource(imp.raw).lowercased()
        guard !normalizedImport.isEmpty else { continue }
        if candidateSet.contains(normalizedImport) {
          hits.append((importer: entry.relativePath, importLine: imp.line, raw: imp.raw))
        }
      }
    }

    if hits.isEmpty {
      return .ok(
        "No codemap entries import '\(target.relativePath)' via paths this tool can detect. Try `grep` for direct symbol references."
      )
    }
    hits.sort { ($0.importer, $0.importLine) < ($1.importer, $1.importLine) }

    let truncated = hits.count > Self.maxResults
    var lines: [String] = []
    lines.append("importers: \(hits.count)\(truncated ? " (truncated)" : "")")
    for hit in hits.prefix(Self.maxResults) {
      lines.append("  \(hit.importer):\(hit.importLine)  \"\(hit.raw)\"")
    }
    return .ok(lines.joined(separator: "\n"))
  }

  /// Match keys we'll look for in importers. We can't precisely match
  /// across language module-resolution rules, so we generate the
  /// plausible representations and accept any hit. Lowercased by the
  /// caller before set lookup.
  public static func candidates(for relativePath: String) -> [String] {
    let stem = AgentCodemapPath.stripExtension(relativePath)
    let basename = AgentCodemapPath.basenameWithoutExtension(relativePath)
    var values: [String] = [
      relativePath,
      stem,
      basename,
    ]
    // Python-style dotted module: src/foo/bar.py → src.foo.bar / foo.bar.
    let dotted = stem.replacingOccurrences(of: "/", with: ".")
    if dotted != stem { values.append(dotted) }
    // Trailing "/index" for TS/JS packages: src/foo/index.ts is imported
    // as "src/foo" or "./foo".
    if basename == "index" {
      let parent = (stem as NSString).deletingLastPathComponent
      if !parent.isEmpty {
        values.append(parent)
        let parentBase = (parent as NSString).lastPathComponent
        if !parentBase.isEmpty { values.append(parentBase) }
      }
    }
    return values.filter { !$0.isEmpty }
  }
}
