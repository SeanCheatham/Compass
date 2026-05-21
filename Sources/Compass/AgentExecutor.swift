import Foundation
import OpenAI

/// Outcome of one Plan / Reflect / Develop pass.
///
/// `submitResultArguments` holds the JSON args the model passed to the
/// terminal `submit_result` tool — the structured response Compass decodes
/// into `PlanRunResult` / `DevelopSummary` / `ReflectSummary`.
struct AgentExecutionResult: Equatable {
    var submitResultArguments: Data
    var iterations: Int
    var assistantText: String
    var reasoningText: String
}

/// Configuration for a single AgentExecutor.run() invocation.
struct AgentExecutionConfiguration {
    var settings: AgentRuntimeSettings
    var phase: AgentPhase
    var modelOverride: String
    var systemPrompt: String
    var userPrompt: String
    var tools: [AgentTool]
    var submitResultSchema: AgentToolParametersSchema
    var workingDirectory: URL
    var bashRunner: AgentBashRunner
    var maxIterations: Int
    var wallClockTimeout: TimeInterval

    init(
        settings: AgentRuntimeSettings,
        phase: AgentPhase,
        modelOverride: String = "",
        systemPrompt: String,
        userPrompt: String,
        tools: [AgentTool],
        submitResultSchema: AgentToolParametersSchema,
        workingDirectory: URL,
        bashRunner: AgentBashRunner = AgentHostBashRunner(),
        maxIterations: Int = 64,
        wallClockTimeout: TimeInterval = 30 * 60
    ) {
        self.settings = settings
        self.phase = phase
        self.modelOverride = modelOverride
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.tools = tools
        self.submitResultSchema = submitResultSchema
        self.workingDirectory = workingDirectory
        self.bashRunner = bashRunner
        self.maxIterations = maxIterations
        self.wallClockTimeout = wallClockTimeout
    }
}

enum AgentExecutionError: LocalizedError, Equatable {
    case configurationInvalid(String)
    case streamFailed(String)
    case maxIterationsExceeded(Int)
    case wallClockExceeded(TimeInterval)
    case modelStoppedWithoutSubmitResult
    case toolCallDecodeFailed(name: String, detail: String)
    case duplicateToolName(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .configurationInvalid(detail): return "Agent configuration invalid: \(detail)"
        case let .streamFailed(detail): return "Chat completions stream failed: \(detail)"
        case let .maxIterationsExceeded(n): return "Agent exceeded max iterations (\(n))"
        case let .wallClockExceeded(timeout): return "Agent exceeded wall-clock timeout (\(Int(timeout))s)"
        case .modelStoppedWithoutSubmitResult: return "Model stopped without calling submit_result"
        case let .toolCallDecodeFailed(name, detail): return "Tool call \(name) had undecodable args: \(detail)"
        case let .duplicateToolName(name): return "Duplicate tool name in registry: \(name)"
        case .cancelled: return "Agent execution cancelled"
        }
    }
}

/// Runs the OpenAI-compatible chat-completions loop with tool dispatch.
/// Terminates when the model invokes the `submit_result` tool, whose
/// `parameters` schema is the phase's output schema.
final class AgentExecutor {
    static let submitResultToolName = "submit_result"

    private let onEvent: (LiveEvent) -> Void
    private var cancelled = false

    init(onEvent: @escaping (LiveEvent) -> Void = { _ in }) {
        self.onEvent = onEvent
    }

    func cancel() {
        cancelled = true
    }

