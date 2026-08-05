import Foundation

/// How the agentic loop talks to the model.
///
/// `.envelope` is the legacy Compass-owned text protocol: the model emits one
/// JSON object per turn and the executor parses it. `.nativeTools` uses the
/// provider's native tool calling (OpenAI-style `tools` / `tool_calls`), which
/// is the preferred path for capable cloud models and modern MLX checkpoints.
public enum AgentPromptMode: String, Sendable, Equatable, Codable {
  case envelope
  case nativeTools
}

/// One tool invocation requested by the model through native tool calling.
public struct AgentChatToolCall: Equatable, Sendable {
  public var id: String
  public var name: String
  /// Raw JSON object text for the call arguments, as emitted by the provider.
  public var argumentsJSON: String

  public init(id: String, name: String, argumentsJSON: String) {
    self.id = id
    self.name = name
    self.argumentsJSON = argumentsJSON
  }
}

public enum AgentChatRole: String, Sendable, Equatable, Codable {
  case system
  case user
  case assistant
  case tool
}

/// A single message in a native tool-calling conversation.
public struct AgentChatMessage: Equatable, Sendable {
  public var role: AgentChatRole
  public var content: String
  /// Tool calls made by the assistant in this turn.
  public var toolCalls: [AgentChatToolCall]
  /// For `.tool` messages, the `id` of the tool call being answered.
  public var toolCallID: String?
  /// Provider chain-of-thought for assistant turns (`reasoning_content`).
  /// Required on writeback for Kimi preserved-thinking / multi-turn tool loops.
  public var reasoningContent: String?

  public init(
    role: AgentChatRole,
    content: String,
    toolCalls: [AgentChatToolCall] = [],
    toolCallID: String? = nil,
    reasoningContent: String? = nil
  ) {
    self.role = role
    self.content = content
    self.toolCalls = toolCalls
    self.toolCallID = toolCallID
    self.reasoningContent = reasoningContent
  }

  public static func system(_ content: String) -> Self {
    Self(role: .system, content: content)
  }

  public static func user(_ content: String) -> Self {
    Self(role: .user, content: content)
  }

  public static func assistant(
    _ content: String,
    toolCalls: [AgentChatToolCall] = [],
    reasoningContent: String? = nil
  ) -> Self {
    Self(
      role: .assistant,
      content: content,
      toolCalls: toolCalls,
      reasoningContent: reasoningContent
    )
  }

  public static func toolResult(_ content: String, toolCallID: String) -> Self {
    Self(role: .tool, content: content, toolCallID: toolCallID)
  }
}

public struct AgentChatRequest: Sendable {
  public var modelID: String
  public var messages: [AgentChatMessage]
  public var tools: [AgentToolSpec]
  public var maxOutputTokens: Int
  public var logLabel: String?
  public var routingHint: ModelRoutingHint

  public init(
    modelID: String,
    messages: [AgentChatMessage],
    tools: [AgentToolSpec] = [],
    maxOutputTokens: Int = AgentExecutor.maxCompletionTokensPerTurn,
    logLabel: String? = nil,
    routingHint: ModelRoutingHint = .cloudPrimary
  ) {
    self.modelID = modelID
    self.messages = messages
    self.tools = tools
    self.maxOutputTokens = max(1, maxOutputTokens)
    self.logLabel = logLabel
    self.routingHint = routingHint
  }
}

public struct AgentChatResponse: Sendable, Equatable {
  public var text: String
  /// Chain-of-thought from providers that emit `reasoning_content` (e.g. Kimi).
  public var reasoningText: String
  public var toolCalls: [AgentChatToolCall]
  public var tokenUsage: AgentRunTokenUsage

  public init(
    text: String,
    toolCalls: [AgentChatToolCall],
    tokenUsage: AgentRunTokenUsage,
    reasoningText: String = ""
  ) {
    self.text = text
    self.reasoningText = reasoningText
    self.toolCalls = toolCalls
    self.tokenUsage = tokenUsage
  }
}

/// A model backend that supports native tool calling with a structured
/// message history — as opposed to the plain text-in/text-out
/// `LocalModelGenerating` interface used by the legacy envelope loop and
/// cheap assist work.
public protocol AgentChatGenerating: Sendable {
  func generateChat(request: AgentChatRequest) async throws -> AgentChatResponse
}

extension AgentToolSpec {
  /// OpenAI-style `{"type":"function","function":{...}}` tool definition,
  /// suitable for both cloud chat-completions and MLX chat templates.
  public var nativeToolJSONObject: [String: Any]? {
    guard
      let parameters = try? JSONSerialization.jsonObject(with: parameters.json) as? [String: Any]
    else {
      return nil
    }
    return [
      "type": "function",
      "function": [
        "name": name,
        "description": description,
        "parameters": parameters,
      ],
    ]
  }
}
