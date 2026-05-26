import Foundation
import FoundationModels

/// On-device text runtime backed by Apple's `FoundationModels` framework, available
/// on macOS 26.0 and later. Selected at the Settings level in place of a
/// network-based Text provider — a user who picks "Foundation Models" gets a
/// real agent loop without configuring any credentials.
///
/// ## How it plugs into the agent loop
///
/// Compass tools are wrapped as `FoundationModels.Tool` instances and passed to a
/// `LanguageModelSession`. The system prompt becomes the session's `instructions`;
/// `LanguageModelSession.streamResponse(to:)` drives the turn-by-turn conversation.
/// When the model calls `submit_result`, `SubmitResultTool.call` stashes the
/// structured JSON args in a thread-safe capture box and throws a sentinel
/// `SubmitResultSignal` to break out of the framework's internal stream loop.
/// The runtime catches the signal, retrieves the captured args, and returns an
/// `AgentExecutionResult` — the same termination contract as the OpenAI-compatible
/// path.
///
/// ## Limits
///
/// FoundationModels owns its own context compaction. There is no HTTP layer, so
/// this path carries none of the network-retry or exponential-backoff machinery
/// present in the OpenAI-compatible `AgentExecutor` path. If the model needs to
/// call `submit_result` and has not done so by the time the stream finishes
/// cleanly, the runtime nudges the model with a single-shot prompt before
/// iterating again — the same fallback used by the network path.
enum FoundationModelsAgentRuntime {
  static func run(
    _ configuration: AgentExecutionConfiguration,
    isCancelled: @Sendable @escaping () -> Bool,
    emit: @Sendable @escaping (LiveEvent) -> Void
  ) async throws -> AgentExecutionResult {
    try AgentExecutor.ensureUniqueToolNames(configuration.tools)

    guard SystemLanguageModel.default.isAvailable else {
      throw AgentExecutionError.streamFailed(
        "Apple Foundation Models is not available on this system. "
          + "Check System Settings → Apple Intelligence, or pick a "
          + "different Text provider in Compass Settings."
      )
    }

    let toolContext = AgentToolContext(
      workingDirectory: configuration.workingDirectory,
      filesystem: configuration.filesystem,
      bashRunner: configuration.bashRunner,
      delegateRunner: AgentExecutor.makeDelegateRunner(
        configuration: configuration,
        onEvent: emit
      ),
      codemapStoreDirectory: configuration.codemapStoreDirectory,
      planHistoryEntries: configuration.planHistoryEntries
    )

    let submitCapture = SubmitResultCapture()
    let fmTools = try buildFoundationModelsTools(
      configuration: configuration,
      toolContext: toolContext,
      submitCapture: submitCapture,
      emit: emit
    )

    let session = LanguageModelSession(
      model: .default,
      tools: fmTools,
      instructions: configuration.systemPrompt
    )

    let startedAt = Date()
    var iterations = 0
    var assistantTranscript = ""
    var nextPrompt: String = configuration.userPrompt

    while iterations < configuration.maxIterations {
      if isCancelled() { throw AgentExecutionError.cancelled }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed > configuration.wallClockTimeout {
        throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
      }
      iterations += 1
      emit(
        LiveEvent(
          level: .info,
          text: "Foundation Models iteration \(iterations)",
          kind: .lifecycle,
          status: .running
        )
      )

      do {
        var iterationText = ""
        let stream = session.streamResponse(to: nextPrompt)
        for try await snapshot in stream {
          if isCancelled() { throw AgentExecutionError.cancelled }
          iterationText = snapshot.content
        }
        if !iterationText.isEmpty {
          assistantTranscript += iterationText
          emit(
            LiveEvent(
              level: .raw,
              text: "Assistant",
              detail: previewString(iterationText),
              kind: .agentMessage,
              status: .completed
            )
          )
        }
        if let captured = submitCapture.consume() {
          if let rejection = Self.rejectSubmitResultIfNeeded(
            captured,
            configuration: configuration,
            emit: emit
          ) {
            nextPrompt = rejection
            continue
          }
          return AgentExecutionResult(
            submitResultArguments: captured,
            iterations: iterations,
            assistantText: assistantTranscript,
            reasoningText: ""
          )
        }
        // Stream finished without submit_result being called. Nudge
        // the model to call it on the next turn — same shape as the
        // OpenAI-compatible path.
        nextPrompt =
          "You must call the submit_result tool to finish this phase. Use it now."
      } catch let signal as SubmitResultSignal {
        // submit_result was invoked mid-stream; its args are in the
        // capture box. The thrown sentinel unwinds the framework's
        // internal tool loop cleanly.
        _ = signal
        if let captured = submitCapture.consume() {
          if let rejection = Self.rejectSubmitResultIfNeeded(
            captured,
            configuration: configuration,
            emit: emit
          ) {
            nextPrompt = rejection
            continue
          }
          return AgentExecutionResult(
            submitResultArguments: captured,
            iterations: iterations,
            assistantText: assistantTranscript,
            reasoningText: ""
          )
        }
        throw AgentExecutionError.streamFailed(
          "submit_result was signalled but no arguments captured"
        )
      } catch is CancellationError {
        throw AgentExecutionError.cancelled
      } catch let agentError as AgentExecutionError {
        throw agentError
      } catch {
        throw AgentExecutionError.streamFailed(error.localizedDescription)
      }
    }
    throw AgentExecutionError.maxIterationsExceeded(configuration.maxIterations)
  }