    func run(_ configuration: AgentExecutionConfiguration) async throws -> AgentExecutionResult {
        try Self.ensureUniqueToolNames(configuration.tools)
        let registry = Dictionary(uniqueKeysWithValues: configuration.tools.map { ($0.spec.name, $0) })

        let openAI = Self.makeClient(settings: configuration.settings)
        let openAITools = try Self.buildOpenAITools(configuration: configuration)
        let toolContext = AgentToolContext(
            workingDirectory: configuration.workingDirectory,
            bashRunner: configuration.bashRunner
        )
        let model = configuration.settings.model(for: configuration.phase, sidebarOverride: configuration.modelOverride)

        var messages: [ChatQuery.ChatCompletionMessageParam] = [
            .system(.init(content: .textContent(configuration.systemPrompt))),
            .user(.init(content: .string(configuration.userPrompt)))
        ]
        var assistantTranscript = ""
        var reasoningTranscript = ""
        let startedAt = Date()

        for iteration in 1...configuration.maxIterations {
            if cancelled { throw AgentExecutionError.cancelled }
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed > configuration.wallClockTimeout {
                throw AgentExecutionError.wallClockExceeded(configuration.wallClockTimeout)
            }

            emit(level: .info, text: "Agent iteration \(iteration)", kind: .lifecycle, status: .running)

            let query = ChatQuery(
                messages: messages,
                model: model,
                tools: openAITools,
                stream: true
            )

            let aggregated: AggregatedTurn
            do {
                aggregated = try await streamOneTurn(openAI: openAI, query: query)
            } catch is CancellationError {
                throw AgentExecutionError.cancelled
            } catch {
                if cancelled { throw AgentExecutionError.cancelled }
                throw AgentExecutionError.streamFailed(error.localizedDescription)
            }

            assistantTranscript += aggregated.assistantText
            reasoningTranscript += aggregated.reasoningText

            if !aggregated.assistantText.isEmpty {
                emit(level: .raw, text: "Assistant", detail: previewString(aggregated.assistantText), kind: .agentMessage, status: .completed)
            }

            messages.append(.assistant(.init(
                content: aggregated.assistantText.isEmpty ? nil : .textContent(aggregated.assistantText),
                toolCalls: aggregated.toolCalls.isEmpty ? nil : aggregated.toolCalls.map { $0.asAssistantToolCall() }
            )))

            // No tool calls → either submit_result was missed or the model
            // gave up. Either way, nudge it once; on the next loop we'll
            // either get tool calls or break out.
            if aggregated.toolCalls.isEmpty {
                if aggregated.finishReason == "stop" || aggregated.finishReason == nil {
                    messages.append(.user(.init(content: .string("You must call the submit_result tool to finish this phase. Use it now."))))
                    continue
                }
            }

            for toolCall in aggregated.toolCalls {
                if cancelled { throw AgentExecutionError.cancelled }

                if toolCall.name == Self.submitResultToolName {
                    let argsData = Data(toolCall.arguments.utf8)
                    // Validate that the args are well-formed JSON; the
                    // caller decodes them into the phase model.
                    if (try? JSONSerialization.jsonObject(with: argsData)) == nil {
                        let detail = "submit_result args are not valid JSON: \(previewString(toolCall.arguments))"
                        messages.append(.tool(.init(
                            content: .textContent(detail),
                            toolCallId: toolCall.id
                        )))
                        emit(level: .error, text: "submit_result rejected", detail: detail, kind: .agentMessage, status: .failed, correlationID: toolCall.id)
                        continue
                    }
                    emit(level: .success, text: "submit_result", detail: previewString(toolCall.arguments), kind: .agentMessage, status: .completed, correlationID: toolCall.id)
                    return AgentExecutionResult(
                        submitResultArguments: argsData,
                        iterations: iteration,
                        assistantText: assistantTranscript,
                        reasoningText: reasoningTranscript
                    )
                }

                guard let tool = registry[toolCall.name] else {
                    let detail = "Unknown tool: \(toolCall.name)"
                    messages.append(.tool(.init(content: .textContent(detail), toolCallId: toolCall.id)))
                    emit(level: .error, text: detail, kind: .lifecycle, status: .failed, correlationID: toolCall.id)
                    continue
                }

                emitToolStart(name: toolCall.name, arguments: toolCall.arguments, correlationID: toolCall.id)

                let result: AgentToolInvocationResult
                do {
                    result = try await tool.invoke(arguments: Data(toolCall.arguments.utf8), context: toolContext)
                } catch {
                    let message = "Tool \(toolCall.name) threw: \(error.localizedDescription)"
                    messages.append(.tool(.init(content: .textContent(message), toolCallId: toolCall.id)))
                    emitToolEnd(name: toolCall.name, result: .failure(message), correlationID: toolCall.id)
                    continue
                }
                messages.append(.tool(.init(content: .textContent(result.content), toolCallId: toolCall.id)))
                emitToolEnd(name: toolCall.name, result: result, correlationID: toolCall.id)
            }
        }
        throw AgentExecutionError.maxIterationsExceeded(configuration.maxIterations)
    }

