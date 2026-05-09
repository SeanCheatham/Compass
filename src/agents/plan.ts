import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig } from "../state/types.js";
import { readStateText } from "../mcp/utils/workspace.js";
import { buildPlanSystemPrompt } from "./prompts/plan-system.js";
import { createPlanMcpServer, type PlanMcpContext } from "../mcp/plan-server.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";

export interface PlanAgentInput {
  /** Snapshot of drafts.md taken by the runner (already cleared from disk). */
  drafts: string;
  /** Snapshot of feedback.md taken by the runner (already cleared from disk). */
  feedback: string;
}

export interface PlanAgentResult {
  done: boolean;
  doneReason?: string;
  /** True if the run was aborted via the signal (cancel button or shutdown). */
  cancelled: boolean;
}

export interface PlanAgentOptions {
  /** Aborts the agent mid-stream when the user cancels or the process exits. */
  signal: AbortSignal;
}

export async function runPlanAgent(
  config: WorkspaceConfig,
  input: PlanAgentInput,
  output: OutputManager,
  opts: PlanAgentOptions
): Promise<PlanAgentResult> {
  const stateJson = await readStateText(config);

  const systemPrompt = buildPlanSystemPrompt({
    stateJson,
    drafts: input.drafts,
    feedback: input.feedback,
  });
  const mcpContext: PlanMcpContext = { done: false };
  const mcpServer = createPlanMcpServer(mcpContext);

  const initialPrompt = `Run a planning iteration.

1. Review state.json (provided in your system prompt; also at .compass/state.json on disk).
2. Review the drafts and feedback snapshots in your system prompt.
3. Explore the codebase if you need to ground the plan in reality.
4. Overwrite .compass/state.json with updated Completed / Next / Follow-up.
5. If next is null AND there were no drafts to integrate, call signal_done to drop into idle.

Otherwise finish when state.json is in good shape — Develop will implement next.`;

  const abortController = new AbortController();
  if (opts.signal.aborted) abortController.abort();
  else
    opts.signal.addEventListener("abort", () => abortController.abort(), {
      once: true,
    });

  const planOptions: Options = {
    systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
    abortController,
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

  let cancelled = false;
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
    if (opts.signal.aborted) {
      cancelled = true;
      output.info("Plan cancelled.");
    } else {
      output.error(`Plan agent error: ${error}`);
      throw error;
    }
  }

  return {
    done: mcpContext.done,
    doneReason: mcpContext.doneReason,
    cancelled,
  };
}
