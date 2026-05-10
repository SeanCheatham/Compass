import { exec } from "node:child_process";
import { promisify } from "node:util";
import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanNext, WorkspaceConfig } from "../state/types.js";
import { buildDevSystemPrompt } from "./prompts/dev-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";
import { readLessons } from "../mcp/utils/workspace.js";
import { createDevMcpServer } from "../mcp/server.js";
import type { VerifyOutput } from "../state/sessions.js";

const execAsync = promisify(exec);

const MAX_ATTEMPTS = 3;
const DEFAULT_VERIFY_TIMEOUT_MS = 10 * 60 * 1000;

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
   * Feedback string from the last `complete()` call, threaded into the next
   * Plan run. Empty if Develop never called complete.
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
  const systemPrompt = buildDevSystemPrompt({ next, lessons });

  let priorRetryIssues: string[] = [];
  let lastDisplayIssues: string[] = [];
  let lastVerifyOutput: VerifyOutput | null = null;
  let lastFeedback = "";

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
    const queryResult = await runDevQuery(
      config,
      systemPrompt,
      initialPrompt,
      next,
      output,
      attempt,
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

    const post = await runPostChecks(
      config,
      next.verify,
      output,
      queryResult.feedback !== null,
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
call the \`complete\` MCP tool with feedback for the next Plan run, and finish.

If the plan can't be implemented as written, make no changes, call \`complete\` with
the reason in feedback, and finish. Plan will read it and replan next iteration.`;
  }

  return `Your previous attempt left these post-check failures unresolved:

${priorIssues.map((i, idx) => `${idx + 1}. ${i}`).join("\n\n")}

Fix them now and finish with a \`complete\` call. Do not stop until the verify command
exits 0, \`git status --porcelain\` is empty, and you have called \`complete\`.`;
}

async function runDevQuery(
  config: WorkspaceConfig,
  systemPrompt: string,
  prompt: string,
  next: PlanNext,
  output: OutputManager,
  attempt: number,
  signal: AbortSignal
): Promise<{ cancelled: boolean; feedback: string | null }> {
  const abortController = new AbortController();
  if (signal.aborted) abortController.abort();
  else signal.addEventListener("abort", () => abortController.abort(), { once: true });

  let capturedFeedback: string | null = null;
  const mcpServer = createDevMcpServer(config, {
    onComplete: (feedback) => {
      // First call wins; subsequent calls in the same attempt are ignored.
      if (capturedFeedback === null) capturedFeedback = feedback;
    },
  });

  const devOptions: Options = {
    systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
    abortController,
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
      "mcp__compass__complete",
      "mcp__compass__read_lessons",
      "mcp__compass__set_lessons",
      "mcp__compass__append_lesson",
    ],
  };

  const ctx =
    attempt === 1
      ? next.plan.split("\n")[0]?.slice(0, 120)
      : `Retry ${attempt}/${MAX_ATTEMPTS}`;
  output.agentStart("Develop", ctx);

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
      }
    }

    output.agentComplete("Develop");
    return { cancelled: false, feedback: capturedFeedback };
  } catch (error) {
    if (signal.aborted) {
      output.info("Develop cancelled.");
      return { cancelled: true, feedback: capturedFeedback };
    }
    output.error(`Develop agent error: ${error}`);
    throw error;
  }
}

async function runPostChecks(
  config: WorkspaceConfig,
  verifyCommand: string,
  output: OutputManager,
  completeWasCalled: boolean,
  verifyTimeoutMsOverride: number | undefined
): Promise<PostCheckResult> {
  const retryIssues: string[] = [];
  const displayIssues: string[] = [];
  let verifyOutput: VerifyOutput | null = null;

  if (!completeWasCalled) {
    const msg =
      "Develop ended without calling the `complete` MCP tool. Every iteration must finish by calling `complete({ feedback: \"...\" })` so the next Plan run gets context.";
    retryIssues.push(msg);
    displayIssues.push(msg);
    output.error("Develop did not call `complete`.");
  }

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
