import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig } from "../state/types.js";
import {
  readState,
  readDrafts,
  readFeedback,
} from "../mcp/utils/workspace.js";
import { buildPlanSystemPrompt } from "./prompts/plan-system.js";
import { createPlanMcpServer, type PlanMcpContext } from "../mcp/plan-server.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";

export interface PlanAgentResult {
  done: boolean;
  doneReason?: string;
}

export async function runPlanAgent(
  config: WorkspaceConfig,
  output: OutputManager
): Promise<PlanAgentResult> {
  const state = await readState(config);
  const drafts = await readDrafts(config);
  const feedback = await readFeedback(config);

  const systemPrompt = buildPlanSystemPrompt({ state, drafts, feedback });
  const mcpContext: PlanMcpContext = { done: false };
  const mcpServer = createPlanMcpServer(mcpContext);

  const initialPrompt = `Run a planning iteration.

1. Review state.md, drafts.md, and feedback.md (provided in your system prompt and on disk).
2. Explore the codebase if you need to ground your plan in reality.
3. Edit .compass/state.md so Completed / Next / Follow-up reflect current truth.
4. Clear .compass/drafts.md and .compass/feedback.md by overwriting them with empty content.
5. If there is nothing left to do, call signal_done to exit the loop.

Otherwise finish when state.md is in good shape — Develop will implement Next next.`;

  const planOptions: Options = {
    systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
    mcpServers: {
      compass: mcpServer,
    },
    allowedTools: [
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "LS",
      "LSP",
      "Agent",
      "Skill",
      "WebFetch",
      "WebSearch",
      "NotebookRead",
      "mcp__compass__signal_done",
    ],
  };

  output.agentStart("Plan");

  try {
    const stream = query({ prompt: initialPrompt, options: planOptions });

    for await (const message of stream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool(
              "Plan",
              block.name,
              extractToolDetail(block.name, block.input as Record<string, unknown>)
            );
          }
        }
      }
    }

    output.agentComplete("Plan", mcpContext.done ? "Done" : undefined);
  } catch (error) {
    output.error(`Plan agent error: ${error}`);
    throw error;
  }

  return {
    done: mcpContext.done,
    doneReason: mcpContext.doneReason,
  };
}
