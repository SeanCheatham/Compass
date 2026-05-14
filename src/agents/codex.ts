import {
  Codex,
  type ModelReasoningEffort,
  type SandboxMode,
  type ThreadEvent,
  type ThreadItem,
} from "@openai/codex-sdk";
import type { PlanNext, PlanState, WorkspaceConfig } from "../state/types.js";
import {
  readStateText,
  readLessons,
  readCompass,
} from "../mcp/utils/workspace.js";
import { buildPlanSystemPrompt } from "./prompts/plan-system.js";
import { buildReflectSystemPrompt } from "./prompts/reflect-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { prepareCodemap } from "../repomap/index.js";
import {
  startCodexMcpHttpServer,
} from "../mcp/codex-http-server.js";
import type {
  PlanAgentInput,
  PlanAgentOptions,
  PlanAgentResult,
} from "./plan.js";
import {
  runDevAgent,
  type DevAgentOptions,
  type DevAgentResult,
  type DevQueryArgs,
  type DevQueryResult,
} from "./dev.js";
import type {
  ReflectAgentInput,
  ReflectAgentOptions,
  ReflectAgentResult,
} from "./reflect.js";
import { buildCodexOptions, codexModelFromEnv } from "./codex-client.js";

const PLAN_INITIAL_PROMPT = `Run a planning iteration.

1. Review the current state, drafts, feedback, and lessons in your instructions.
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
your instructions.`;

const REFLECT_INITIAL_PROMPT = `Run a course-correction pass.

1. Review the recent sessions, current state, lessons, and vision in your
   instructions. Use the codemap tools to ground observations in the actual
   code where helpful.
2. Decide whether the project is on course toward the vision.
3. If everything is on course, do nothing — just say so in a short final
   message and stop. Don't call set_state defensively.
4. If you see drift, call \`set_state\` ONCE with rewritten \`midTerm\` and/or
   \`longTerm\` (passing the existing \`immediate\` and \`completed\` through
   unchanged). Optionally \`append_lesson\` if you spotted a recurring failure
   mode worth recording.

Keep the reflection tight. "On course, nothing to change" is a legitimate
outcome and is preferable to gratuitous rewrites.`;

export async function runCodexPlanAgent(
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

  const firstPass = await runCodexPlanPass({
    config,
    systemPrompt,
    prompt: PLAN_INITIAL_PROMPT,
    allowEscalate: true,
    reasoningEffort: "high",
    label: "Codex",
    signal: opts.signal,
    output,
    onSetState: (state) => {
      capturedState = state;
    },
    onEscalate: (message) => {
      escalationMessage = message;
    },
  });

  if (firstPass === "cancelled") {
    output.info("Plan cancelled.");
    return { cancelled: true, state: capturedState };
  }

  if (firstPass === "escalated") {
    const msg = escalationMessage ?? "(no escalation message provided)";
    output.info(`Plan escalating within Codex: ${msg}`);
    capturedState = null;
    const secondPass = await runCodexPlanPass({
      config,
      systemPrompt,
      prompt: buildCodexEscalationPrompt(msg),
      allowEscalate: false,
      reasoningEffort: "xhigh",
      label: "Codex · xhigh",
      signal: opts.signal,
      output,
      onSetState: (state) => {
        capturedState = state;
      },
      onEscalate: () => {},
    });
    if (secondPass === "cancelled") {
      output.info("Plan cancelled.");
      return { cancelled: true, state: capturedState };
    }
  }

  return { cancelled: false, state: capturedState };
}

export async function runCodexDevAgent(
  config: WorkspaceConfig,
  next: PlanNext,
  output: OutputManager,
  opts: DevAgentOptions
): Promise<DevAgentResult> {
  return runDevAgent(config, next, output, {
    signal: opts.signal,
    beforeSha: opts.beforeSha,
    codexSidecar: undefined,
    queryRunner: runCodexDevQuery,
  });
}

export async function runCodexReflectAgent(
  config: WorkspaceConfig,
  input: ReflectAgentInput,
  output: OutputManager,
  opts: ReflectAgentOptions
): Promise<ReflectAgentResult> {
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

  const systemPrompt = buildReflectSystemPrompt({
    stateJson,
    lessons,
    vision,
    recentSessions: input.recentSessions,
    iteration: input.iteration,
  });

  let capturedState: PlanState | null = null;
  const abortController = new AbortController();
  const forwardAbort = () => abortController.abort(opts.signal.reason);
  if (opts.signal.aborted) abortController.abort(opts.signal.reason);
  else opts.signal.addEventListener("abort", forwardAbort, { once: true });

  const mcp = await startCodexMcpHttpServer({
    role: "plan",
    config,
    allowEscalate: false,
    callbacks: {
      onSetState: (state) => {
        capturedState = state;
      },
    },
  });

  output.agentStart("Reflect", codexAgentLabel("xhigh"));
  let cancelled = false;
  try {
    await runCodexTurn({
      prompt: composeCodexPrompt(systemPrompt, REFLECT_INITIAL_PROMPT),
      cwd: config.implRepoPath,
      sandboxMode: "read-only",
      reasoningEffort: "xhigh",
      model: codexModelFromEnv("COMPASS_CODEX_REFLECT_MODEL"),
      mcpUrl: mcp.url,
      toolNames: mcp.toolNames,
      output,
      agentName: "Reflect",
      signal: abortController.signal,
    });
    output.agentComplete("Reflect");
  } catch (error) {
    if (opts.signal.aborted) {
      cancelled = true;
      output.info("Reflect cancelled.");
    } else {
      output.error(`Reflect agent error: ${error}`);
      throw error;
    }
  } finally {
    opts.signal.removeEventListener("abort", forwardAbort);
    await mcp.close();
  }

  return { cancelled, state: capturedState };
}

