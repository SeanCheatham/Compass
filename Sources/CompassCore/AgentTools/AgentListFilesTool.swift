import Foundation

/// Enumerate source files currently in the codemap plus live source files
/// that may have been created after the last codemap refresh, optionally
/// narrowed by a substring or glob-like filter on the relative path. The
/// output is one path per line with the detected language so the model can
/// quickly find candidates without paging through `glob`.
public struct AgentListFilesTool: AgentTool {
  public static let toolName = "list_files"
  public static let maxResults = 500
  public static let liveWalkCap = 20_000

  public struct Arguments: Decodable {
    public let filter: String?

    public enum CodingKeys: String, CodingKey {
      case filter
      case query
      case search
      case path
      case directory
      case dir
      case pattern
      case glob
      case file
      case filename
      case fileName
      case fileNameSnake = "file_name"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      filter = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .filter,
        aliases: [
          .query, .search, .path, .directory, .dir, .pattern, .glob, .file, .filename,
          .fileName, .fileNameSnake,
        ]
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "filter": [
          "type": "string",
          "description":
            "Optional case-insensitive substring or glob-like filter on the relative path. Supports common extension groups like `**/*.{ts,tsx}` and `**/*.(ts|tsx)`. Omit to list every known source file.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Codemap source inventory: repo-relative source paths with detected language (includes freshly created files not yet indexed). Prefer this over `glob`/`ls` when you need language-tagged source candidates. Use `filter` for a substring or glob-like path pattern. Prefer `ls` for one directory's entries and `glob` for raw filesystem pattern search. Capped at 500 results.",
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
    let filter = args.filter?.trimmingCharacters(in: .whitespacesAndNewlines)
    var entriesByPath = Dictionary(
      uniqueKeysWithValues: context.codemapStore().loadAllEntries().map { entry in
        (
          entry.relativePath,
          ListedFile(
            relativePath: entry.relativePath,
            language: entry.language,
            symbolCount: entry.symbols.count
          )
        )
      })
    for liveEntry in await Self.liveSourceFiles(context: context)
    where entriesByPath[liveEntry.relativePath] == nil {
      entriesByPath[liveEntry.relativePath] = liveEntry
    }

    var entries = Array(entriesByPath.values)
    let filterVariants = filter.map(Self.filterVariants) ?? []
    if let filter, !filter.isEmpty {
      entries = entries.filter { entry in
        filterVariants.contains { Self.path(entry.relativePath, matchesFilter: $0) }
      }
    }
    entries.sort { $0.relativePath < $1.relativePath }
    if entries.isEmpty {
      let suffix = (filter.flatMap { $0.isEmpty ? nil : " matching '\($0)'" }) ?? ""
      return .ok(
        "(no source files\(suffix))\(Self.emptyResultHint(for: filter, variants: filterVariants))")
    }

    let truncated = entries.count > Self.maxResults
    let shown = entries.prefix(Self.maxResults)
    var lines: [String] = []
    lines.append("files: \(entries.count)\(truncated ? " (truncated)" : "")")
    if let filter, let note = Self.normalizedFilterNote(original: filter, variants: filterVariants)
    {
      lines.append("matched normalized filters: \(note)")
    }
    for entry in shown {
      if let count = entry.symbolCount {
        lines.append("  \(entry.relativePath)  [\(entry.language.displayName), \(count) symbol(s)]")
      } else {
        lines.append("  \(entry.relativePath)  [\(entry.language.displayName), unindexed]")
      }
    }
    return .ok(lines.joined(separator: "\n"))
  }

  private struct ListedFile {
    public let relativePath: String
    public let language: CodemapLanguage
    public let symbolCount: Int?
  }

