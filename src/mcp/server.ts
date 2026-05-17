/**
 * In-process MCP servers for the Plan and Develop agents.
 *
 * Plan tools:
 *   - set_state(state)        — replace the full PlanState (completed,
 *                               immediate, midTerm, longTerm). Runner persists.
 *   - edit_lessons(...)       — exact find/replace edits to lessons.md.
 *
 * Develop tools:
 *   - set_feedback({ text })  — set/replace the feedback string handed to the
 *                               next Plan run. Optional but strongly encouraged.
 *                               Last call wins.
 *   - signal_complete({ bypassVerify? })
 *                             — exactly-once end-of-iteration signal. Aborts
 *                               the stream so the runner moves to post-checks.
 *   - edit_lessons(...)
 *
 * Tools close over per-run callback objects so the runner can observe set_state,
 * set_feedback, and signal_complete payloads without re-reading disk.
 */

import { z } from "zod";
import {
  createSdkMcpServer,
  tool,
  type McpSdkServerConfigWithInstance,
} from "@anthropic-ai/claude-agent-sdk";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { editLessons } from "./utils/workspace.js";
import { codemapToolDefinitions } from "./codemap-tools.js";
import type { PlanState, WorkspaceConfig } from "../state/types.js";

const planNextSchema = z.object({
  plan: z.string().min(1, "immediate.plan must be a non-empty markdown string"),
  verify: z.string().min(1, "immediate.verify must be a non-empty shell command"),
  verifyTimeoutMs: z.number().int().positive().optional(),
  estimatedDifficulty: z.enum(["low", "medium", "high"]).optional(),
});

const planStateSchema = z.object({
  completed: z.array(z.string()),
  immediate: z.union([planNextSchema, z.null()]),
  midTerm: z.string(),
  longTerm: z.string(),
});

function textResult(text: string, isError = false): CallToolResult {
  return {
    content: [{ type: "text", text }],
    ...(isError ? { isError: true } : {}),
  };
}

function lessonsTools(config: WorkspaceConfig) {
  return [
    tool(
      "edit_lessons",
      "Edit lessons.md with exact find/replace mechanics. The current file is already shown in your prompt. `find` must match the current contents exactly; if it occurs multiple times, provide more surrounding context or set `replaceAll=true`. To append, replace the final relevant block with that block plus the new bullet. If lessons.md is empty, use an empty `find` to create its initial contents.",
      {
        find: z.string(),
        replace: z.string(),
        replaceAll: z.boolean().optional(),
      },
      async ({ find, replace, replaceAll }) => {
        const result = await editLessons(config, { find, replace, replaceAll });
        return textResult(
          `ok: replaced ${result.replacements} occurrence${result.replacements === 1 ? "" : "s"}; lessons.md is ${result.bytes} bytes.`
        );
      }
    ),
  ];
}

function codemapTools(config: WorkspaceConfig) {
  return codemapToolDefinitions(config).map((def) =>
    tool(def.name, def.description, def.inputSchema, def.handler)
  );
}

export interface PlanToolCallbacks {
  /**
   * Called whenever Plan invokes set_state. The runner stores the latest call
   * and persists it after Plan finishes. Multiple calls are allowed; the last
   * one wins.
   */
  onSetState: (state: PlanState) => void;
  /**
   * Called when Plan invokes `escalate`. First call wins — the runner aborts
   * the current Sonnet stream and restarts the iteration with Opus, threading
   * `message` through as context. Subsequent calls (including any during the
   * Opus pass) are ignored.
   */
  onEscalate: (message: string) => void;
}

