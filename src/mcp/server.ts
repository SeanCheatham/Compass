/**
 * In-process MCP servers for the Plan and Develop agents.
 *
 * Plan tools:
 *   - set_state(state)        — replace the full PlanState. Runner persists to disk.
 *   - read_lessons()          — read lessons.md.
 *   - set_lessons(text)       — replace lessons.md.
 *   - append_lesson(text)     — append a bullet to lessons.md.
 *
 * Develop tools:
 *   - complete({ feedback })  — signal end-of-iteration with feedback for Plan.
 *   - read_lessons()
 *   - set_lessons(text)
 *   - append_lesson(text)
 *
 * Tools close over per-run callback objects so the runner can observe set_state
 * and complete payloads without re-reading disk.
 */

import { z } from "zod";
import {
  createSdkMcpServer,
  tool,
  type McpSdkServerConfigWithInstance,
} from "@anthropic-ai/claude-agent-sdk";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import {
  appendLesson,
  readLessons,
  writeLessons,
} from "./utils/workspace.js";
import type { PlanState, WorkspaceConfig } from "../state/types.js";

const planNextSchema = z.object({
  plan: z.string().min(1, "next.plan must be a non-empty markdown string"),
  verify: z.string().min(1, "next.verify must be a non-empty shell command"),
});

const planStateSchema = z.object({
  completed: z.array(z.string()),
  next: z.union([planNextSchema, z.null()]),
  followUp: z.string(),
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
      "read_lessons",
      "Read the full contents of lessons.md (long-term memory shared across iterations). Returns an empty string if no lessons have been recorded.",
      {},
      async () => textResult(await readLessons(config))
    ),
    tool(
      "set_lessons",
      "Replace lessons.md with the given text in full. Use this when compacting or rewriting the lessons; otherwise prefer append_lesson.",
      { text: z.string() },
      async ({ text }) => {
        await writeLessons(config, text);
        return textResult("ok");
      }
    ),
    tool(
      "append_lesson",
      "Append a single lesson (a short bullet, one or two sentences) to lessons.md. Use this for the common 'I learned X this iteration' case so concurrent edits don't clobber each other.",
      { text: z.string() },
      async ({ text }) => {
        await appendLesson(config, text);
        return textResult("ok");
      }
    ),
  ];
}

export interface PlanToolCallbacks {
  /**
   * Called whenever Plan invokes set_state. The runner stores the latest call
   * and persists it after Plan finishes. Multiple calls are allowed; the last
   * one wins.
   */
  onSetState: (state: PlanState) => void;
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
        "Replace the full state.json contents with the given object. Plan calls this once it has decided the next iteration's plan and verify command. Use null for `next` when there is no concrete next step (the runner will idle).",
        planStateSchema.shape,
        async (args) => {
          const parsed = planStateSchema.parse(args);
          callbacks.onSetState(parsed);
          return textResult("ok");
        }
      ),
      ...lessonsTools(config),
    ],
  });
}

export interface DevToolCallbacks {
  /**
   * Called when Develop invokes complete. The first call wins — the runner
   * uses it as the iteration-finished signal and surfaces feedback to the
   * next Plan run. Subsequent calls are ignored (and warned about).
   */
  onComplete: (feedback: string) => void;
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
        "complete",
        "Signal that this Develop iteration is finished. Pass `feedback` for the next Plan run — discoveries that should reshape the plan, blockers, or a one-line confirmation if everything went smoothly. The runner enforces verify + clean-tree post-checks after this call.",
        { feedback: z.string() },
        async ({ feedback }) => {
          callbacks.onComplete(feedback);
          return textResult("ok");
        }
      ),
      ...lessonsTools(config),
    ],
  });
}
