import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanState, WorkspaceConfig } from "../state/types.js";
import { readStateText, readLessons, readCompass } from "../mcp/utils/workspace.js";
import { buildPlanSystemPrompt } from "./prompts/plan-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { buildRepoMap } from "../repomap/index.js";
import { createPlanMcpServer } from "../mcp/server.js";

export interface PlanAgentInput {
  /** Snapshot of drafts.md taken by the runner (already cleared from disk). */
  drafts: string;
  /** Feedback from the previous Develop run's `complete()` call (in-memory). */
  feedback: string;
}

export interface PlanAgentResult {
  /** True if the run was aborted via the signal (cancel button or shutdown). */
  cancelled: boolean;
  /**
   * The latest PlanState passed to set_state during this run. Null if Plan
   * never called set_state. The runner is responsible for persisting it.
   */
  state: PlanState | null;
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
  const lessons = await readLessons(config);
  const vision = await readCompass(config);

  let repoMap = "";
  try {
    repoMap = await buildRepoMap(config);
  } catch (err) {
    output.error(`Repo map build failed: ${err}`);
  }

  const systemPrompt = buildPlanSystemPrompt({
    stateJson,
    drafts: input.drafts,
    feedback: input.feedback,
    lessons,
    vision,
    repoMap,
  });

  const initialPrompt = `Run a planning iteration.

1. Review the current state, drafts, feedback, and lessons in your system prompt.
2. Explore the codebase if you need to ground the plan in reality.
3. Optionally call \`append_lesson\` to record anything durable for future iterations.
4. Call \`set_state\` exactly once with the full updated PlanState.

Default to producing a non-null \`next\` every iteration. If drafts are empty,
promote the most useful \`followUp\` item — including ones marked deferred or
not user-prioritized — or originate a plan yourself from the repo, lessons,
and \`completed\` history. Pass \`next: null\` only when the project is genuinely
complete (every goal hit, no useful followUp, no obvious next increment); see
the "Idling is rare" section of your system prompt.`;

  let capturedState: PlanState | null = null;
  const mcpServer = createPlanMcpServer(config, {
    onSetState: (state) => {
      capturedState = state;
    },
  });

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
    mcpServers: { compass: mcpServer },
    allowedTools: [
      "Read",
      "Glob",
      "Grep",
      "LS",
      "LSP",
      "Agent",
      "Skill",
      "WebFetch",
      "WebSearch",
      "NotebookRead",
      "mcp__compass__set_state",
      "mcp__compass__read_lessons",
      "mcp__compass__set_lessons",
      "mcp__compass__append_lesson",
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

    output.agentComplete("Plan");
  } catch (error) {
    if (opts.signal.aborted) {
      cancelled = true;
      output.info("Plan cancelled.");
    } else {
      output.error(`Plan agent error: ${error}`);
      throw error;
    }
  }

  return { cancelled, state: capturedState };
}
