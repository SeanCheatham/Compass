import Foundation

/// Locate every codemap entry that defines a symbol with a matching name.
/// Faster than greping for "func foo" / "class Foo" — the codemap already
/// knows what's a declaration vs. a reference.
public struct AgentFindSymbolTool: AgentTool {
  public static let toolName = "find_symbol"
  public static let maxResults = 100

  public struct Arguments: Decodable {
    public let name: String
    public let kind: String?

    public enum CodingKeys: String, CodingKey {
      case name
      case symbol
      case symbolName
      case symbolNameSnake = "symbol_name"
      case query
      case kind
      case symbolKind
      case symbolKindSnake = "symbol_kind"
      case type
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .name,
        aliases: [.symbol, .symbolName, .symbolNameSnake, .query],
        fieldName: "name"
      )
      kind = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .kind,
        aliases: [.symbolKind, .symbolKindSnake, .type]
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let kindValues = CodemapSymbolKind.allRawValues
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["name"],
      "properties": [
        "name": [
          "type": "string",
          "description":
            "Exact symbol name (case-sensitive). Use `outline`/`grep` first if you only have a partial name.",
        ],
        "kind": [
          "type": "string",
          "enum": kindValues,
          "description":
            "Optional symbol kind to narrow the match (e.g. `class`, `function`, `method`).",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Find every codemap entry that declares a symbol with the given name. Returns repo-relative path, line, and kind for each match. Capped at 100 results.",
      parameters: schema
    )
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    let targetName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !targetName.isEmpty else {
      return .failure(.invalidArguments("name must be non-empty"))
    }
    let kindFilter: CodemapSymbolKind?
    if let kindRaw = args.kind?.trimmingCharacters(in: .whitespacesAndNewlines),
      !kindRaw.isEmpty
    {
      guard let resolved = CodemapSymbolKind(rawValue: kindRaw) else {
        return .failure(
          "Unknown kind '\(kindRaw)'. Allowed: \(CodemapSymbolKind.allRawValues.joined(separator: ", "))."
        )
      }
      kindFilter = resolved
    } else {
      kindFilter = nil
    }

    let store = context.codemapStore()
    var matches: [(path: String, symbol: CodemapSymbol)] = []
    for entry in store.loadAllEntries() {
      for symbol in entry.symbols where symbol.name == targetName {
        if let kindFilter, symbol.kind != kindFilter { continue }
        matches.append((path: entry.relativePath, symbol: symbol))
      }
    }

    if matches.isEmpty {
      var hint = "No codemap symbol named '\(targetName)'"
      if let kindFilter { hint += " with kind \(kindFilter.rawValue)" }
      hint +=
        ". The codemap only sees declarations the parser recognizes; try `grep` for references."
      return .ok(hint)
    }

    matches.sort {
      ($0.path, $0.symbol.line) < ($1.path, $1.symbol.line)
    }

    var lines: [String] = []
    lines.append(
      "matches: \(matches.count)\(matches.count > Self.maxResults ? " (truncated)" : "")")
    for match in matches.prefix(Self.maxResults) {
      lines.append("  \(match.path):\(match.symbol.line)  \(match.symbol.kind.rawValue)")
    }
    return .ok(lines.joined(separator: "\n"))
  }
}

public extension CodemapSymbolKind {
  /// JSON-Schema-friendly list of allowed `kind` values for tool input
  /// validation. Stable order so the schema diff stays minimal across
  /// builds.
  static var allRawValues: [String] {
    [
      "function", "method", "class", "interface", "struct", "enum",
      "trait", "module", "type", "property", "macro", "impl",
      "extension", "constant",
    ]
  }
}