interface CodexPlanPassArgs {
  config: WorkspaceConfig;
  systemPrompt: string;
  prompt: string;
  allowEscalate: boolean;
  reasoningEffort: ModelReasoningEffort;
  label: string;
  signal: AbortSignal;
  output: OutputManager;
  onSetState: (state: PlanState) => void;
  onEscalate: (message: string) => void;
}

async function runCodexPlanPass(
  args: CodexPlanPassArgs
): Promise<"completed" | "cancelled" | "escalated"> {
  const abortController = new AbortController();
  const forwardAbort = () => abortController.abort(args.signal.reason);
  if (args.signal.aborted) abortController.abort(args.signal.reason);
  else args.signal.addEventListener("abort", forwardAbort, { once: true });

  let escalateLatched = !args.allowEscalate;
  let escalatedThisPass = false;

  const mcp = await startCodexMcpHttpServer({
    role: "plan",
    config: args.config,
    allowEscalate: args.allowEscalate,
    callbacks: {
      onSetState: args.onSetState,
      onEscalate: (message) => {
        if (escalateLatched) return;
        escalateLatched = true;
        escalatedThisPass = true;
        args.onEscalate(message);
        setTimeout(() => abortController.abort(new Error("Codex Plan escalated.")), 50);
      },
    },
  });

  args.output.agentStart("Plan", args.label);

  try {
    await runCodexTurn({
      prompt: composeCodexPrompt(args.systemPrompt, args.prompt),
      cwd: args.config.implRepoPath,
      sandboxMode: "read-only",
      reasoningEffort: args.reasoningEffort,
      model: codexModelFromEnv("COMPASS_CODEX_PLAN_MODEL"),
      mcpUrl: mcp.url,
      toolNames: mcp.toolNames,
      output: args.output,
      agentName: "Plan",
      signal: abortController.signal,
    });
    args.output.agentComplete("Plan");
    return escalatedThisPass ? "escalated" : "completed";
  } catch (error) {
    if (escalatedThisPass) {
      args.output.agentComplete("Plan");
      return "escalated";
    }
    if (args.signal.aborted) {
      return "cancelled";
    }
    args.output.error(`Plan agent error: ${error}`);
    throw error;
  } finally {
    args.signal.removeEventListener("abort", forwardAbort);
    await mcp.close();
  }
}

async function runCodexDevQuery(args: DevQueryArgs): Promise<DevQueryResult> {
  const abortController = new AbortController();
  const forwardAbort = () => abortController.abort(args.signal.reason);
  if (args.signal.aborted) abortController.abort(args.signal.reason);
  else args.signal.addEventListener("abort", forwardAbort, { once: true });

  let capturedFeedback: string | null = null;
  let capturedBypassVerify = false;
  let signaledComplete = false;
  let completedNormally = false;

  const mcp = await startCodexMcpHttpServer({
    role: "develop",
    config: args.config,
    callbacks: {
      onSetFeedback: (text) => {
        capturedFeedback = text;
      },
      onSignalComplete: ({ bypassVerify }) => {
        if (signaledComplete) return;
        signaledComplete = true;
        capturedBypassVerify = bypassVerify;
        completedNormally = true;
        if (bypassVerify) {
          args.output.info(
            "Develop requested bypassVerify=true — verify post-check will be skipped this iteration."
          );
        }
        setTimeout(
          () => abortController.abort(new Error("Codex Develop signaled complete.")),
          50
        );
      },
    },
  });

  const effort = pickCodexDevEffort(args.next.estimatedDifficulty);
  const fullLabel = args.ctxLabel
    ? `${codexAgentLabel(effort)} · ${args.ctxLabel}`
    : codexAgentLabel(effort);
  args.output.agentStart("Develop", fullLabel);

  try {
    await runCodexTurn({
      prompt: composeCodexPrompt(args.systemPrompt, args.prompt),
      cwd: args.config.implRepoPath,
      sandboxMode: "danger-full-access",
      reasoningEffort: effort,
      model: codexModelFromEnv("COMPASS_CODEX_DEV_MODEL"),
      mcpUrl: mcp.url,
      toolNames: mcp.toolNames,
      output: args.output,
      agentName: "Develop",
      signal: abortController.signal,
    });
    args.output.agentComplete("Develop");
    return {
      cancelled: false,
      feedback: capturedFeedback,
      cutOff: signaledComplete ? null : "no_complete",
      bypassVerify: capturedBypassVerify,
    };
  } catch (error) {
    if (completedNormally) {
      args.output.agentComplete("Develop");
      return {
        cancelled: false,
        feedback: capturedFeedback,
        cutOff: null,
        bypassVerify: capturedBypassVerify,
      };
    }
    if (args.signal.aborted) {
      args.output.info("Develop cancelled.");
      return {
        cancelled: true,
        feedback: capturedFeedback,
        cutOff: signaledComplete ? null : "no_complete",
        bypassVerify: capturedBypassVerify,
      };
    }
    args.output.error(`Develop agent error: ${error}`);
    throw error;
  } finally {
    args.signal.removeEventListener("abort", forwardAbort);
    await mcp.close();
  }
}

