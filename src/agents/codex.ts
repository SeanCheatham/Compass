import {
  Codex,
  type ThreadEvent,
  type ThreadItem,
  type ThreadOptions,
} from "@openai/codex-sdk";
import type { PlanNext, PlanState, WorkspaceConfig } from "../state/types.js";
import { normalizePlanState } from "../mcp/utils/workspace.js";
import type { OutputManager } from "../web/output-manager.js";
import type { ToolDetail } from "./tool-details.js";

export interface CodexPlanAgentInput {
  systemPrompt: string;
  prompt: string;
}

export interface CodexPlanAgentResult {
  cancelled: boolean;
  state: PlanState | null;
}

export interface CodexReflectAgentInput {
  systemPrompt: string;
  prompt: string;
}

export interface CodexReflectAgentResult {
  cancelled: boolean;
  state: PlanState | null;
}

export interface CodexDevAgentInput {
  systemPrompt: string;
  prompt: string;
  next: PlanNext;
  ctxLabel?: string;
}

export interface CodexDevAgentResult {
  cancelled: boolean;
  feedback: string | null;
  bypassVerify: boolean;
  completed: boolean;
}

const PLAN_STATE_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    completed: {
      type: "array",
      items: { type: "string" },
    },
    immediate: {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          properties: {
            plan: { type: "string" },
            verify: { type: "string" },
            verifyTimeoutMs: {
              anyOf: [{ type: "integer", minimum: 1 }, { type: "null" }],
            },
            estimatedDifficulty: {
              anyOf: [
                { type: "string", enum: ["low", "medium", "high"] },
                { type: "null" },
              ],
            },
          },
          required: [
            "plan",
            "verify",
            "verifyTimeoutMs",
            "estimatedDifficulty",
          ],
        },
        { type: "null" },
      ],
    },
    midTerm: { type: "string" },
    longTerm: { type: "string" },
  },
  required: ["completed", "immediate", "midTerm", "longTerm"],
} as const;

const REFLECT_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    state: {
      anyOf: [PLAN_STATE_OUTPUT_SCHEMA, { type: "null" }],
    },
  },
  required: ["state"],
} as const;

const DEV_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    feedback: { type: "string" },
    bypassVerify: { type: "boolean" },
  },
  required: ["feedback", "bypassVerify"],
} as const;

export async function runCodexPlanAgent(
  config: WorkspaceConfig,
  input: CodexPlanAgentInput,
  output: OutputManager,
  signal: AbortSignal
): Promise<CodexPlanAgentResult> {
  output.agentStart("Plan", "Codex");
  try {
    const turn = await runCodexStructuredTurn({
      config,
      output,
      agentName: "Plan",
      prompt: buildCodexPlanPrompt(input.systemPrompt, input.prompt),
      outputSchema: PLAN_STATE_OUTPUT_SCHEMA,
      sandboxMode: "read-only",
      effort: "xhigh",
      signal,
    });
    if (turn.cancelled) {
      output.info("Plan cancelled.");
      return { cancelled: true, state: null };
    }

    const state = parsePlanState(turn.finalResponse);
    if (!state) {
      throw new Error("Codex Plan did not return a valid PlanState JSON object.");
    }
    output.info("Codex Plan returned a structured PlanState.");
    output.agentComplete("Plan");
    return { cancelled: false, state };
  } catch (error) {
    if (signal.aborted) {
      output.info("Plan cancelled.");
      return { cancelled: true, state: null };
    }
    output.error(`Codex Plan agent error: ${error}`);
    throw error;
  }
}

export async function runCodexReflectAgent(
  config: WorkspaceConfig,
  input: CodexReflectAgentInput,
  output: OutputManager,
  signal: AbortSignal
): Promise<CodexReflectAgentResult> {
  output.agentStart("Reflect", "Codex");
  try {
    const turn = await runCodexStructuredTurn({
      config,
      output,
      agentName: "Reflect",
      prompt: buildCodexReflectPrompt(input.systemPrompt, input.prompt),
      outputSchema: REFLECT_OUTPUT_SCHEMA,
      sandboxMode: "read-only",
      effort: "xhigh",
      signal,
    });
    if (turn.cancelled) {
      output.info("Reflect cancelled.");
      return { cancelled: true, state: null };
    }

    const parsed = parseJsonObject(turn.finalResponse);
    const rawState =
      parsed && typeof parsed === "object"
        ? (parsed as Record<string, unknown>).state
        : undefined;
    const state = rawState === null ? null : normalizePlanState(rawState);
    if (rawState !== null && !state) {
      throw new Error("Codex Reflect did not return a valid state/null payload.");
    }
    output.agentComplete("Reflect");
    return { cancelled: false, state };
  } catch (error) {
    if (signal.aborted) {
      output.info("Reflect cancelled.");
      return { cancelled: true, state: null };
    }
    output.error(`Codex Reflect agent error: ${error}`);
    throw error;
  }
}