    static func ensureUniqueToolNames(_ tools: [AgentTool]) throws {
        var seen = Set<String>()
        for tool in tools {
            if tool.spec.name == Self.submitResultToolName {
                throw AgentExecutionError.duplicateToolName(tool.spec.name)
            }
            if !seen.insert(tool.spec.name).inserted {
                throw AgentExecutionError.duplicateToolName(tool.spec.name)
            }
        }
    }

    static func makeClient(settings: AgentRuntimeSettings) -> OpenAI {
        let components = URLComponents(url: settings.baseURL, resolvingAgainstBaseURL: false)
        let host = components?.host ?? "api.openai.com"
        let port = components?.port ?? (settings.baseURL.scheme == "http" ? 80 : 443)
        let scheme = components?.scheme ?? "https"
        let basePath = components?.path.isEmpty == false ? components!.path : "/v1"

        let configuration = OpenAI.Configuration(
            token: settings.apiKey,
            organizationIdentifier: nil,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            timeoutInterval: 600.0,
            customHeaders: [:],
            parsingOptions: [.relaxed]
        )
        return OpenAI(configuration: configuration)
    }

    static func buildOpenAITools(
        configuration: AgentExecutionConfiguration
    ) throws -> [ChatQuery.ChatCompletionToolParam] {
        var out: [ChatQuery.ChatCompletionToolParam] = []
        for tool in configuration.tools {
            out.append(try Self.buildFunctionParam(spec: tool.spec))
        }
        let submitSpec = AgentToolSpec(
            name: Self.submitResultToolName,
            description: "Call this once with the structured result for this phase. The arguments object must match the phase output schema. Calling this ends the phase.",
            parameters: configuration.submitResultSchema
        )
        out.append(try Self.buildFunctionParam(spec: submitSpec))
        return out
    }

    private static func buildFunctionParam(spec: AgentToolSpec) throws -> ChatQuery.ChatCompletionToolParam {
        let schema = try JSONDecoder().decode(JSONSchema.self, from: spec.parameters.json)
        return ChatQuery.ChatCompletionToolParam(function: .init(
            name: spec.name,
            description: spec.description,
            parameters: schema,
            strict: nil
        ))
    }

    // MARK: - Streaming aggregation

    private struct AggregatedTurn {
        var assistantText: String
        var reasoningText: String
        var toolCalls: [PendingToolCall]
        var finishReason: String?
    }

    private struct PendingToolCall {
        var index: Int
        var id: String
        var name: String
        var arguments: String

        func asAssistantToolCall() -> ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam {
            .init(id: id, function: .init(arguments: arguments, name: name))
        }
    }

