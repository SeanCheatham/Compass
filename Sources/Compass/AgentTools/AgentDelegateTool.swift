import Foundation

/// Spawn a focused sub-agent for a self-contained sub-task. The
/// sub-agent runs in the same working directory with (by default) the
/// parent's tool set minus `delegate`, then returns a single `findings`
/// string that comes back as this tool's result content.
///
/// Nesting is disabled: the runner unconditionally excludes
/// `AgentDelegateTool` from the child's tool list, so sub-agents have
/// no `delegate` to call.
struct AgentDelegateTool: AgentTool {
  static let toolName = "delegate"
  static let maxTaskLength = 8_000

  struct Arguments: Decodable {
    let task: String
    let tools: [String]?
    let profile: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
      case task
      case prompt
      case instructions
      case instruction
      case question
      case subtask
      case tools
      case toolNames
      case toolNamesSnake = "tool_names"
      case allowedTools
      case allowedToolsSnake = "allowed_tools"
      case toolWhitelist
      case toolWhitelistSnake = "tool_whitelist"
      case profile
      case model
      case modelOverride
      case modelOverrideSnake = "model_override"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      task = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .task,
        aliases: [.prompt, .instructions, .instruction, .question, .subtask],
        fieldName: "task"
      )
      tools = try Self.decodeToolListIfPresent(
        from: container,
        preferredKey: .tools,
        aliases: [
          .toolNames, .toolNamesSnake, .allowedTools, .allowedToolsSnake,
          .toolWhitelist, .toolWhitelistSnake,
        ]
      )
      profile = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .profile,
        aliases: []
      )
      model = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .model,
        aliases: [.modelOverride, .modelOverrideSnake]
      )
    }

    private static func decodeToolListIfPresent(
      from container: KeyedDecodingContainer<CodingKeys>,
      preferredKey: CodingKeys,
      aliases: [CodingKeys]
    ) throws -> [String]? {
      var firstTypeError: Error?

      for key in [preferredKey] + aliases where container.contains(key) {
        if try container.decodeNil(forKey: key) {
          continue
        }
        if let values = try? container.decode([String].self, forKey: key) {
          return values
        }
        if let rawValue = try? container.decode(String.self, forKey: key) {
          return
            rawValue
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }
        do {
          _ = try container.decode([String].self, forKey: key)
        } catch {
          firstTypeError = error
        }
      }

      if let firstTypeError {
        throw firstTypeError
      }
      return nil
    }
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["task"],
      "properties": [
        "task": [
          "type": "string",
          "description":
            "Self-contained instructions for the sub-agent. Describe the question or sub-task, name the files / symbols it should focus on, and state what the findings string should contain. The sub-agent does not see the parent conversation.",
        ],
        "tools": [
          "type": "array",
          "items": ["type": "string"],
          "description":
            "Optional whitelist of tool names from the parent's tool set. Defaults to all parent tools except `delegate`. Unknown names are dropped.",
        ],
        "model": [
          "type": "string",
          "description":
            "Optional model identifier override for the sub-agent. Defaults to the parent agent's model.",
        ],
        "profile": [
          "type": "string",
          "enum": ["rust-clippy", "rust-test", "rust-ui"],
          "description":
            "Optional predefined focused tool profile. Ignored when `tools` is supplied.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Spawn a focused sub-agent that runs in the same working directory and returns a findings string. Use for self-contained investigations (e.g. \"find every callsite of X and report how they handle Y\") so the parent's context stays focused. Sub-agents cannot delegate further.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }
    let trimmedTask = args.task.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTask.isEmpty else {
      return .failure(.invalidArguments("task is empty"))
    }
    if trimmedTask.count > Self.maxTaskLength {
      return .failure(
        .invalidArguments(
          "task exceeds the \(Self.maxTaskLength)-char limit; tighten the instructions or split the work."
        ))
    }
    guard let runner = context.delegateRunner else {
      return .failure(
        .delegateFailure(
          "delegate is not available in this context (sub-agent nesting is disabled, or the host did not wire a runner)."
        ))
    }
    do {
      let findings = try await runner.delegate(
        task: trimmedTask,
        toolNames: args.tools,
        profile: args.profile,
        modelOverride: args.model
      )
      return .ok(findings)
    } catch let error as AgentDelegateRunnerError {
      return .failure(.delegateFailure(error.errorDescription ?? "delegate failed"))
    } catch let error as AgentExecutionError {
      return .failure(.delegateFailure("sub-agent failed: \(error.localizedDescription)"))
    } catch {
      return .failure(.delegateFailure("sub-agent failed: \(error.localizedDescription)"))
    }
  }
}
