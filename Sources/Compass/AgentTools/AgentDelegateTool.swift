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

  struct Arguments: Codable {
    let task: String
    let tools: [String]?
    let model: String?
  }

  let spec: AgentToolSpec

  init() {
    let schema = try! AgentToolParametersSchema([
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
      return .failure("Failed to decode arguments: \(error.localizedDescription)")
    }
    let trimmedTask = args.task.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTask.isEmpty else {
      return .failure("task is empty")
    }
    if trimmedTask.count > Self.maxTaskLength {
      return .failure(
        "task exceeds the \(Self.maxTaskLength)-char limit; tighten the instructions or split the work."
      )
    }
    guard let runner = context.delegateRunner else {
      return .failure(
        "delegate is not available in this context (sub-agent nesting is disabled, or the host did not wire a runner)."
      )
    }
    do {
      let findings = try await runner.delegate(
        task: trimmedTask,
        toolNames: args.tools,
        modelOverride: args.model
      )
      return .ok(findings)
    } catch let error as AgentDelegateRunnerError {
      return .failure(error.errorDescription ?? "delegate failed")
    } catch let error as AgentExecutionError {
      return .failure("sub-agent failed: \(error.localizedDescription)")
    } catch {
      return .failure("sub-agent failed: \(error.localizedDescription)")
    }
  }
}
