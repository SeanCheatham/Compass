import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanState, WorkspaceConfig } from "../state/types.js";
import { readStateText, readLessons, readCompass } from "../mcp/utils/workspace.js";
import { buildPlanSystemPrompt } from "./prompts/plan-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { prepareCodemap } from "../repomap/index.js";
import { createPlanMcpServer } from "../mcp/server.js";

export interface PlanAgentInput {
  /** Snapshot of drafts.md taken by the runner (already cleared from disk). */
  drafts: string;
  /** Feedback from the previous Develop run's `set_feedback` call (in-memory). May be empty if Develop skipped it. */
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

/** SDK model IDs for the two Plan rungs. */
const SONNET = "claude-sonnet-4-6";
const OPUS = "claude-opus-4-7";

const INITIAL_PROMPT = `Run a planning iteration.

1. Review the current state, drafts, feedback, and lessons in your system prompt.
2. Explore the codebase if you need to ground the plan in reality.
3. Optionally call \`append_lesson\` to record anything durable for future iterations.
4. Call \`set_state\` exactly once with the full updated PlanState
   (\`completed\`, \`immediate\`, \`midTerm\`, \`longTerm\`).

Default to producing a non-null \`immediate\` every iteration. If drafts are
empty, promote the top item from \`midTerm\` — including ones marked deferred or
not user-prioritized — or originate a plan yourself from the repo, lessons,
\`completed\` history, and \`longTerm\`. Pass \`immediate: null\` only when the
project is genuinely complete (every goal hit, \`midTerm\` and \`longTerm\` both
exhausted, no obvious next increment); see the "Idling is rare" section of
your system prompt.`;

function buildOpusEscalationPrompt(message: string): string {
  return `${INITIAL_PROMPT}

---

You were just escalated from Sonnet to Opus. The Sonnet pass aborted before
calling \`set_state\` and left this note explaining why it wanted help:

> ${message.replace(/\n/g, "\n> ")}

Re-run the planning iteration from scratch with that note in mind. Anything
the Sonnet pass concluded that isn't in the note above is gone — re-derive it.
You cannot escalate further; this pass must end with a \`set_state\` call.`;
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

  try {
    const { cache, summaryResult } = await prepareCodemap(config, {
      signal: opts.signal,
    });
    if (summaryResult.generated > 0 || summaryResult.errors > 0) {
      output.info(
        `Codemap: indexed ${Object.keys(cache.files).length} files; summarized ${summaryResult.generated} (${summaryResult.skipped} skipped, ${summaryResult.errors} errors).`
      );
    }
  } catch (err) {
    output.error(`Codemap build failed: ${err}`);
  }

  const systemPrompt = buildPlanSystemPrompt({
    stateJson,
    drafts: input.drafts,
    feedback: input.feedback,
    lessons,
    vision,
  });

  let capturedState: PlanState | null = null;
  let escalationMessage: string | null = null;

  const sonnet = await runPlanPass({
    config,
    systemPrompt,
    prompt: INITIAL_PROMPT,
    model: SONNET,
    allowEscalate: true,
    signal: opts.signal,
    output,
    onSetState: (s) => {
      capturedState = s;
    },
    onEscalate: (msg) => {
      escalationMessage = msg;
    },
  });

  if (sonnet === "cancelled") {
    output.info("Plan cancelled.");
    return { cancelled: true, state: capturedState };
  }

  if (sonnet === "escalated") {
    const msg = escalationMessage ?? "(no escalation message provided)";
    output.info(`Plan escalating to Opus: ${msg}`);
    // Sonnet's state (if any) is discarded — Opus replans from scratch.
    capturedState = null;
    const opus = await runPlanPass({
      config,
      systemPrompt,
      prompt: buildOpusEscalationPrompt(msg),
      model: OPUS,
      allowEscalate: false,
      signal: opts.signal,
      output,
      onSetState: (s) => {
        capturedState = s;
      },
      onEscalate: () => {
        // Opus can't escalate further; ignore.
      },
    });
    if (opus === "cancelled") {
      output.info("Plan cancelled.");
      return { cancelled: true, state: capturedState };
    }
  }

  return { cancelled: false, state: capturedState };
}

interface PlanPassArgs {
  config: WorkspaceConfig;
  systemPrompt: string;
  prompt: string;
  model: typeof SONNET | typeof OPUS;
  /** When false, the `escalate` MCP tool is hidden from the agent. */
  allowEscalate: boolean;
  signal: AbortSignal;
  output: OutputManager;
  onSetState: (state: PlanState) => void;
  onEscalate: (message: string) => void;
}

async function runPlanPass(args: PlanPassArgs): Promise<"completed" | "cancelled" | "escalated"> {
  const {
    config,
    systemPrompt,
    prompt,
    model,
    allowEscalate,
    signal,
    output,
    onSetState,
    onEscalate,
  } = args;

  const abortController = new AbortController();
  const forwardAbort = () => abortController.abort();
  if (signal.aborted) abortController.abort();
  else signal.addEventListener("abort", forwardAbort, { once: true });

  let escalateLatched = !allowEscalate;
  // Distinguishes "we aborted because of escalate" from "user cancelled" in
  // the catch block.
  let escalatedThisPass = false;

  const mcpServer = createPlanMcpServer(config, {
    onSetState,
    onEscalate: (message) => {
      if (escalateLatched) return;
      escalateLatched = true;
      escalatedThisPass = true;
      onEscalate(message);
      abortController.abort();
    },
  });

  const baseTools = [
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
    "mcp__compass__outline",
    "mcp__compass__find_symbol",
    "mcp__compass__list_files",
    "mcp__compass__importers_of",
    "mcp__compass__summary",
    "mcp__compass__search",
  ];

  const planOptions: Options = {
    systemPrompt,
    model,
    effort: "xhigh",
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    settingSources: ["user", "project", "local"],
    abortController,
    maxTurns: 300,
    maxBudgetUsd: 8,
    mcpServers: { compass: mcpServer },
    allowedTools: allowEscalate
      ? [...baseTools, "mcp__compass__escalate"]
      : baseTools,
  };

  const label = model === OPUS ? "Opus" : "Sonnet";
  output.agentStart("Plan", label);

  try {
    const stream = query({ prompt, options: planOptions });

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
    return "completed";
  } catch (error) {
    if (escalatedThisPass) {
      // We aborted the stream ourselves on escalate. Treat as a clean handoff.
      output.agentComplete("Plan");
      return "escalated";
    }
    if (signal.aborted) {
      return "cancelled";
    }
    output.error(`Plan agent error: ${error}`);
    throw error;
  } finally {
    signal.removeEventListener("abort", forwardAbort);
  }
}
