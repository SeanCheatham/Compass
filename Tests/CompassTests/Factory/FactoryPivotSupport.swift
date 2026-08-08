import Foundation
import Testing

@testable import Compass
@testable import CompassCore

// Shared helpers from former FactoryPivotTests.

actor FakeLocalModelRuntime: LocalModelGenerating {
  var outputs: [String]
  var requests: [LocalModelGenerationRequest] = []
  let delayNanoseconds: UInt64

  init(outputs: [String], delayNanoseconds: UInt64 = 0) {
    self.outputs = outputs
    self.delayNanoseconds = delayNanoseconds
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult
  {
    requests.append(request)
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }
    guard !outputs.isEmpty else {
      throw LocalModelRuntimeError.generationFailed("Fake runtime has no queued output.")
    }
    let text = outputs.removeFirst()
    return LocalModelGenerationResult(
      text: text,
      tokenUsage: .estimated(
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: text.count
      )
    )
  }

  func capturedPrompts() -> [String] {
    requests.map(\.prompt)
  }
}

final class RejectFirstPlanSubmitValidator: @unchecked Sendable {
  let lock = NSLock()
  var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt == 1 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify:
          "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

final class RejectFirstTwoPlanSubmitValidator: @unchecked Sendable {
  let lock = NSLock()
  var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt <= 2 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify:
          "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

final class ToolInvocationCounter: @unchecked Sendable {
  let lock = NSLock()
  var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}

final class ToolResultQueue: @unchecked Sendable {
  let lock = NSLock()
  var results: [AgentToolInvocationResult]

  init(_ results: [AgentToolInvocationResult]) {
    self.results = results
  }

  func next() -> AgentToolInvocationResult {
    lock.lock()
    defer { lock.unlock() }
    guard !results.isEmpty else {
      return .failure("Fake bash result queue exhausted.", kind: .unknown)
    }
    return results.removeFirst()
  }
}

struct FakeBashTool: AgentTool {
  var output: String
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentBashTool.toolName,
      description: "Fake bash tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    counter?.increment()
    return .ok(output)
  }
}

struct FakeReadFileTool: AgentTool {
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentReadFileTool.toolName,
      description: "Fake read file tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    counter?.increment()
    return .ok("fake file contents")
  }
}

struct FakeSequencedBashTool: AgentTool {
  var results: ToolResultQueue
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentBashTool.toolName,
      description: "Fake sequenced bash tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    counter?.increment()
    return results.next()
  }
}

func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "CompassFactoryPivotTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func jsonStringLiteral(_ value: String) -> String {
  let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
  return String(decoding: data, as: UTF8.self)
}

func testConfiguration(
  phase: AgentPhase,
  settings: AgentRuntimeSettings = AgentRuntimeSettings(),
  runtime: any LocalModelGenerating,
  tools: [AgentTool],
  workingDirectory: URL,
  submitResultSchema: String,
  maxIterations: Int = 8,
  wallClockTimeout: TimeInterval = 60,
  validateSubmitResult: (@Sendable (Data) throws -> Void)? = nil
) -> AgentExecutionConfiguration {
  AgentExecutionConfiguration(
    settings: settings,
    phase: phase,
    systemPrompt: Prompts.agentSystemPrompt(
      phase: phase,
      workingDirectoryPath: workingDirectory.path,
      executionEnvironment: .host
    ),
    userPrompt: "Test phase packet.",
    tools: tools,
    modelRuntime: runtime,
    submitResultSchema: AgentToolParametersSchema(json: Data(submitResultSchema.utf8)),
    workingDirectory: workingDirectory,
    validateSubmitResult: validateSubmitResult ?? { data in
      switch phase {
      case .plan:
        _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
      case .develop:
        _ = try JSONDecoder().decode(DevelopSummary.self, from: data)
      case .critic:
        _ = try JSONDecoder().decode(CriticVerdict.self, from: data)
      case .requirementsAudit:
        _ = try JSONDecoder().decode(RequirementsAuditResult.self, from: data)
      case .chamber:
        _ = try JSONDecoder().decode(ChamberHuntSubmit.self, from: data)
      }
    },
    maxIterations: maxIterations,
    wallClockTimeout: wallClockTimeout
  )
}
