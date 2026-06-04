import Foundation

struct AgentCoverageGapsTool: AgentTool {
  static let toolName = "coverage_gaps"

  struct Arguments: Decodable {
    var package: String?
    var timeoutMs: Int?
  }

  let spec = AgentToolSpec(
    name: Self.toolName,
    description:
      "Run cargo-llvm-cov through compass-engine and summarize coverage gaps for Rust projects.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "package": ["type": "string"],
        "timeoutMs": ["type": "integer", "minimum": 1, "maximum": 1_800_000],
      ],
    ])
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    guard let service = context.rustCargoService else {
      return .failure("Rust cargo tools are not enabled for this project.", kind: .invalidArguments)
    }
    var commandArgs: [String] = []
    if let package = args.package?.trimmingCharacters(in: .whitespacesAndNewlines), !package.isEmpty {
      commandArgs += ["--package", package]
    }
    do {
      let data = try await service.run(
        command: .coverageGaps,
        repoURL: context.workingDirectory,
        arguments: commandArgs,
        timeout: TimeInterval(args.timeoutMs ?? 120_000) / 1_000
      )
      let response = try JSONDecoder().decode(RustEngineResponse<CoverageGapsData>.self, from: data)
      guard response.ok, let payload = response.data else {
        return .failure(response.errors.joined(separator: "\n"), kind: .bashFailure)
      }
      var lines = ["overall line coverage: \(String(format: "%.1f", payload.overallLinePercent))%"]
      for file in payload.files.prefix(30) {
        lines.append("- \(file.path): \(String(format: "%.1f", file.linePercent))% uncovered \(file.uncoveredLines.prefix(40).map(String.init).joined(separator: ","))")
      }
      if !payload.logTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("[log tail]\n\(payload.logTail)")
      }
      return .ok(lines.joined(separator: "\n"))
    } catch {
      return .failure(error.localizedDescription, kind: .bashFailure)
    }
  }
}

struct AgentVisualVerifyTool: AgentTool {
  static let toolName = "visual_verify"

  let spec = AgentToolSpec(
    name: Self.toolName,
    description:
      "Run Rust desktop visual verification through compass-engine. Develop-only; returns screenshot path/log tail, not screenshot bytes.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [:],
    ])
  )

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    guard let service = context.rustCargoService else {
      return .failure("Rust cargo tools are not enabled for this project.", kind: .invalidArguments)
    }
    do {
      let data = try await service.run(
        command: .visualVerify,
        repoURL: context.workingDirectory,
        arguments: [],
        timeout: 120
      )
      let response = try JSONDecoder().decode(RustEngineResponse<VisualVerifyData>.self, from: data)
      guard response.ok, let payload = response.data else {
        return .failure(response.errors.joined(separator: "\n"), kind: .bashFailure)
      }
      let status = payload.ok ? "passed" : "failed"
      return .ok(
        """
        visual_verify: \(status)
        screenshot_path: \(payload.screenshotPath ?? "(none)")
        log_tail:
        \(payload.logTail)
        """
      )
    } catch {
      return .failure(error.localizedDescription, kind: .bashFailure)
    }
  }
}
