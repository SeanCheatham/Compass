import { exec } from "node:child_process";
import { promisify } from "node:util";
import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanNext, WorkspaceConfig } from "../state/types.js";
import { buildDevSystemPrompt } from "./prompts/dev-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { readLessons, readCompass } from "../mcp/utils/workspace.js";
import { createDevMcpServer } from "../mcp/server.js";
import { prepareCodemap } from "../repomap/index.js";
import type { VerifyOutput } from "../state/sessions.js";

const execAsync = promisify(exec);

const MAX_ATTEMPTS = 3;
const DEFAULT_VERIFY_TIMEOUT_MS = 10 * 60 * 1000;

/**
 * Why the Develop query stream ended without `signal_complete()` being called.
 * - "budget"      — SDK reported `error_max_budget_usd`.
 * - "turns"       — SDK reported `error_max_turns`.
 * - "no_complete" — Stream ended (success or other error) but the agent never
 *                   called the `signal_complete` MCP tool.
 *
 * Any of these triggers a single follow-up Cleanup pass before yielding to Plan.
 */
type CutOffReason = "budget" | "turns" | "no_complete";

function describeCutOff(reason: CutOffReason): string {
  switch (reason) {
    case "budget":
      return "ran out of its per-attempt USD budget";
    case "turns":
      return "hit its per-attempt turn limit";
    case "no_complete":
      return "ended without calling `signal_complete`";
  }
}

function getVerifyTimeoutMs(): number {
  const raw = process.env.COMPASS_VERIFY_TIMEOUT_MS;
  if (!raw) return DEFAULT_VERIFY_TIMEOUT_MS;
  const parsed = parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_VERIFY_TIMEOUT_MS;
  return parsed;
}

interface PostCheckResult {
  ok: boolean;
  /** Issues fed back to Develop as the retry prompt (includes verify-tail). */
  retryIssues: string[];
  /** Issues surfaced as session notes (excludes the verify-failure dup). */
  displayIssues: string[];
  /** Populated only when verify failed; null otherwise. */
  verifyOutput: VerifyOutput | null;
}

export interface DevAgentOptions {
  /** Aborts the agent mid-stream when the user cancels or the process exits. */
  signal: AbortSignal;
}

export interface DevAgentResult {
  /** True if at least one Develop attempt finished with both post-checks green. */
  succeeded: boolean;
  /** True if the run was cancelled (Ctrl+C or UI cancel). */
  cancelled: boolean;
  /**
   * Display issues to be addNote'd on the session — i.e. everything except the
   * verify-failure entry, which is now surfaced separately via `verifyOutput`.
   * Empty when succeeded.
   */
  issues: string[];
  /**
   * Verify-failure detail from the final post-check (the one whose result
   * decided the loop's outcome). Null on success and on cancellations that
   * never reached the verify step.
   */
  verifyOutput: VerifyOutput | null;
  /**
   * Feedback string from the last `set_feedback` call, threaded into the next
   * Plan run. Empty if Develop never called set_feedback (Plan continues from
   * state alone).
   */
  feedback: string;
}