export async function runCodexDevAgent(
  config: WorkspaceConfig,
  input: CodexDevAgentInput,
  output: OutputManager,
  signal: AbortSignal
): Promise<CodexDevAgentResult> {
  const label = input.ctxLabel ? `Codex · ${input.ctxLabel}` : "Codex";
  output.agentStart("Develop", label);
  try {
    const turn = await runCodexStructuredTurn({
      config,
      output,
      agentName: "Develop",
      prompt: buildCodexDevPrompt(input.systemPrompt, input.prompt, input.next),
      outputSchema: DEV_OUTPUT_SCHEMA,
      sandboxMode: "workspace-write",
      effort: effortForDifficulty(input.next.estimatedDifficulty),
      signal,
    });
    if (turn.cancelled) {
      output.info("Develop cancelled.");
      return {
        cancelled: true,
        feedback: null,
        bypassVerify: false,
        completed: false,
      };
    }

    const final = parseDevFinal(turn.finalResponse);
    output.agentComplete("Develop");
    return {
      cancelled: false,
      feedback: final?.feedback ?? null,
      bypassVerify: final?.bypassVerify ?? false,
      completed: final !== null,
    };
  } catch (error) {
    if (signal.aborted) {
      output.info("Develop cancelled.");
      return {
        cancelled: true,
        feedback: null,
        bypassVerify: false,
        completed: false,
      };
    }
    output.error(`Codex Develop agent error: ${error}`);
    throw error;
  }
}

interface CodexTurnArgs {
  config: WorkspaceConfig;
  output: OutputManager;
  agentName: string;
  prompt: string;
  outputSchema: unknown;
  sandboxMode: ThreadOptions["sandboxMode"];
  effort: NonNullable<ThreadOptions["modelReasoningEffort"]>;
  signal: AbortSignal;
}

async function runCodexStructuredTurn(args: CodexTurnArgs): Promise<{
  cancelled: boolean;
  finalResponse: string;
}> {
  const codex = new Codex();
  const thread = codex.startThread({
    workingDirectory: args.config.implRepoPath,
    skipGitRepoCheck: false,
    sandboxMode: args.sandboxMode,
    approvalPolicy: "never",
    model: codexModel(),
    modelReasoningEffort: args.effort,
  });

  let finalResponse = "";
  const { events } = await thread.runStreamed(args.prompt, {
    outputSchema: args.outputSchema,
    signal: args.signal,
  });

  try {
    for await (const event of events) {
      handleCodexEvent(args.agentName, event, args.output);
      if (event.type === "item.completed" && event.item.type === "agent_message") {
        finalResponse = event.item.text;
      } else if (event.type === "turn.failed") {
        throw new Error(event.error.message);
      }
    }
  } catch (error) {
    if (args.signal.aborted) {
      return { cancelled: true, finalResponse };
    }
    throw error;
  }

  return { cancelled: false, finalResponse };
}

function codexModel(): string | undefined {
  const raw = process.env.COMPASS_CODEX_MODEL?.trim();
  return raw || undefined;
}

function effortForDifficulty(
  difficulty: PlanNext["estimatedDifficulty"]
): NonNullable<ThreadOptions["modelReasoningEffort"]> {
  switch (difficulty) {
    case "low":
      return "medium";
    case "high":
      return "xhigh";
    case "medium":
    case undefined:
      return "high";
  }
}

function buildCodexPlanPrompt(systemPrompt: string, prompt: string): string {
  return `You are running inside Compass through the OpenAI Codex SDK.

The Compass instructions below were originally written for the Claude Agent SDK.
Follow their planning policy and project context, but adapt the SDK-specific
mechanics this way:

- Do not call Compass MCP tools such as set_state, append_lesson, or escalate.
- Do not modify files during Plan.
- Your final answer MUST be only a JSON object matching the supplied schema.
- That JSON object is the full PlanState Compass will persist as state.json.
- Use immediate: null only when the project is genuinely complete.

## Compass Planning Instructions

${systemPrompt}

## Task

${prompt}`;
}

