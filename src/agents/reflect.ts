import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanState, WorkspaceConfig } from "../state/types.js";
import type { SessionRecord } from "../state/sessions.js";
import { readStateText, readLessons, readCompass } from "../mcp/utils/workspace.js";
import { buildReflectSystemPrompt } from "./prompts/reflect-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { prepareCodemap } from "../repomap/index.js";
import { createPlanMcpServer } from "../mcp/server.js";

const OPUS = "claude-opus-4-7";

export interface ReflectAgentInput {
  /** Most-recent-first slice of session records. */
  recentSessions: SessionRecord[];
  /** Iteration number this Reflect pass is attached to. */
  iteration: number;
}

export interface ReflectAgentResult {
  cancelled: boolean;
  /** The state passed to set_state during this run, or null if Reflect made no change. */
  state: PlanState | null;
}

export interface ReflectAgentOptions {
  signal: AbortSignal;
}

const INITIAL_PROMPT = `Run a course-correction pass.

1. Review the recent sessions, current state, lessons, and vision in your
   system prompt. Use the codemap tools to ground observations in the actual
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

export async function runReflectAgent(
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
  const forwardAbort = () => abortController.abort();
  if (opts.signal.aborted) abortController.abort();
  else opts.signal.addEventListener("abort", forwardAbort, { once: true });

  const mcpServer = createPlanMcpServer(config, {
    onSetState: (state) => {
      capturedState = state;
    },
    onEscalate: () => {
      // Reflect is already on Opus; ignore any escalate calls (the tool isn't
      // in allowedTools anyway, but the callback shape requires this).
    },
  });

  const reflectOptions: Options = {
    systemPrompt,
    model: OPUS,
    effort: "xhigh",
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    settingSources: ["user", "project", "local"],
    abortController,
    maxTurns: 200,
    maxBudgetUsd: 6,
    mcpServers: { compass: mcpServer },
    allowedTools: [
      "Read",
      "Glob",
      "Grep",
      "LS",
      "LSP",
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
    ],
  };

  output.agentStart("Reflect", "Opus");

  let cancelled = false;
  try {
    const stream = query({ prompt: INITIAL_PROMPT, options: reflectOptions });

    for await (const message of stream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool(
              "Reflect",
              block.name,
              extractToolDetail(block.name, block.input as Record<string, unknown>)
            );
          }
        }
      }
    }

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
  }

  return { cancelled, state: capturedState };
}
