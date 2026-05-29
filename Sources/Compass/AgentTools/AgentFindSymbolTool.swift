import Foundation

/// Locate every codemap entry that defines a symbol with a matching name.
/// Faster than greping for "func foo" / "class Foo" — the codemap already
/// knows what's a declaration vs. a reference.
struct AgentFindSymbolTool: AgentTool {
  static let toolName = "find_symbol"
  static let maxResults = 100

  struct Arguments: Codable {
    let name: String
    let kind: String?
  }

  let spec: AgentToolSpec

  init() {
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

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
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

extension CodemapSymbolKind {
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