function buildCodexReflectPrompt(systemPrompt: string, prompt: string): string {
  return `You are running inside Compass through the OpenAI Codex SDK.

Follow the course-correction policy in the Compass instructions below, but adapt
the SDK-specific mechanics this way:

- Do not call Compass MCP tools.
- Do not modify files during Reflect.
- Your final answer MUST be only JSON: { "state": null } when no change is
  needed, or { "state": <full PlanState> } when Reflect should rewrite state.
- Preserve completed and immediate unless the Compass instructions explicitly
  justify changing them.

## Compass Reflect Instructions

${systemPrompt}

## Task

${prompt}`;
}

function buildCodexDevPrompt(
  systemPrompt: string,
  prompt: string,
  next: PlanNext
): string {
  return `You are running inside Compass through the OpenAI Codex SDK.

The Compass instructions below were originally written for the Claude Agent SDK.
Follow their development policy and project context, but adapt the SDK-specific
mechanics this way:

- Do not call Compass MCP tools such as set_feedback or signal_complete.
- Use Codex's file and shell tools to implement, verify, and commit.
- When done, your final answer MUST be only JSON matching the supplied schema:
  { "feedback": "...", "bypassVerify": false }.
- This final JSON replaces set_feedback + signal_complete. Compass will run the
  verify and clean-tree post-checks after your turn ends.
- Set bypassVerify to true only when the verify command below is wrong or
  impossible without Plan revisiting the plan. Explain why in feedback.

## Compass Develop Instructions

${systemPrompt}

## Verify Command

\`\`\`bash
${next.verify}
\`\`\`

## Task

${prompt}`;
}

function parsePlanState(text: string): PlanState | null {
  return normalizePlanState(parseJsonObject(text));
}

function parseDevFinal(text: string): {
  feedback: string;
  bypassVerify: boolean;
} | null {
  const parsed = parseJsonObject(text);
  if (!parsed || typeof parsed !== "object") return null;
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.feedback !== "string") return null;
  return {
    feedback: obj.feedback,
    bypassVerify: obj.bypassVerify === true,
  };
}

function parseJsonObject(text: string): unknown {
  const trimmed = text.trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
    if (!fenced) return null;
    try {
      return JSON.parse(fenced[1].trim());
    } catch {
      return null;
    }
  }
}

function handleCodexEvent(
  agentName: string,
  event: ThreadEvent,
  output: OutputManager
): void {
  if (event.type === "item.completed") {
    handleCodexItem(agentName, event.item, output);
  }
}

function handleCodexItem(
  agentName: string,
  item: ThreadItem,
  output: OutputManager
): void {
  switch (item.type) {
    case "agent_message":
      if (!looksLikeJson(item.text)) output.log(item.text);
      return;
    case "reasoning":
      if (item.text) output.log(item.text);
      return;
    case "command_execution":
      output.tool(agentName, "Bash", {
        summary: truncate(item.command, 60),
        full: {
          command: item.command,
          ...(item.status ? { status: item.status } : {}),
          ...(typeof item.exit_code === "number"
            ? { exitCode: String(item.exit_code) }
            : {}),
        },
      });
      return;
    case "file_change":
      output.tool(agentName, "Edit", codexFileChangeDetail(item));
      return;
    case "web_search":
      output.tool(agentName, "WebSearch", {
        summary: item.query,
        full: { query: item.query },
      });
      return;
    case "mcp_tool_call":
      output.tool(agentName, `mcp__${item.server}__${item.tool}`, {
        summary: item.tool,
        full: stringifyRecord(item.arguments ?? {}),
      });
      return;
    default:
      return;
  }
}

function codexFileChangeDetail(item: Extract<ThreadItem, { type: "file_change" }>): ToolDetail {
  const files = item.changes.map((c) => c.path).join(", ");
  return {
    summary: truncate(files || "file change", 60),
    full: {
      files,
    },
  };
}

function stringifyRecord(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {};
  const out: Record<string, string> = {};
  for (const [key, val] of Object.entries(value)) {
    if (
      typeof val === "string" ||
      typeof val === "number" ||
      typeof val === "boolean"
    ) {
      out[key] = String(val);
    }
  }
  return out;
}

function looksLikeJson(text: string): boolean {
  const trimmed = text.trim();
  return trimmed.startsWith("{") || trimmed.startsWith("```json");
}

function truncate(str: string, max: number): string {
  if (str.length <= max) return str;
  return str.slice(0, max) + "...";
}