  private static func rejectSubmitResultIfNeeded(
    _ submitResultJSON: Data,
    configuration: AgentExecutionConfiguration,
    emit: @Sendable (LiveEvent) -> Void
  ) -> String? {
    guard let validate = configuration.validateSubmitResult else { return nil }
    do {
      try validate(submitResultJSON)
      return nil
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error)
      emit(
        LiveEvent(
          level: .warning,
          text: nudge.eventText,
          detail: nudge.eventDetail,
          kind: .agentMessage,
          status: .failed
        )
      )
      return nudge.userMessage
    }
  }

  // MARK: - Tool construction

  private static func buildFoundationModelsTools(
    configuration: AgentExecutionConfiguration,
    toolContext: AgentToolContext,
    submitCapture: SubmitResultCapture,
    emit: @Sendable @escaping (LiveEvent) -> Void
  ) throws -> [any FoundationModels.Tool] {
    var out: [any FoundationModels.Tool] = []
    out.reserveCapacity(configuration.tools.count + 1)

    let submitSchema = try FoundationModelsSchemaTranslator.dynamicSchema(
      name: AgentExecutor.submitResultToolName,
      description: "Submit the final structured result for this phase.",
      from: configuration.submitResultSchema
    )
    out.append(
      SubmitResultTool(
        capture: submitCapture,
        schema: submitSchema,
        emit: emit
      )
    )

    for tool in configuration.tools {
      let schema = try FoundationModelsSchemaTranslator.dynamicSchema(
        name: tool.spec.name,
        description: tool.spec.description,
        from: tool.spec.parameters
      )
      out.append(
        DynamicAgentTool(
          agentTool: tool,
          context: toolContext,
          schema: schema,
          emit: emit
        )
      )
    }
    return out
  }
}

// MARK: - Sentinel / capture types

/// Thrown by `SubmitResultTool.call` so the FoundationModels stream
/// unwinds the moment the model invokes `submit_result`. The runtime
/// converts it back into a real `AgentExecutionResult` using the
/// args stashed in the shared `SubmitResultCapture`.
private struct SubmitResultSignal: Error {}

/// Thread-safe holder for the structured args the model passed to
/// `submit_result`. Set once, then consumed by the runtime.
@available(macOS 26.0, *)
final class SubmitResultCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Data?

  func set(_ data: Data) {
    lock.lock()
    defer { lock.unlock() }
    value = data
  }

  func consume() -> Data? {
    lock.lock()
    defer { lock.unlock() }
    let v = value
    value = nil
    return v
  }
}

// MARK: - submit_result tool

@available(macOS 26.0, *)
private struct SubmitResultTool: FoundationModels.Tool {
  typealias Arguments = GeneratedContent
  typealias Output = String

  let capture: SubmitResultCapture
  let schema: GenerationSchema
  let emit: @Sendable (LiveEvent) -> Void

  var name: String { AgentExecutor.submitResultToolName }
  var description: String { "Submit the final structured result for this phase." }
  var parameters: GenerationSchema { schema }
  var includesSchemaInInstructions: Bool { true }

  func call(arguments: GeneratedContent) async throws -> String {
    let json = arguments.jsonString
    let data = Data(json.utf8)
    capture.set(data)
    emit(
      LiveEvent(
        level: .success,
        text: "submit_result",
        detail: previewString(json),
        kind: .agentMessage,
        status: .completed
      )
    )
    throw SubmitResultSignal()
  }
}

// MARK: - Dynamic AgentTool → FoundationModels.Tool adapter

@available(macOS 26.0, *)
private struct DynamicAgentTool: FoundationModels.Tool {
  typealias Arguments = GeneratedContent
  typealias Output = String

  let agentTool: AgentTool
  let context: AgentToolContext
  let schema: GenerationSchema
  let emit: @Sendable (LiveEvent) -> Void

  var name: String { agentTool.spec.name }
  var description: String { agentTool.spec.description }
  var parameters: GenerationSchema { schema }
  var includesSchemaInInstructions: Bool { true }

