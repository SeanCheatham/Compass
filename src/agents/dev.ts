import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig } from "../state/types.js";
import { buildDevSystemPrompt } from "./prompts/dev-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";

export async function runDevAgent(
  config: WorkspaceConfig,
  next: string,
  output: OutputManager
): Promise<void> {
  const systemPrompt = buildDevSystemPrompt({ next });

  const initialPrompt = `Implement the plan in your system prompt.

When you're done — implementation working, changes committed — overwrite
\`.compass/feedback.md\` with notes for the Plan agent and finish.

If the plan can't be implemented as written, make no changes, write the reason to
\`.compass/feedback.md\`, and finish. Plan will read it and replan next iteration.`;

  const devOptions: Options = {
    systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
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
    ],
  };

  output.agentStart("Develop", next.split("\n")[0]?.slice(0, 120));

  try {
    const stream = query({ prompt: initialPrompt, options: devOptions });

    for await (const message of stream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool(
              "Develop",
              block.name,
              extractToolDetail(block.name, block.input as Record<string, unknown>)
            );
          }
        }
      }
    }

    output.agentComplete("Develop");
  } catch (error) {
    output.error(`Develop agent error: ${error}`);
    throw error;
  }
}
