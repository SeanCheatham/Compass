import Foundation

/// Enumerate every file currently in the codemap, optionally narrowed by a
/// substring or glob-like filter on the relative path. The output is one
/// path per line with the detected language so the model can quickly find
/// candidates without paging through `glob`.
struct AgentListFilesTool: AgentTool {
  static let toolName = "list_files"
  static let maxResults = 500

  struct Arguments: Decodable {
    let filter: String?

    enum CodingKeys: String, CodingKey {
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

    init(from decoder: Decoder) throws {
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

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "filter": [
          "type": "string",
          "description":
            "Optional case-insensitive substring or glob-like filter on the relative path. Supports common extension groups like `**/*.{ts,tsx}` and `**/*.(ts|tsx)`. Omit to list every indexed file.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List the repo-relative paths the codemap has indexed, with each file's detected language. Use a `filter` substring or glob-like pattern to narrow to a subdirectory or filename. Common extension groups like `**/*.{ts,tsx}` and `**/*.(ts|tsx)` are accepted. Capped at 500 results.",
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
    let filter = args.filter?.trimmingCharacters(in: .whitespacesAndNewlines)
    let store = context.codemapStore()
    var entries = store.loadAllEntries()
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
        "(no codemap files\(suffix))\(Self.emptyResultHint(for: filter, variants: filterVariants))")
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
      let count = entry.symbols.count
      lines.append("  \(entry.relativePath)  [\(entry.language.displayName), \(count) symbol(s)]")
    }
    return .ok(lines.joined(separator: "\n"))
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