export function createPlanMcpServer(
  config: WorkspaceConfig,
  callbacks: PlanToolCallbacks
): McpSdkServerConfigWithInstance {
  return createSdkMcpServer({
    name: "compass-plan",
    version: "0.1.0",
    tools: [
      tool(
        "set_state",
        "Replace the full state.json contents with the given object. Plan calls this once it has decided the iteration's three horizons: `immediate` (the {plan,verify,estimatedDifficulty?} Develop runs this iteration), `midTerm` (markdown sketch of the next ~3-7 iterations — the promotion queue), and `longTerm` (markdown sketch of the strategic arc, ~10+ iterations out). Use null for `immediate` only when the project is genuinely complete; the runner will idle.",
        planStateSchema.shape,
        async (args) => {
          const parsed = planStateSchema.parse(args);
          callbacks.onSetState(parsed);
          return textResult("ok");
        }
      ),
      tool(
        "escalate",
        "Escalate this planning iteration to Opus. Call this when Sonnet (the default Plan model) is out of its depth: the strategic picture is unclear, drafts conflict in ways you can't reconcile, the codebase reality contradicts what feedback implied, or you're about to set_state on a plan you don't have confidence in. The runner aborts your current stream and restarts the iteration from scratch with Opus, threading your `message` through as context — anything you've already concluded must be summarised there. Call this BEFORE `set_state`: any state you set in the Sonnet pass is discarded when the Opus pass starts. First call wins; subsequent escalates are ignored.",
        { message: z.string().min(1, "escalate.message must be non-empty") },
        async ({ message }) => {
          callbacks.onEscalate(message);
          return textResult("ok");
        }
      ),
      ...lessonsTools(config),
      ...codemapTools(config),
    ],
  });
}

export interface DevSignalCompletePayload {
  /**
   * When true, the runner skips the verify post-check for this iteration. Use
   * sparingly — only when Develop has determined that the verify command as
   * written can't pass without Plan revisiting the plan (e.g. wrong command,
   * impossible assertion, missing dependency that's out of scope). The
   * clean-tree post-check still applies. Defaults to false.
   */
  bypassVerify: boolean;
}

export interface DevToolCallbacks {
  /**
   * Called whenever Develop invokes set_feedback. Last call wins — the runner
   * stores the most recent text and surfaces it to the next Plan run when the
   * iteration ends. Optional from the agent's side; if never called, Plan
   * sees no feedback and continues from state alone.
   */
  onSetFeedback: (text: string) => void;
  /**
   * Called when Develop invokes signal_complete. The first call wins — the
   * runner uses it as the iteration-finished signal. Subsequent calls are
   * ignored.
   */
  onSignalComplete: (payload: DevSignalCompletePayload) => void;
}

export function createDevMcpServer(
  config: WorkspaceConfig,
  callbacks: DevToolCallbacks
): McpSdkServerConfigWithInstance {
  return createSdkMcpServer({
    name: "compass-dev",
    version: "0.1.0",
    tools: [
      tool(
        "set_feedback",
        "Set the feedback string handed to the next Plan run. STRONGLY recommended — Plan uses it to decide what to plan next. Pass discoveries that should reshape the plan, blockers, or a one-line confirmation if everything went smoothly. Call this BEFORE `signal_complete`. Last call wins; calling again replaces the prior text. Soft cap: 3 KB. If you skip this entirely, Plan will see no feedback and just continue from state alone.",
        { text: z.string() },
        async ({ text }) => {
          callbacks.onSetFeedback(text);
          return textResult("ok");
        }
      ),
      tool(
        "signal_complete",
        "Signal that this Develop iteration is finished. Call this exactly once, as your FINAL action — the runner aborts the stream right after this call returns and moves to post-checks (verify + clean tree). Set `bypassVerify: true` ONLY when you have determined mid-implementation that the verify command in the plan can't pass without Plan replanning (e.g. the command is wrong, asserts something impossible, or needs an out-of-scope dependency); the runner will skip the verify post-check (clean-tree still applies) and route your feedback straight to Plan. Always call `set_feedback` first to explain.",
        { bypassVerify: z.boolean().optional() },
        async ({ bypassVerify }) => {
          callbacks.onSignalComplete({ bypassVerify: bypassVerify ?? false });
          return textResult(
            "Iteration complete. The runner has captured your signal and will terminate this stream momentarily. Do not take any further action; any subsequent assistant text or tool calls will be discarded."
          );
        }
      ),
      ...lessonsTools(config),
      ...codemapTools(config),
    ],
  });
}