interface RunCodexTurnArgs {
  prompt: string;
  cwd: string;
  sandboxMode: SandboxMode;
  reasoningEffort: ModelReasoningEffort;
  model: string | undefined;
  mcpUrl: string;
  toolNames: string[];
  output: OutputManager;
  agentName: string;
  signal: AbortSignal;
}

async function runCodexTurn(args: RunCodexTurnArgs): Promise<void> {
  const codex = new Codex(
    buildCodexOptions({
      mcpUrl: args.mcpUrl,
      toolNames: args.toolNames,
    })
  );
  const thread = codex.startThread({
    workingDirectory: args.cwd,
    sandboxMode: args.sandboxMode,
    approvalPolicy: "never",
    modelReasoningEffort: args.reasoningEffort,
    ...(args.model ? { model: args.model } : {}),
    ...(args.sandboxMode === "read-only" ? {} : { networkAccessEnabled: true }),
  });

  const { events } = await thread.runStreamed(args.prompt, {
    signal: args.signal,
  });

  for await (const event of events) {
    handleCodexEvent(event, args.output, args.agentName);
  }
}

function handleCodexEvent(
  event: ThreadEvent,
  output: OutputManager,
  agentName: string
): void {
  if (event.type === "turn.failed") {
    throw new Error(event.error.message);
  }
  if (event.type === "error") {
    throw new Error(event.message);
  }
  if (event.type === "item.started") {
    handleStartedItem(event.item, output, agentName);
    return;
  }
  if (event.type === "item.completed") {
    handleCompletedItem(event.item, output, agentName);
  }
}

function handleStartedItem(
  item: ThreadItem,
  output: OutputManager,
  agentName: string
): void {
  if (item.type === "mcp_tool_call") {
    const toolName = `mcp__${item.server}__${item.tool}`;
    output.tool(
      agentName,
      toolName,
      extractToolDetail(toolName, recordFromUnknown(item.arguments))
    );
  } else if (item.type === "command_execution") {
    output.tool(
      agentName,
      "Bash",
      extractToolDetail("Bash", { command: item.command })
    );
  } else if (item.type === "web_search") {
    output.tool(
      agentName,
      "WebSearch",
      extractToolDetail("WebSearch", { query: item.query })
    );
  }
}

function handleCompletedItem(
  item: ThreadItem,
  output: OutputManager,
  agentName: string
): void {
  if (item.type === "agent_message") {
    output.log(item.text);
  } else if (item.type === "file_change") {
    const summary = item.changes
      .map((change) => `${change.kind} ${change.path}`)
      .join(", ");
    output.tool(agentName, "Edit", {
      summary,
      full: {
        changes: summary,
        status: item.status,
      },
    });
  } else if (item.type === "command_execution" && item.status === "failed") {
    output.error(
      `Command failed: ${item.command}\n${tail(item.aggregated_output, 2000)}`
    );
  } else if (item.type === "mcp_tool_call" && item.status === "failed") {
    output.error(
      `MCP tool ${item.server}.${item.tool} failed: ${item.error?.message ?? "unknown error"}`
    );
  } else if (item.type === "error") {
    output.error(item.message);
  }
}

function composeCodexPrompt(systemPrompt: string, prompt: string): string {
  return `Treat the following Compass instructions as the controlling instructions for this run.

<compass_instructions>
${systemPrompt}
</compass_instructions>

<task>
${prompt}
</task>`;
}

function buildCodexEscalationPrompt(message: string): string {
  return `${PLAN_INITIAL_PROMPT}

---

You were just escalated from the default Codex planning pass to a higher
reasoning pass. The first pass aborted before calling \`set_state\` and left
this note explaining why it wanted help:

> ${message.replace(/\n/g, "\n> ")}

Re-run the planning iteration from scratch with that note in mind. Anything
the first pass concluded that isn't in the note above is gone — re-derive it.
You cannot escalate further; this pass must end with a \`set_state\` call.`;
}

function pickCodexDevEffort(
  difficulty: PlanNext["estimatedDifficulty"]
): ModelReasoningEffort {
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

function codexAgentLabel(effort: ModelReasoningEffort): string {
  return `Codex · ${effort}`;
}

function recordFromUnknown(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function tail(text: string, max: number): string {
  if (text.length <= max) return text;
  return "…(truncated)…\n" + text.slice(-max);
}
