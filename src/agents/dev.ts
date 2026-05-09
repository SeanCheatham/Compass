import { exec } from "node:child_process";
import { promisify } from "node:util";
import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { PlanNext, WorkspaceConfig } from "../state/types.js";
import { buildDevSystemPrompt } from "./prompts/dev-system.js";
import type { OutputManager } from "../web/output-manager.js";
import { extractToolDetail } from "./tool-details.js";

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
  issues: string[];
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
  /** Last set of post-check issues, if any (empty when succeeded). */
  issues: string[];
}

export async function runDevAgent(
  config: WorkspaceConfig,
  next: PlanNext,
  output: OutputManager,
  opts: DevAgentOptions
): Promise<DevAgentResult> {
  const systemPrompt = buildDevSystemPrompt({ next });

  let priorIssues: string[] = [];

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    if (opts.signal.aborted) {
      return { succeeded: false, cancelled: true, issues: priorIssues };
    }

    const initialPrompt = buildDevPrompt(attempt, priorIssues);
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
      return { succeeded: false, cancelled: true, issues: priorIssues };
    }

    const post = await runPostChecks(config, next.verify, output);
    if (post.ok) {
      return { succeeded: true, cancelled: false, issues: [] };
    }

    priorIssues = post.issues;

    if (attempt === MAX_ATTEMPTS) {
      output.error(
        `Develop post-checks still failing after ${MAX_ATTEMPTS} attempts. Moving on; Plan will see the feedback next iteration.`
      );
      return { succeeded: false, cancelled: false, issues: priorIssues };
    }

    output.info(
      `Develop post-checks failed (attempt ${attempt}/${MAX_ATTEMPTS}). Re-prompting.`
    );
  }

  return { succeeded: false, cancelled: false, issues: priorIssues };
}

function buildDevPrompt(attempt: number, priorIssues: string[]): string {
  if (attempt === 1) {
    return `Implement the plan in your system prompt.

When you're done — implementation working, verify command passing, changes committed —
overwrite \`.compass/feedback.md\` with notes for the Plan agent and finish.

If the plan can't be implemented as written, make no changes, write the reason to
\`.compass/feedback.md\`, and finish. Plan will read it and replan next iteration.`;
  }

  return `Your previous attempt left these post-check failures unresolved:

${priorIssues.map((i, idx) => `${idx + 1}. ${i}`).join("\n\n")}

Fix them now and finish. Do not signal completion until both the verify command exits 0
and \`git status --porcelain\` is empty.`;
}

async function runDevQuery(
  config: WorkspaceConfig,
  systemPrompt: string,
  prompt: string,
  next: PlanNext,
  output: OutputManager,
  attempt: number,
  signal: AbortSignal
): Promise<{ cancelled: boolean }> {
  const abortController = new AbortController();
  if (signal.aborted) abortController.abort();
  else signal.addEventListener("abort", () => abortController.abort(), { once: true });

  const devOptions: Options = {
    systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    settingSources: ["user", "project", "local"],
    abortController,
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
    return { cancelled: false };
  } catch (error) {
    if (signal.aborted) {
      output.info("Develop cancelled.");
      return { cancelled: true };
    }
    output.error(`Develop agent error: ${error}`);
    throw error;
  }
}

async function runPostChecks(
  config: WorkspaceConfig,
  verifyCommand: string,
  output: OutputManager
): Promise<PostCheckResult> {
  const issues: string[] = [];

  output.info(`Post-check: running verify command \`${verifyCommand}\`...`);
  const verify = await runCommand(verifyCommand, config.implRepoPath, getVerifyTimeoutMs());
  if (!verify.ok) {
    issues.push(
      `Verify command \`${verifyCommand}\` exited with code ${verify.code}. Output (tail):\n\`\`\`\n${tail(verify.output, 4000)}\n\`\`\``
    );
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
    issues.push(
      `\`git status --porcelain\` failed unexpectedly:\n\`\`\`\n${tail(gitStatus.output, 2000)}\n\`\`\``
    );
  } else if (gitStatus.output.trim().length > 0) {
    issues.push(
      `Uncommitted or untracked changes remain after Develop ran. Either commit them or add them to .gitignore. \`git status --porcelain\` output:\n\`\`\`\n${gitStatus.output.trim()}\n\`\`\``
    );
    output.error("Workspace dirty after Develop ran.");
  } else {
    output.info("Working tree clean.");
  }

  return { ok: issues.length === 0, issues };
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
