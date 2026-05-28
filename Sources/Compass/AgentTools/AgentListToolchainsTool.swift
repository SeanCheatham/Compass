import Foundation

/// Lists predefined Shared VM toolchains and whether each is installed.
struct AgentListToolchainsTool: AgentTool {
  static let toolName = "list_toolchains"

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [:] as [String: Any],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List predefined toolchains in the Compass Shared VM and whether each is installed. Use before install_toolchain to see what is available. Only meaningful when running in the Shared VM.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    guard let service = context.toolchainService else {
      return .ok(
        "Toolchains are only managed in the Compass Shared VM. This run is on the native macOS host."
      )
    }
    do {
      let statuses = try await service.listToolchains(runner: context.bashRunner)
      return .ok(Self.format(statuses))
    } catch {
      return .failure(.rpcFailure(error.localizedDescription))
    }
  }

  static func format(_ statuses: [ToolchainStatus]) -> String {
    var lines: [String] = ["Shared VM toolchains:"]
    for status in statuses {
      let availability = status.installed ? "installed" : "missing"
      let provisioned =
        status.defaultProvisioned ? " (default-provisioned)" : " (on-demand)"
      lines.append("- \(status.id): \(status.displayName) — \(availability)\(provisioned)")
      lines.append("  \(status.description)")
    }
    lines.append("")
    lines.append(
      "Install missing on-demand toolchains with install_toolchain. Default-provisioned toolchains (command_line_tools, homebrew, ripgrep) are installed during VM setup."
    )
    return lines.joined(separator: "\n")
  }
}
