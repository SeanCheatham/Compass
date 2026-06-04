import Foundation

struct AgentWorkspaceOutlineTool: AgentTool {
  static let toolName = "workspace_outline"
  static let defaultTimeoutMs = 30_000

  struct Arguments: Decodable {
    let refresh: Bool?

    enum CodingKeys: String, CodingKey {
      case refresh
      case forceRefresh = "force_refresh"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      refresh =
        (try? container.decodeIfPresent(Bool.self, forKey: .refresh))
        ?? (try? container.decodeIfPresent(Bool.self, forKey: .forceRefresh))
    }
  }

  let spec: AgentToolSpec

  init() {
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Summarize the Rust Cargo workspace from Compass's cached cargo graph. Use this before reading Cargo.toml files in Rust projects. Pass refresh=true to ask compass-engine for fresh cargo metadata when available.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": false,
        "properties": [
          "refresh": [
            "type": "boolean",
            "description": "When true, refresh the cargo graph through compass-engine before reading it.",
          ]
        ],
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let workspace = CompassWorkspace(
      repoURL: context.workingDirectory,
      storageRootURL: context.codemapStoreDirectory.deletingLastPathComponent()
    )
    let store = CargoGraphStore()
    let snapshot: CargoGraphSnapshot?
    if args.refresh == true {
      snapshot = try await refreshSnapshot(context: context, workspace: workspace, store: store)
    } else {
      if let cached = store.load(from: workspace) {
        snapshot = cached
      } else {
        snapshot = try await refreshSnapshot(context: context, workspace: workspace, store: store)
      }
    }
    guard let snapshot else {
      return .failure(
        "No Cargo graph cache found. Run a codemap refresh or call workspace_outline with refresh=true after building compass-engine.",
        kind: .fileNotFound
      )
    }
    return .ok(Self.format(snapshot.graph, generatedAt: snapshot.generatedAt))
  }

  private func refreshSnapshot(
    context: AgentToolContext,
    workspace: CompassWorkspace,
    store: CargoGraphStore
  ) async throws -> CargoGraphSnapshot? {
    guard let service = context.rustCargoService else {
      return nil
    }
    let data = try await service.run(
      command: .workspaceOutline,
      repoURL: context.workingDirectory,
      arguments: [],
      timeout: TimeInterval(Self.defaultTimeoutMs) / 1_000
    )
    let response = try JSONDecoder().decode(RustEngineResponse<CargoGraphData>.self, from: data)
    guard response.ok, let graph = response.data else {
      return nil
    }
    let snapshot = store.makeSnapshot(graph: graph, workspace: workspace)
    try store.save(snapshot, workspace: workspace)
    return snapshot
  }

  static func format(_ graph: CargoGraphData, generatedAt: Date) -> String {
    var lines: [String] = []
    lines.append("workspace: \(graph.workspaceRoot)")
    lines.append("members: \(graph.members.count)")
    for member in graph.members {
      let deps = member.dependencies.map(\.name).joined(separator: ", ")
      lines.append("  \(member.name) [\(member.kind)]")
      lines.append("    manifest: \(member.manifestPath)")
      lines.append("    src: \(member.srcRoot)")
      if !deps.isEmpty {
        lines.append("    deps: \(deps)")
      }
      let namedFeatures = member.features.named.keys.sorted().joined(separator: ", ")
      if !member.features.default.isEmpty || !namedFeatures.isEmpty {
        lines.append(
          "    features: default[\(member.features.default.joined(separator: ", "))] named[\(namedFeatures)]"
        )
      }
    }
    if !graph.edges.isEmpty {
      lines.append("edges:")
      for edge in graph.edges {
        let flags = [edge.dev ? "dev" : nil, edge.optional ? "optional" : nil]
          .compactMap { $0 }
          .joined(separator: ",")
        lines.append("  \(edge.from) -> \(edge.to)\(flags.isEmpty ? "" : " [\(flags)]")")
      }
    }
    let date = ISO8601DateFormatter().string(from: generatedAt)
    lines.append("generated_at: \(date)")
    return lines.joined(separator: "\n")
  }
}
