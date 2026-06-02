import Foundation
import FoundationModels

/// On-device text runtime backed by Apple's `FoundationModels` framework, available
/// on macOS 26.0 and later. Selected at the Settings level in place of a
/// network-based Text provider — a user who picks "Foundation Models" gets a
/// real agent loop without configuring any credentials.
///
/// ## How it plugs into the agent loop
///
/// `AgentExecutor` builds Compass tools (`read_file`, `bash`, `submit_result`, …)
/// as OpenAI-style tool param objects. This runtime takes that same tool set via
/// `AgentExecutionConfiguration` and wraps it for Apple\'s on-device Foundation
/// Models (`FoundationModels.Tool` / `DynamicAgentTool`) so the model can call
/// them just as it would on the network-based path. The system prompt becomes
/// the session\'s `instructions`; `LanguageModelSession.streamResponse(to:)`
/// drives the turn-by-turn conversation. `SubmitResultTool` uses a sentinel
/// signal to break out of the framework\'s internal stream loop and produce an
/// `AgentExecutionResult` — the same termination contract as the OpenAI path.
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

    guard FoundationModelsAvailability.isAvailable else {
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
      planHistoryEntries: configuration.planHistoryEntries,
      assumptionsURL: configuration.assumptionsURL,
      phase: configuration.phase,
      sessionNumber: configuration.sessionNumber,
      toolchainService: configuration.toolchainService,
      hostXcodeService: configuration.hostXcodeService
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
          Self.emitSubmitResultAccepted(captured, emit: emit)
          return AgentExecutionResult(
            submitResultArguments: captured,
            iterations: iterations,
            assistantText: assistantTranscript,
            reasoningText: ""
          )
        }
        // Stream finished without submit_result being called. Nudge
        // the model to call it on the next turn — same phase-specific
        // recovery packet as the OpenAI-compatible path.
        let nudge = AgentExecutor.missingSubmitResultNudge(
          finishReason: nil,
          maxCompletionTokens: AgentExecutor.maxCompletionTokensPerTurn,
          phase: configuration.phase
        )
        emit(
          LiveEvent(
            level: .warning,
            text: nudge.eventText,
            detail: nudge.eventDetail,
            kind: .agentMessage,
            status: .failed
          )
        )
        nextPrompt = nudge.userMessage
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
          Self.emitSubmitResultAccepted(captured, emit: emit)
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

  static func rejectSubmitResultIfNeeded(
    _ submitResultJSON: Data,
    configuration: AgentExecutionConfiguration,
    emit: @Sendable (LiveEvent) -> Void
  ) -> String? {
    guard let validate = configuration.validateSubmitResult else { return nil }
    do {
      try validate(submitResultJSON)
      return nil
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(
        for: error,
        phase: configuration.phase
      )
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

  private static func emitSubmitResultAccepted(
    _ submitResultJSON: Data,
    emit: @Sendable (LiveEvent) -> Void
  ) {
    emit(
      LiveEvent(
        level: .success,
        text: "submit_result",
        detail: previewString(String(decoding: submitResultJSON, as: UTF8.self)),
        kind: .agentMessage,
        status: .completed
      )
    )
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

    let submitSchema = try FoundationModelsSchemaTranslator.topLevelGeneratedContentSchema(
      name: AgentExecutor.submitResultToolName,
      description: "Submit the final structured result for this phase.",
      from: configuration.submitResultSchema
    )
    out.append(
      SubmitResultTool(
        capture: submitCapture,
        schema: submitSchema
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

@available(macOS 26.0, *)
extension FoundationModelsAgentRuntime {
  static func jsonData(from content: GeneratedContent) throws -> Data {
    let object = try jsonObject(from: content)
    guard JSONSerialization.isValidJSONObject(object) else {
      throw FoundationModelsJSONEncodingError.invalidJSONObject
    }
    return try JSONSerialization.data(
      withJSONObject: object,
      options: [.withoutEscapingSlashes]
    )
  }

  private static func jsonObject(from content: GeneratedContent) throws -> Any {
    switch content.kind {
    case .null:
      return NSNull()
    case .bool(let value):
      return value
    case .number(let value):
      guard value.isFinite else {
        throw FoundationModelsJSONEncodingError.nonFiniteNumber(value)
      }
      return value
    case .string(let value):
      return value
    case .array(let values):
      return try values.map { try jsonObject(from: $0) }
    case .structure(let properties, _):
      var object = [String: Any]()
      for (key, value) in properties {
        object[key] = try jsonObject(from: value)
      }
      return object
    @unknown default:
      throw FoundationModelsJSONEncodingError.invalidJSONObject
    }
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

  var name: String { AgentExecutor.submitResultToolName }
  var description: String { "Submit the final structured result for this phase." }
  var parameters: GenerationSchema { schema }
  var includesSchemaInInstructions: Bool { true }

  func call(arguments: GeneratedContent) async throws -> String {
    let data = try FoundationModelsAgentRuntime.jsonData(from: arguments)
    capture.set(data)
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
    let data: Data
    let json: String
    do {
      data = try FoundationModelsAgentRuntime.jsonData(from: arguments)
      json = String(decoding: data, as: UTF8.self)
    } catch {
      let message = "Tool \(name) arguments could not be serialized: \(error.localizedDescription)"
      emit(
        LiveEvent(
          level: .error,
          text: name,
          detail: previewString(message),
          kind: .agentMessage,
          status: .failed,
          correlationID: UUID().uuidString
        )
      )
      return message
    }
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
        arguments: data,
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

// MARK: - GeneratedContent JSON encoding

enum FoundationModelsJSONEncodingError: LocalizedError, Equatable {
  case nonFiniteNumber(Double)
  case invalidJSONObject

  var errorDescription: String? {
    switch self {
    case .nonFiniteNumber(let value):
      return "GeneratedContent contained a non-finite number: \(value)"
    case .invalidJSONObject:
      return "GeneratedContent could not be represented as JSON"
    }
  }
}

// MARK: - Schema translation

enum CompassJSONSchemaTranslation {
  static func concreteNullableAnyOfBranch(
    in dict: [String: Any],
    root: [String: Any]? = nil
  ) -> [String: Any]? {
    let resolved = root.map { resolveReference(in: dict, root: $0) } ?? dict
    guard let branches = resolved["anyOf"] as? [[String: Any]] else { return nil }
    let concreteBranches = branches
      .map { branch in
        root.map { resolveReference(in: branch, root: $0) } ?? branch
      }
      .filter { ($0["type"] as? String) != "null" }
    guard concreteBranches.count == 1 else { return nil }
    return concreteBranches[0]
  }

  static func containsNullAnyOf(
    in dict: [String: Any],
    root: [String: Any]? = nil
  ) -> Bool {
    let resolved = root.map { resolveReference(in: dict, root: $0) } ?? dict
    guard let branches = resolved["anyOf"] as? [[String: Any]] else { return false }
    return branches.contains { branch in
      let resolvedBranch = root.map { resolveReference(in: branch, root: $0) } ?? branch
      return (resolvedBranch["type"] as? String) == "null"
    }
  }

  static func resolveReference(in dict: [String: Any], root: [String: Any]) -> [String: Any] {
    guard let ref = dict["$ref"] as? String, ref.hasPrefix("#/") else {
      return dict
    }
    let path = ref.dropFirst(2).split(separator: "/").map { component in
      component
        .replacingOccurrences(of: "~1", with: "/")
        .replacingOccurrences(of: "~0", with: "~")
    }
    var current: Any = root
    for component in path {
      guard let object = current as? [String: Any],
        let next = object[String(component)]
      else {
        return dict
      }
      current = next
    }
    return (current as? [String: Any]) ?? dict
  }
}

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
/// - `anyOf`, including nullable pairs such as `[{"type": "boolean"}, {"type": "null"}]`
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

  static func topLevelGeneratedContentSchema(
    name: String,
    description: String,
    from parameters: AgentToolParametersSchema
  ) throws -> GenerationSchema {
    let object = try JSONSerialization.jsonObject(with: parameters.json)
    let root = (object as? [String: Any]) ?? [:]
    let properties = (root["properties"] as? [String: Any]) ?? [:]
    let required = Set((root["required"] as? [String]) ?? [])
    let translated = properties.keys.sorted().map { propertyName in
      let propertyNode = properties[propertyName] as? [String: Any]
      let propertyDescription = propertyNode?["description"] as? String
      return DynamicGenerationSchema.Property(
        name: propertyName,
        description: propertyDescription,
        schema: DynamicGenerationSchema(type: GeneratedContent.self),
        isOptional: !required.contains(propertyName)
      )
    }
    let rootSchema = DynamicGenerationSchema(
      name: name,
      description: description,
      properties: translated
    )
    return try GenerationSchema(root: rootSchema, dependencies: [])
  }

  private static func translate(
    name: String,
    description: String?,
    json: Data
  ) throws -> DynamicGenerationSchema {
    let object = try JSONSerialization.jsonObject(with: json)
    let root = (object as? [String: Any]) ?? [:]
    return translateNode(name: name, description: description, node: object, root: root)
  }

  private static func translateNode(
    name: String,
    description: String?,
    node: Any,
    root: [String: Any]
  ) -> DynamicGenerationSchema {
    guard let dict = node as? [String: Any] else {
      return DynamicGenerationSchema(type: String.self)
    }
    let resolved = CompassJSONSchemaTranslation.resolveReference(in: dict, root: root)
    let nodeDescription =
      (resolved["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? description
    if let branches = resolved["anyOf"] as? [[String: Any]], !branches.isEmpty {
      let choices = branches.compactMap { branch -> DynamicGenerationSchema? in
        let resolvedBranch = CompassJSONSchemaTranslation.resolveReference(in: branch, root: root)
        if (resolvedBranch["type"] as? String) == "null" {
          if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            return DynamicGenerationSchema.null
          }
          return nil
        }
        var branchWithDescription = resolvedBranch
        if branchWithDescription["description"] == nil, let nodeDescription {
          branchWithDescription["description"] = nodeDescription
        }
        return translateNode(
          name: name,
          description: nodeDescription,
          node: branchWithDescription,
          root: root
        )
      }
      guard choices.count > 1 else {
        return choices.first ?? DynamicGenerationSchema(type: String.self)
      }
      return DynamicGenerationSchema(name: name, description: nodeDescription, anyOf: choices)
    }
    let type = (resolved["type"] as? String) ?? "object"
    switch type {
    case "object":
      let properties = (resolved["properties"] as? [String: Any]) ?? [:]
      let required = Set((resolved["required"] as? [String]) ?? [])
      let translated = properties.map {
        (propertyName, propertyNode) -> DynamicGenerationSchema.Property in
        let propertyDescription =
          ((propertyNode as? [String: Any])?["description"] as? String)
        let childSchema = translateNode(
          name: "\(name).\(propertyName)",
          description: propertyDescription,
          node: propertyNode,
          root: root
        )
        return DynamicGenerationSchema.Property(
          name: propertyName,
          description: propertyDescription,
          schema: childSchema,
          isOptional: propertyIsOptional(
            propertyName: propertyName,
            propertyNode: propertyNode,
            required: required,
            root: root
          )
        )
      }
      return DynamicGenerationSchema(
        name: name,
        description: nodeDescription,
        properties: translated
      )
    case "string":
      if let choices = resolved["enum"] as? [String], !choices.isEmpty {
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
      let items = resolved["items"] ?? [String: Any]()
      let itemSchema = translateNode(
        name: "\(name).item",
        description: nil,
        node: items,
        root: root
      )
      return DynamicGenerationSchema(arrayOf: itemSchema)
    default:
      return DynamicGenerationSchema(type: String.self)
    }
  }

  static func propertyIsOptional(
    propertyName: String,
    propertyNode: Any,
    required: Set<String>,
    root: [String: Any]
  ) -> Bool {
    if !required.contains(propertyName) {
      return true
    }
    guard let dict = propertyNode as? [String: Any],
      CompassJSONSchemaTranslation.containsNullAnyOf(in: dict, root: root)
    else {
      return false
    }
    if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
      return false
    }
    return true
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