    private func streamOneTurn(
        openAI: OpenAI,
        query: ChatQuery
    ) async throws -> AggregatedTurn {
        var assistantText = ""
        var reasoningText = ""
        var pending: [Int: PendingToolCall] = [:]
        var finishReason: String?

        for try await chunk in openAI.chatsStream(query: query) {
            if cancelled { throw AgentExecutionError.cancelled }
            for choice in chunk.choices {
                if let delta = choice.delta.content {
                    assistantText += delta
                }
                if let reasoning = choice.delta.reasoning {
                    reasoningText += reasoning
                }
                if let toolCalls = choice.delta.toolCalls {
                    for fragment in toolCalls {
                        let index = fragment.index
                        var current = pending[index] ?? PendingToolCall(index: index, id: "", name: "", arguments: "")
                        if let id = fragment.id, !id.isEmpty { current.id = id }
                        if let name = fragment.function?.name, !name.isEmpty { current.name = name }
                        if let args = fragment.function?.arguments { current.arguments += args }
                        pending[index] = current
                    }
                }
                if let reason = choice.finishReason {
                    finishReason = String(describing: reason)
                }
            }
        }

        // Strip <think>...</think> blocks the model might embed when the
        // endpoint doesn't split reasoning into its own field. Move the
        // contents into reasoningText so the assistant message we replay to
        // the API contains only the user-visible reply.
        let (cleaned, extractedReasoning) = Self.stripThinkBlocks(assistantText)
        assistantText = cleaned
        if !extractedReasoning.isEmpty {
            reasoningText += extractedReasoning
        }

        let ordered = pending.keys.sorted().compactMap { pending[$0] }
        let valid = ordered.filter { !$0.id.isEmpty && !$0.name.isEmpty }
        return AggregatedTurn(
            assistantText: assistantText.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoningText: reasoningText.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: valid,
            finishReason: finishReason
        )
    }

    static func stripThinkBlocks(_ text: String) -> (String, String) {
        guard text.contains("<think>") else { return (text, "") }
        var output = ""
        var reasoning = ""
        var remaining = Substring(text)
        while let start = remaining.range(of: "<think>") {
            output += remaining[..<start.lowerBound]
            let afterOpen = remaining[start.upperBound...]
            if let end = afterOpen.range(of: "</think>") {
                reasoning += afterOpen[..<end.lowerBound]
                remaining = afterOpen[end.upperBound...]
            } else {
                reasoning += afterOpen
                remaining = ""
                break
            }
        }
        output += remaining
        return (output, reasoning)
    }

    // MARK: - LiveEvent mapping

    private func emit(
        level: LiveLine.Level = .info,
        text: String,
        detail: String? = nil,
        kind: LiveLine.Kind = .message,
        status: LiveLine.Status = .none,
        correlationID: String? = nil
    ) {
        onEvent(LiveEvent(level: level, text: text, detail: detail, kind: kind, status: status, correlationID: correlationID))
    }

    private func emitToolStart(name: String, arguments: String, correlationID: String) {
        let kind = liveKind(forTool: name)
        let level: LiveLine.Level = kind == .command ? .raw : .info
        let detail = previewString(arguments)
        emit(level: level, text: "Tool \(name)", detail: detail, kind: kind, status: .running, correlationID: correlationID)
    }

    private func emitToolEnd(name: String, result: AgentToolInvocationResult, correlationID: String) {
        let kind = liveKind(forTool: name)
        let status: LiveLine.Status = result.isError ? .failed : .completed
        let level: LiveLine.Level = result.isError ? .error : (kind == .command ? .success : .info)
        emit(level: level, text: "Tool \(name)", detail: previewString(result.content), kind: kind, status: status, correlationID: correlationID)
    }

    private func liveKind(forTool name: String) -> LiveLine.Kind {
        switch name {
        case AgentBashTool.toolName: return .command
        case AgentWriteFileTool.toolName, AgentEditFileTool.toolName: return .fileChange
        default: return .lifecycle
        }
    }

    private func previewString(_ s: String, limit: Int = 280) -> String {
        let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count <= limit { return stripped }
        return String(stripped.prefix(limit)) + " ..."
    }

    // MARK: - Tool registries

    /// Tools the Plan and Reflect phases get: read-only file access.
    static func readOnlyTools() -> [AgentTool] {
        [
            AgentReadFileTool(),
            AgentLsTool(),
            AgentGrepTool(),
            AgentGlobTool()
        ]
    }

    /// Tools the Develop phase gets: read-only set plus write/edit/bash.
    static func developTools() -> [AgentTool] {
        readOnlyTools() + [
            AgentWriteFileTool(),
            AgentEditFileTool(),
            AgentBashTool()
        ]
    }

    static func toolsForPhase(_ phase: AgentPhase) -> [AgentTool] {
        switch phase {
        case .plan, .reflect: return readOnlyTools()
        case .develop: return developTools()
        }
    }
}