export async function runDevAgent(
  config: WorkspaceConfig,
  next: PlanNext,
  output: OutputManager,
  opts: DevAgentOptions
): Promise<DevAgentResult> {
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

  const systemPrompt = buildDevSystemPrompt({ next, lessons, vision });

  let priorRetryIssues: string[] = [];
  let lastDisplayIssues: string[] = [];
  let lastVerifyOutput: VerifyOutput | null = null;
  let lastFeedback = "";
  let cutOffReason: CutOffReason | null = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    if (opts.signal.aborted) {
      return {
        succeeded: false,
        cancelled: true,
        issues: lastDisplayIssues,
        verifyOutput: lastVerifyOutput,
        feedback: lastFeedback,
      };
    }

    const initialPrompt = buildDevPrompt(attempt, priorRetryIssues);
    const ctxLabel =
      attempt === 1
        ? next.plan.split("\n")[0]?.slice(0, 120)
        : `Retry ${attempt}/${MAX_ATTEMPTS}`;
    const queryResult = await runDevQuery(
      config,
      systemPrompt,
      initialPrompt,
      next,
      output,
      ctxLabel,
      opts.signal
    );
    if (queryResult.cancelled) {
      return {
        succeeded: false,
        cancelled: true,
        issues: lastDisplayIssues,
        verifyOutput: lastVerifyOutput,
        feedback: lastFeedback,
      };
    }
    if (queryResult.feedback !== null) {
      lastFeedback = queryResult.feedback;
    }

    // If the stream was cut off (budget / turns / never called signal_complete),
    // skip the normal post-check retry path. A single dedicated Cleanup pass
    // below will try to wrap up the in-flight work before yielding to Plan.
    if (queryResult.cutOff) {
      cutOffReason = queryResult.cutOff;
      output.info(
        `Develop ${describeCutOff(queryResult.cutOff)}. Skipping further retries; running Cleanup pass next.`
      );
      break;
    }

    const post = await runPostChecks(
      config,
      next.verify,
      output,
      true,
      queryResult.bypassVerify,
      next.verifyTimeoutMs
    );
    lastDisplayIssues = post.displayIssues;
    lastVerifyOutput = post.verifyOutput;
    if (post.ok) {
      return {
        succeeded: true,
        cancelled: false,
        issues: [],
        verifyOutput: null,
        feedback: lastFeedback,
      };
    }

    priorRetryIssues = post.retryIssues;

    if (attempt === MAX_ATTEMPTS) {
      output.error(
        `Develop post-checks still failing after ${MAX_ATTEMPTS} attempts. Moving on; Plan will see the feedback next iteration.`
      );
      return {
        succeeded: false,
        cancelled: false,
        issues: lastDisplayIssues,
        verifyOutput: lastVerifyOutput,
        feedback: lastFeedback,
      };
    }

    output.info(
      `Develop post-checks failed (attempt ${attempt}/${MAX_ATTEMPTS}). Re-prompting.`
    );
  }

  // Cleanup pass — runs at most once per Dev invocation, only when the prior
  // attempt was cut off mid-task (budget/turns/no-complete). Fresh budget,
  // bounded scope: finish the in-flight work or revert to a clean state, then
  // call complete so the next Plan run gets context.
  if (cutOffReason) {
    const cleanupPrompt = buildCleanupPrompt(cutOffReason);
    const cleanupResult = await runDevQuery(
      config,
      systemPrompt,
      cleanupPrompt,
      next,
      output,
      "Cleanup",
      opts.signal
    );
    if (cleanupResult.cancelled) {
      return {
        succeeded: false,
        cancelled: true,
        issues: lastDisplayIssues,
        verifyOutput: lastVerifyOutput,
        feedback: lastFeedback,
      };
    }
    if (cleanupResult.feedback !== null) {
      lastFeedback = cleanupResult.feedback;
    }

    const post = await runPostChecks(
      config,
      next.verify,
      output,
      cleanupResult.cutOff === null,
      cleanupResult.bypassVerify,
      next.verifyTimeoutMs
    );
    lastDisplayIssues = post.displayIssues;
    lastVerifyOutput = post.verifyOutput;
    if (post.ok) {
      return {
        succeeded: true,
        cancelled: false,
        issues: [],
        verifyOutput: null,
        feedback: lastFeedback,
      };
    }
    output.error(
      "Cleanup pass finished but post-checks still failing. Yielding to Plan."
    );
    return {
      succeeded: false,
      cancelled: false,
      issues: lastDisplayIssues,
      verifyOutput: lastVerifyOutput,
      feedback: lastFeedback,
    };
  }

  return {
    succeeded: false,
    cancelled: false,
    issues: lastDisplayIssues,
    verifyOutput: lastVerifyOutput,
    feedback: lastFeedback,
  };
}

function buildDevPrompt(attempt: number, priorIssues: string[]): string {
  if (attempt === 1) {
    return `Implement the plan in your system prompt.

When you're done — implementation working, verify command passing, changes committed —
call \`set_feedback\` with a short note for the next Plan run, then call
\`signal_complete\` as your final action.

If the plan can't be implemented as written, make no changes, call \`set_feedback\`
with the reason, then call \`signal_complete\`. Plan will read the feedback and
replan next iteration.`;
  }

  return `Your previous attempt left these post-check failures unresolved:

${priorIssues.map((i, idx) => `${idx + 1}. ${i}`).join("\n\n")}

Fix them now and finish with a \`signal_complete\` call (call \`set_feedback\`
first to leave a note for Plan). Do not stop until the verify command exits 0,
\`git status --porcelain\` is empty, and you have called \`signal_complete\`.`;
}

