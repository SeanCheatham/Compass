import Foundation

/// Installs an on-demand toolchain in the Compass Shared VM guest.
struct AgentInstallToolchainTool: AgentTool {
  static let toolName = "install_toolchain"

  static let installableIDs: [String] = SharedVMToolchainCatalog.all
    .filter { !$0.defaultProvisioned && $0.installableViaGenericProvisioner }
    .map(\.stringID)

  struct Arguments: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
      case id
      case toolchain
      case toolchainID
      case toolchainIDSnake = "toolchain_id"
      case name
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .id,
        aliases: [.toolchain, .toolchainID, .toolchainIDSnake, .name],
        fieldName: "id"
      )
    }
  }

  let spec: AgentToolSpec

  init() {
    let idList = Self.installableIDs.joined(separator: ", ")
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["id"],
      "properties": [
        "id": [
          "type": "string",
          "description":
            "Toolchain id to install. Valid on-demand ids: \(idList).",
        ] as [String: Any]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Install a missing on-demand toolchain in the Compass Shared VM. Blocks until installation completes or fails. Dependencies (e.g. homebrew) install automatically when needed. Only meaningful when running in the Shared VM.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    guard let service = context.toolchainService else {
      return .failure(
        "Toolchains are only managed in the Compass Shared VM. This run is on the native macOS host.",
        kind: .invalidArguments
      )
    }

    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    do {
      let id = args.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty else {
        return .failure(.invalidArguments("id is empty"))
      }
      let report = try await service.installToolchain(
        id: id,
        runner: context.bashRunner,
        progress: { _ in }
      )
      if report.alreadyInstalled {
        return .ok("Toolchain \(id) is already installed.")
      }
      var message = "Toolchain \(id) installed successfully."
      if !report.logTail.isEmpty {
        message += "\n\nInstall log tail:\n\(report.logTail)"
      }
      return .ok(message)
    } catch let error as SharedCompassVMToolchainManager.ManagerError {
      return .failure(error.description, kind: .invalidArguments)
    } catch {
      return .failure(.rpcFailure(SharedVMToolchainDiagnostics.describe(error)))
    }
  }
}
