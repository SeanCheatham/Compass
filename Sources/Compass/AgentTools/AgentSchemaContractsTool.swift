import Foundation

struct AgentSchemaContractsTool: AgentTool {
  static let toolName = "schema_contracts"

  struct Arguments: Decodable {
    var schema: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
      case schema
      case type
      case rustType = "rust_type"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schema = try container.decodeIfPresent(String.self, forKey: .schema)
      type =
        (try? container.decodeIfPresent(String.self, forKey: .type))
        ?? (try? container.decodeIfPresent(String.self, forKey: .rustType))
    }
  }

  let spec = AgentToolSpec(
    name: Self.toolName,
    description:
      "Read cached mappings between JSON Schema files under schemas/ and Rust types. Use before changing persisted state or schema-backed Rust structs.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "schema": ["type": "string", "description": "Optional schema path/title filter."],
        "type": ["type": "string", "description": "Optional Rust type filter."],
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
    let workspace = RustCodemapEnricher.workspace(from: context)
    guard var contracts = SchemaContractsStore().load(from: workspace)?.contracts else {
      return .failure(
        "No schema contracts cache found. Refresh the codemap first.", kind: .fileNotFound)
    }
    if let schema = args.schema?.trimmingCharacters(in: .whitespacesAndNewlines), !schema.isEmpty {
      contracts = contracts.filter {
        $0.schemaPath.localizedCaseInsensitiveContains(schema)
          || $0.schemaTitle.localizedCaseInsensitiveContains(schema)
      }
    }
    if let type = args.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
      contracts = contracts.filter { $0.rustType == type }
    }
    if contracts.isEmpty {
      return .ok("(no schema contracts found)")
    }
    return .ok(contracts.map(Self.format).joined(separator: "\n"))
  }

  private static func format(_ contract: SchemaContract) -> String {
    let target =
      contract.rustType.map { rustType in
        "\(rustType) @ \(contract.rustFile ?? "?"):\(contract.line.map(String.init) ?? "?")"
      } ?? "(no Rust type linked)"
    let fields = contract.fieldMapping
      .map { "\($0.schemaField)->\($0.rustField)" }
      .joined(separator: ", ")
    return
      "\(contract.schemaPath) (\(contract.schemaTitle)) -> \(target) [\(contract.confidence)]\(fields.isEmpty ? "" : " fields: \(fields)")"
  }
}