function buildCleanupPrompt(reason: CutOffReason): string {
  return `Your previous attempt ${describeCutOff(reason)} mid-task. The working
tree may contain partial edits, uncommitted changes, or half-finished work from
that attempt.

This is a CLEANUP pass — your job is to wrap up the in-flight work so the next
Plan run gets a clean handoff. Do NOT expand scope or start anything new.

1. Run \`git status\` and \`git diff\` to see what state the previous attempt
   left behind. Read any partially-edited files.
2. Decide between two paths and execute it:
   a) FINISH — if the remaining work is small and clear, complete it: get the
      verify command passing, commit, then call \`set_feedback\` to summarise
      what shipped and \`signal_complete\` to end the iteration.
   b) REVERT — if finishing would be too large or risky for one more pass,
      undo the partial work (\`git restore\`, \`git clean -fd\` for untracked
      files) until \`git status --porcelain\` is empty, then call \`set_feedback\`
      to explain what was attempted and what's still outstanding so Plan can
      downsize the scope next iteration, and \`signal_complete\` to end.
3. Either way you MUST end with a \`signal_complete\` call (after \`set_feedback\`)
   and leave \`git status --porcelain\` empty. There are no more retries after
   this pass.

Keep this attempt tight. Don't risk a second budget exhaustion — pick the
quicker of FINISH or REVERT when in doubt.`;
}

async function runDevQuery(
  config: WorkspaceConfig,
  systemPrompt: string,
  prompt: string,
  next: PlanNext,
  output: OutputManager,
  /** Short label rendered next to "Develop" in the activity stream. */
  ctxLabel: string | undefined,
  signal: AbortSignal
): Promise<{
  cancelled: boolean;
  feedback: string | null;
  /** Non-null when the stream ended without `signal_complete` being called. */
  cutOff: CutOffReason | null;
  /** Whether `signal_complete` was called with bypassVerify=true. */
  bypassVerify: boolean;
}> {
  const abortController = new AbortController();
  if (signal.aborted) abortController.abort();
  else signal.addEventListener("abort", () => abortController.abort(), { once: true });

  let capturedFeedback: string | null = null;
  let capturedBypassVerify = false;
  let signaledComplete = false;
  // Distinguishes "stream ended because we aborted on signal_complete" from
  // "stream ended because the user cancelled" in the catch block below.
  let completedNormally = false;
  const mcpServer = createDevMcpServer(config, {
    onSetFeedback: (text) => {
      // Last call wins — the agent may refine the feedback before completing.
      capturedFeedback = text;
    },
    onSignalComplete: ({ bypassVerify }) => {
      // First call wins; subsequent calls in the same attempt are ignored.
      if (signaledComplete) return;
      signaledComplete = true;
      capturedBypassVerify = bypassVerify;
      if (bypassVerify) {
        output.info(
          "Develop requested bypassVerify=true — verify post-check will be skipped this iteration."
        );
      }
      // End the stream as soon as Develop signals done. Without this the SDK
      // keeps spinning and the model frequently re-calls signal_complete
      // (seeing the bland "ok" result, it second-guesses itself and burns
      // budget on retries the runner can't even use — first call already won).
      completedNormally = true;
      abortController.abort();
    },
  });

  const devOptions: Options = {
    systemPrompt,
    model: "claude-sonnet-4-6",
    fallbackModel: "claude-opus-4-7",
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    settingSources: ["user", "project", "local"],
    abortController,
    maxTurns: 300,
    maxBudgetUsd: 8,
    mcpServers: { compass: mcpServer },
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
      "mcp__compass__set_feedback",
      "mcp__compass__signal_complete",
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

  output.agentStart("Develop", ctxLabel);

  let lastResultSubtype: string | null = null;

  try {
    const stream = query({ prompt, options: devOptions });

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
      } else if (message.type === "result") {
        lastResultSubtype = message.subtype;
      }
    }

    output.agentComplete("Develop");
    return {
      cancelled: false,
      feedback: capturedFeedback,
      cutOff: deriveCutOff(signaledComplete, lastResultSubtype),
      bypassVerify: capturedBypassVerify,
    };
  } catch (error) {
    if (completedNormally) {
      // We aborted the stream ourselves because Develop called signal_complete.
      // Treat as a clean end-of-iteration, not a cancellation.
      output.agentComplete("Develop");
      return {
        cancelled: false,
        feedback: capturedFeedback,
        cutOff: null,
        bypassVerify: capturedBypassVerify,
      };
    }
    if (signal.aborted) {
      output.info("Develop cancelled.");
      return {
        cancelled: true,
        feedback: capturedFeedback,
        cutOff: deriveCutOff(signaledComplete, lastResultSubtype),
        bypassVerify: capturedBypassVerify,
      };
    }
    output.error(`Develop agent error: ${error}`);
    throw error;
  }
}