  func call(arguments: GeneratedContent) async throws -> String {
    let json = arguments.jsonString
    let correlationID = UUID().uuidString
    emit(
      LiveEvent(
        level: .info,
        text: name,
        detail: previewString(json),
        kind: .agentMessage,
        status: .running,
        correlationID: correlationID
      )
    )
    do {
      let result = try await agentTool.invoke(
        arguments: Data(json.utf8),
        context: context
      )
      emit(
        LiveEvent(
          level: result.isError ? .error : .success,
          text: name,
          detail: previewString(result.content),
          kind: .agentMessage,
          status: result.isError ? .failed : .completed,
          correlationID: correlationID
        )
      )
      return result.content
    } catch let toolError as AgentToolError {
      let message = toolError.errorDescription ?? "Tool error"
      emit(
        LiveEvent(
          level: .error,
          text: name,
          detail: previewString(message),
          kind: .agentMessage,
          status: .failed,
          correlationID: correlationID
        )
      )
      return message
    } catch {
      let message = "Tool \(name) threw: \(error.localizedDescription)"
      emit(
        LiveEvent(
          level: .error,
          text: name,
          detail: previewString(message),
          kind: .agentMessage,
          status: .failed,
          correlationID: correlationID
        )
      )
      return message
    }
  }
}

// MARK: - Schema translation

/// Translates Compass's JSON-Schema-shaped `AgentToolParametersSchema`
/// into the `DynamicGenerationSchema` graph FoundationModels expects.
///
/// We don't need to be a fully-general JSON Schema implementation —
/// only the subset Compass's tool definitions use:
///
/// - `type: "object"` with `properties` + `required`
/// - `type: "string"` (optional `enum`)
/// - `type: "integer"` / `type: "number"`
/// - `type: "boolean"`
/// - `type: "array"` with `items`
/// - `description` strings on any node
///
/// Unknown shapes degrade to a permissive `String` node so the
/// dynamic dispatch path stays best-effort rather than failing the
/// whole run.
@available(macOS 26.0, *)
enum FoundationModelsSchemaTranslator {
  static func dynamicSchema(
    name: String,
    description: String,
    from parameters: AgentToolParametersSchema
  ) throws -> GenerationSchema {
    let root = try translate(
      name: name,
      description: description,
      json: parameters.json
    )
    return try GenerationSchema(root: root, dependencies: [])
  }

  private static func translate(
    name: String,
    description: String?,
    json: Data
  ) throws -> DynamicGenerationSchema {
    let object = try JSONSerialization.jsonObject(with: json)
    return translateNode(name: name, description: description, node: object)
  }

  private static func translateNode(
    name: String,
    description: String?,
    node: Any
  ) -> DynamicGenerationSchema {
    guard let dict = node as? [String: Any] else {
      return DynamicGenerationSchema(type: String.self)
    }
    let nodeDescription =
      (dict["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? description
    let type = (dict["type"] as? String) ?? "object"
    switch type {
    case "object":
      let properties = (dict["properties"] as? [String: Any]) ?? [:]
      let required = Set((dict["required"] as? [String]) ?? [])
      let translated = properties.map {
        (propertyName, propertyNode) -> DynamicGenerationSchema.Property in
        let propertyDescription =
          ((propertyNode as? [String: Any])?["description"] as? String)
        let childSchema = translateNode(
          name: "\(name).\(propertyName)",
          description: propertyDescription,
          node: propertyNode
        )
        return DynamicGenerationSchema.Property(
          name: propertyName,
          description: propertyDescription,
          schema: childSchema,
          isOptional: !required.contains(propertyName)
        )
      }
      return DynamicGenerationSchema(
        name: name,
        description: nodeDescription,
        properties: translated
      )
    case "string":
      if let choices = dict["enum"] as? [String], !choices.isEmpty {
        return DynamicGenerationSchema(
          name: name,
          description: nodeDescription,
          anyOf: choices
        )
      }
      return DynamicGenerationSchema(type: String.self)
    case "integer":
      return DynamicGenerationSchema(type: Int.self)
    case "number":
      return DynamicGenerationSchema(type: Double.self)
    case "boolean":
      return DynamicGenerationSchema(type: Bool.self)
    case "array":
      let items = dict["items"] ?? [String: Any]()
      let itemSchema = translateNode(
        name: "\(name).item",
        description: nil,
        node: items
      )
      return DynamicGenerationSchema(arrayOf: itemSchema)
    default:
      return DynamicGenerationSchema(type: String.self)
    }
  }
}

// MARK: - Local helpers

/// Single-line preview used in `LiveEvent` details for tool / stream
/// payloads. Mirrors `AgentExecutor.previewString` so log lines look
/// consistent across the two backends without exposing that helper
/// or duplicating its body if it's already file-private to the
/// other module.
private func previewString(_ text: String, limit: Int = 320) -> String {
  let collapsed = text.replacingOccurrences(of: "\n", with: " ")
  if collapsed.count <= limit { return collapsed }
  return String(collapsed.prefix(limit)) + "…"
}
