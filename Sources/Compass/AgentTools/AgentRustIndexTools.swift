import Foundation

struct AgentFindImplsTool: AgentTool {
  static let toolName = "find_impls"

  struct Arguments: Decodable {
    var trait: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
      case trait
      case type
      case typeName = "type_name"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      trait = try container.decodeIfPresent(String.self, forKey: .trait)
      type =
        (try? container.decodeIfPresent(String.self, forKey: .type))
        ?? (try? container.decodeIfPresent(String.self, forKey: .typeName))
    }
  }

  let spec = AgentToolSpec(
    name: Self.toolName,
    description:
      "Find Rust impl blocks from the cached Rust trait index. Provide `trait`, `type`, or both.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "trait": ["type": "string"],
        "type": ["type": "string"],
      ],
    ])
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    let traitFilter = args.trait?.trimmingCharacters(in: .whitespacesAndNewlines)
    let typeFilter = args.type?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard traitFilter?.isEmpty == false || typeFilter?.isEmpty == false else {
      return .failure(.invalidArguments("provide at least one of `trait` or `type`."))
    }
    let workspace = RustCodemapEnricher.workspace(from: context)
    guard let index = RustCodemapEnricher.loadTraitIndex(workspace: workspace) else {
      return .failure("No Rust trait index found. Refresh the codemap first.", kind: .fileNotFound)
    }
    let matches = index.impls.filter { item in
      (traitFilter.map { item.traitName == $0 } ?? true)
        && (typeFilter.map { item.typeName == $0 } ?? true)
    }
    if matches.isEmpty {
      return .ok("(no impls found)")
    }
    return .ok(
      matches.map { "\($0.file):\($0.line)  impl \($0.traitName) for \($0.typeName)" }.joined(
        separator: "\n"))
  }
}

struct AgentTraitUsersTool: AgentTool {
  static let toolName = "trait_users"

  struct Arguments: Decodable {
    var trait: String
  }

  let spec = AgentToolSpec(
    name: Self.toolName,
    description: "List Rust types implementing a trait from the cached Rust trait index.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["trait"],
      "properties": ["trait": ["type": "string"]],
    ])
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    let traitName = args.trait.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !traitName.isEmpty else {
      return .failure(.invalidArguments("`trait` is empty."))
    }
    let workspace = RustCodemapEnricher.workspace(from: context)
    guard let index = RustCodemapEnricher.loadTraitIndex(workspace: workspace) else {
      return .failure("No Rust trait index found. Refresh the codemap first.", kind: .fileNotFound)
    }
    let matches = index.impls.filter { $0.traitName == traitName }
    if matches.isEmpty {
      return .ok("(no implementers found for \(traitName))")
    }
    return .ok(matches.map { "\($0.typeName)  \($0.file):\($0.line)" }.joined(separator: "\n"))
  }
}
