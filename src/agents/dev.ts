import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig, Plan } from "../state/types.js";
import { readFile } from "fs/promises";
import { buildDevSystemPrompt } from "./prompts/dev-system.js";
import { createDevMcpServer, type DevMcpContext } from "../mcp/dev-server.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";

export interface DevAgentResult {
  success: boolean;
  revertReason?: string;
}

/**
 * Runs the Dev agent with READ/WRITE access to implement a specific task.
 *
 * The Dev agent:
 * - Implements the given task
 * - Verifies the implementation works
 * - Can signal revert if blocked
 * - Completes when implementation is done
 */
export async function runDevAgent(
  config: WorkspaceConfig,
  task: Plan,
  output: OutputManager
): Promise<DevAgentResult> {
  let notes = "";
  try {
    notes = await readFile(config.notesPath, "utf-8");
  } catch {
    notes = "";
  }

  const systemPrompt = buildDevSystemPrompt({
    task,
    notes,
  });

  const mcpContext: DevMcpContext = {
    reverted: false,
  };

  const mcpServer = createDevMcpServer(mcpContext);

  const initialPrompt = `

## Notes from PM

${notes || "No additional notes."}

---

Implement the following task:

${task.content}

Begin by exploring the codebase to understand the context, then implement the task.
Verify your implementation works (run tests, build, etc.) before completing.`;

  const devOptions: Options = {
    systemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
    mcpServers: {
      compass: mcpServer,
    },
    // Dev has full code access + revert signal
    allowedTools: [
      "Read",
      "Write",
      "Edit",
      "Bash",
      "Glob",
      "Grep",
      "LS",
      "LSP",
      "Agent",
      "Skill",
      "WebFetch",
      "WebSearch",
      "NotebookEdit",
      "NotebookRead",
      "mcp__compass__signal_revert",
    ],
  };

  output.agentStart("Dev", task.content);

  try {
    const devStream = query({ prompt: initialPrompt, options: devOptions });

    for await (const message of devStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool("Dev", block.name, extractToolDetail(block.name, block.input as Record<string, unknown>));
          }
        }
      }

      // Check if revert was signaled
      if (mcpContext.reverted) {
        output.agentComplete("Dev", "Reverted");
        return {
          success: false,
          revertReason: mcpContext.revertReason,
        };
      }
    }

    output.agentComplete("Dev");
  } catch (error) {
    output.error(`Dev agent error: ${error}`);
    throw error;
  }

  return {
    success: !mcpContext.reverted,
    revertReason: mcpContext.revertReason,
  };
}