function deriveCutOff(
  signaledComplete: boolean,
  resultSubtype: string | null
): CutOffReason | null {
  // If the agent called signal_complete, trust it — the iteration is "done"
  // from its perspective and the normal post-checks (verify, clean tree)
  // decide whether the work is actually good. Cleanup is only for the case
  // where the stream ended before the agent could wrap up.
  if (signaledComplete) return null;
  if (resultSubtype === "error_max_budget_usd") return "budget";
  if (resultSubtype === "error_max_turns") return "turns";
  return "no_complete";
}

async function runPostChecks(
  config: WorkspaceConfig,
  verifyCommand: string,
  output: OutputManager,
  signaledComplete: boolean,
  bypassVerify: boolean,
  verifyTimeoutMsOverride: number | undefined
): Promise<PostCheckResult> {
  const retryIssues: string[] = [];
  const displayIssues: string[] = [];
  let verifyOutput: VerifyOutput | null = null;

  if (!signaledComplete) {
    const msg =
      "Develop ended without calling the `signal_complete` MCP tool. Every iteration must finish by calling `signal_complete()` as its final action (after optionally leaving a note via `set_feedback`).";
    retryIssues.push(msg);
    displayIssues.push(msg);
    output.error("Develop did not call `signal_complete`.");
  }

  if (bypassVerify) {
    output.info(
      `Post-check: skipping verify command \`${verifyCommand}\` per Develop's bypassVerify=true.`
    );
  } else {
    const verifyTimeoutMs = verifyTimeoutMsOverride ?? getVerifyTimeoutMs();
    output.info(
      `Post-check: running verify command \`${verifyCommand}\` (timeout ${verifyTimeoutMs}ms)...`
    );
    const verify = await runCommand(verifyCommand, config.implRepoPath, verifyTimeoutMs);
    if (!verify.ok) {
      const verifyTail = tail(verify.output, 4000);
      // Retry prompt still includes the verify-tail string so attempt N+1 has
      // the same failure context as before.
      retryIssues.push(
        `Verify command \`${verifyCommand}\` exited with code ${verify.code}. Output (tail):\n\`\`\`\n${verifyTail}\n\`\`\``
      );
      // Display path uses the structured field instead of a duplicated note.
      verifyOutput = {
        command: verifyCommand,
        exitCode: verify.code,
        tail: verifyTail,
      };
      output.error(`Verify failed (exit ${verify.code}).`);
    } else {
      output.info("Verify passed.");
    }
  }

  const gitStatus = await runCommand(
    "git status --porcelain",
    config.implRepoPath,
    30_000
  );
  if (!gitStatus.ok) {
    const msg = `\`git status --porcelain\` failed unexpectedly:\n\`\`\`\n${tail(gitStatus.output, 2000)}\n\`\`\``;
    retryIssues.push(msg);
    displayIssues.push(msg);
  } else if (gitStatus.output.trim().length > 0) {
    const msg = `Uncommitted or untracked changes remain after Develop ran. Either commit them or add them to .gitignore. \`git status --porcelain\` output:\n\`\`\`\n${gitStatus.output.trim()}\n\`\`\``;
    retryIssues.push(msg);
    displayIssues.push(msg);
    output.error("Workspace dirty after Develop ran.");
  } else {
    output.info("Working tree clean.");
  }

  return {
    ok: retryIssues.length === 0,
    retryIssues,
    displayIssues,
    verifyOutput,
  };
}

interface CommandResult {
  ok: boolean;
  code: number | null;
  output: string;
}

async function runCommand(
  command: string,
  cwd: string,
  timeoutMs: number
): Promise<CommandResult> {
  try {
    const { stdout, stderr } = await execAsync(command, {
      cwd,
      timeout: timeoutMs,
      maxBuffer: 10 * 1024 * 1024,
    });
    return { ok: true, code: 0, output: stdout + stderr };
  } catch (err) {
    const e = err as NodeJS.ErrnoException & {
      stdout?: string;
      stderr?: string;
      code?: number | string;
    };
    const code = typeof e.code === "number" ? e.code : null;
    const output = (e.stdout ?? "") + (e.stderr ?? "");
    return { ok: false, code, output: output || String(err) };
  }
}

function tail(text: string, max: number): string {
  if (text.length <= max) return text;
  return "…(truncated)…\n" + text.slice(-max);
}
