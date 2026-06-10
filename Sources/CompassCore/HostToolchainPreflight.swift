import Foundation

struct HostToolchainSnapshot: Equatable, Sendable {
  struct Tool: Equatable, Sendable {
    var name: String
    var path: String?
    var version: String?

    var isAvailable: Bool { path != nil }
  }

  var tools: [Tool]

  func tool(named name: String) -> Tool? {
    tools.first { $0.name == name }
  }

  var missingTools: [String] {
    tools.filter { !$0.isAvailable }.map(\.name)
  }

  var isTypeScriptReady: Bool {
    tool(named: "node")?.isAvailable == true
      && tool(named: "npm")?.isAvailable == true
      && tool(named: "corepack")?.isAvailable == true
      && tool(named: "pnpm")?.isAvailable == true
  }
}

enum HostToolchainPreflight {
  static let toolNames = ["node", "npm", "corepack", "pnpm", "tsc"]

  static func snapshot() async -> HostToolchainSnapshot {
    var tools: [HostToolchainSnapshot.Tool] = []
    for name in toolNames {
      let path = await executablePath(name)
      let version = path == nil ? nil : await version(for: name)
      tools.append(HostToolchainSnapshot.Tool(name: name, path: path, version: version))
    }
    return HostToolchainSnapshot(tools: tools)
  }

  static func verifyCommandRequiresPnpm(_ command: String) -> Bool {
    command
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: " ", options: .regularExpression)
      .split(separator: " ")
      .contains("pnpm")
  }

  private static func executablePath(_ name: String) async -> String? {
    guard
      let result = try? await ProcessRunner.run(
        executable: "/usr/bin/env",
        arguments: ["which", name],
        timeout: 5
      ),
      result.exitCode == 0
    else {
      return nil
    }
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }

  private static func version(for name: String) async -> String? {
    guard
      let result = try? await ProcessRunner.run(
        executable: "/usr/bin/env",
        arguments: [name, "--version"],
        timeout: 5
      ),
      result.exitCode == 0
    else {
      return nil
    }
    let version = (result.stdout + result.stderr)
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return version.isEmpty ? nil : version
  }
}