  private static func liveSourceFiles(context: AgentToolContext) async -> [ListedFile] {
    guard
      let matches = try? await context.filesystem.glob(
        pattern: "**/*",
        under: context.workingDirectory,
        walkCap: liveWalkCap
      )
    else {
      return []
    }

    return matches.compactMap { match in
      let relativePath = context.relativize(match.url)
      guard RepositoryWalkRules.shouldInclude(relativePath: relativePath),
        let language = CodemapLanguage.forRelativePath(relativePath)
      else {
        return nil
      }
      return ListedFile(
        relativePath: relativePath,
        language: language,
        symbolCount: nil
      )
    }
  }

  private static func filterVariants(for filter: String) -> [String] {
    var variants = [filter]
    variants.append(
      contentsOf: expandExtensionAlternation(in: filter, opener: ".(", closer: ")", separator: "|"))
    variants.append(
      contentsOf: expandExtensionAlternation(in: filter, opener: ".{", closer: "}", separator: ","))

    var seen = Set<String>()
    return variants.filter { variant in
      let normalized = variant.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { return false }
      return seen.insert(normalized).inserted
    }
  }

  private static func expandExtensionAlternation(
    in filter: String,
    opener: String,
    closer: Character,
    separator: Character
  ) -> [String] {
    guard let openRange = filter.range(of: opener),
      let closeIndex = filter[openRange.upperBound...].firstIndex(of: closer)
    else {
      return []
    }

    let body = filter[openRange.upperBound..<closeIndex]
    let extensions =
      body
      .split(separator: separator)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0.allSatisfy(isExtensionCharacter) }
    guard extensions.count > 1 else { return [] }

    let prefix = String(filter[..<openRange.lowerBound])
    let suffix = String(filter[filter.index(after: closeIndex)...])
    return extensions.map { "\(prefix).\($0)\(suffix)" }
  }

  private static func isExtensionCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_" || character == "-"
      || character == "+"
  }

  private static func normalizedFilterNote(original: String, variants: [String]) -> String? {
    let expanded = variants.filter { $0 != original }
    guard !expanded.isEmpty else { return nil }
    return expanded.joined(separator: ", ")
  }

  private static func emptyResultHint(for filter: String?, variants: [String]) -> String {
    guard let filter, !filter.isEmpty else { return "" }

    var hints: [String] = []
    if let note = normalizedFilterNote(original: filter, variants: variants) {
      hints.append("tried normalized filters: \(note)")
    }
    if let broad = broadDirectoryHint(for: filter) {
      hints.append("try a broader filter such as '\(broad)'")
    }
    guard !hints.isEmpty else { return "" }
    return "\nHint: \(hints.joined(separator: "; "))."
  }

  private static func broadDirectoryHint(for filter: String) -> String? {
    let wildcardIndex = filter.firstIndex { $0 == "*" || $0 == "?" }
    let prefix = wildcardIndex.map { String(filter[..<$0]) } ?? filter
    let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmed.isEmpty else { return nil }
    if wildcardIndex == nil {
      let parts = trimmed.split(separator: "/")
      if parts.count > 1 {
        return parts.dropLast().joined(separator: "/")
      }
    }
    return trimmed
  }

  private static func path(_ path: String, matchesFilter filter: String) -> Bool {
    let lowercasedPath = path.lowercased()
    let lowercasedFilter = filter.lowercased()
    if lowercasedPath.contains(lowercasedFilter) {
      return true
    }

    guard filter.contains("*") || filter.contains("?") else {
      return false
    }
    if matchesGlob(lowercasedPath, pattern: lowercasedFilter) {
      return true
    }
    if !filter.contains("/") {
      return matchesGlob(lowercasedPath, pattern: "**/\(lowercasedFilter)")
    }
    return false
  }

  private static func matchesGlob(_ path: String, pattern: String) -> Bool {
    guard let regex = try? AgentGlobPattern.regex(forGlob: pattern) else {
      return false
    }
    let range = NSRange(location: 0, length: (path as NSString).length)
    return regex.firstMatch(in: path, options: [], range: range) != nil
  }
}
