import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { PlanNext, WorkspaceConfig } from "../state/types.js";
import type { OutputManager } from "../web/output-manager.js";

export type CodexSidecarMode =
  | "auto"
  | "off"
  | "verify-failures"
  | "diff-review";

export interface CodexSidecarOptions {
  mode: CodexSidecarMode;
}

const DEFAULT_CODEX_SIDECAR_TIMEOUT_MS = 2 * 60 * 1000;

export function parseCodexSidecarMode(
  value: string | undefined
): CodexSidecarMode {
  const normalized = (value ?? "auto").trim().toLowerCase();
  if (
    normalized === "auto" ||
    normalized === "off" ||
    normalized === "verify-failures" ||
    normalized === "diff-review"
  ) {
    return normalized;
  }
  throw new Error(
    `Unknown Codex sidecar mode "${value}". Expected "auto", "verify-failures", "diff-review", or "off".`
  );
}

export function codexSidecarLabel(mode: CodexSidecarMode): string {
  switch (mode) {
    case "off":
      return "off";
    case "diff-review":
      return "diff-review";
    case "verify-failures":
      return "verify-failures";
    case "auto":
      return "auto (verify-failure diagnosis + diff review when Codex CLI is available)";
  }
}

export function codexSidecarHandlesDiffReview(
  options: CodexSidecarOptions
): boolean {
  return options.mode === "auto" || options.mode === "diff-review";
}

export function codexSidecarHandlesVerifyFailures(
  options: CodexSidecarOptions
): boolean {
  return options.mode === "auto" || options.mode === "verify-failures";
}

export async function diagnoseVerifyFailureWithCodex(args: {
  config: WorkspaceConfig;
  options: CodexSidecarOptions;
  next: PlanNext;
  verifyCommand: string;
  exitCode: number | null;
  verifyTail: string;
  output: OutputManager;
  signal: AbortSignal;
}): Promise<string | null> {
  if (!codexSidecarHandlesVerifyFailures(args.options)) return null;

  args.output.info("Codex sidecar: diagnosing verify failure (read-only).");

  const prompt = buildVerifyDiagnosisPrompt(
    args.next,
    args.verifyCommand,
    args.exitCode,
    args.verifyTail
  );

  const result = await runCodexReadOnly(prompt, args.config.implRepoPath, args.signal);
  if (result.status === "unavailable") {
    args.output.info("Codex sidecar unavailable; continuing with Claude-only retry context.");
    return null;
  }
  if (result.status === "cancelled") return null;
  if (result.status === "failed") {
    args.output.info(`Codex sidecar failed: ${result.message}`);
    return null;
  }

  const diagnosis = result.message.trim();
  if (!diagnosis) return null;
  args.output.info("Codex sidecar: diagnosis captured for Claude retry.");
  args.output.log(`Codex sidecar diagnosis:\n\n${diagnosis}`);
  return diagnosis;
}

export async function reviewDiffWithCodex(args: {
  config: WorkspaceConfig;
  options: CodexSidecarOptions;
  next: PlanNext;
  beforeSha: string | null;
  afterSha: string | null;
  output: OutputManager;
  signal: AbortSignal;
}): Promise<string | null> {
  if (!codexSidecarHandlesDiffReview(args.options)) return null;
  if (args.beforeSha && args.beforeSha === args.afterSha) return null;
  if (!args.afterSha) return null;

  args.output.info("Codex sidecar: reviewing committed diff (read-only).");

  const prompt = buildDiffReviewPrompt(args.next, args.beforeSha, args.afterSha);
  const result = await runCodexReadOnly(prompt, args.config.implRepoPath, args.signal);
  if (result.status === "unavailable") {
    args.output.info("Codex sidecar unavailable; skipping diff review.");
    return null;
  }
  if (result.status === "cancelled") return null;
  if (result.status === "failed") {
    args.output.info(`Codex sidecar diff review failed: ${result.message}`);
    return null;
  }

  const review = result.message.trim();
  if (!review || isNoIssuesReview(review)) {
    args.output.info("Codex sidecar: no concrete diff issues reported.");
    return null;
  }
  args.output.info("Codex sidecar: diff review found issues for Claude retry.");
  args.output.log(`Codex sidecar diff review:\n\n${review}`);
  return review;
}

function buildVerifyDiagnosisPrompt(
  next: PlanNext,
  verifyCommand: string,
  exitCode: number | null,
  verifyTail: string
): string {
  return `You are a read-only sidecar reviewer for Compass, a Claude-driven
software factory. Claude owns all tool calls, state changes, file edits, and
commits. Your job is only to diagnose this failing verify command and give
Claude concise retry guidance.

Do not edit files. Do not run destructive commands. Do not propose changes to
Compass state. Inspect the repository if needed, but keep the answer brief.

Return markdown with:

1. Most likely root cause.
2. The smallest concrete fix Claude should try next.
3. Any risky assumptions or files worth inspecting.

## Plan Claude is implementing

${next.plan}

## Verify command

\`\`\`bash
${verifyCommand}
\`\`\`

Exit code: ${exitCode ?? "unknown"}

## Verify output tail

\`\`\`
${verifyTail}
\`\`\`
`;
}

function buildDiffReviewPrompt(
  next: PlanNext,
  beforeSha: string | null,
  afterSha: string
): string {
  const target = beforeSha ? `${beforeSha}..${afterSha}` : afterSha;
  const commands = beforeSha
    ? `git show --stat --oneline ${afterSha}
git diff ${beforeSha}..${afterSha}
git status --porcelain`
    : `git show --stat --oneline ${afterSha}
git show --format=fuller --find-renames ${afterSha}
git status --porcelain`;
  return `You are a read-only sidecar code reviewer for Compass, a Claude-driven
software factory. Claude owns all tool calls, state changes, file edits, and
commits. Your job is only to review the committed diff for concrete correctness
issues before Compass accepts the iteration.

Do not edit files. Do not run destructive commands. Inspect the repository and
diff if needed. Focus on bugs, regressions, missed requirements, broken tests,
and unsafe assumptions. Ignore style-only nits unless they hide a real bug.

Review this git range:

\`\`\`
${target}
\`\`\`

Suggested commands, if useful:

\`\`\`bash
${commands}
\`\`\`

Return exactly one of:

- \`NO_ISSUES\` if you found no concrete issue that should block acceptance.
- Markdown bullets of concrete issues Claude should fix, with file paths when
  possible. Keep it concise.

## Plan Claude implemented

${next.plan}
`;
}

type CodexRunResult =
  | { status: "ok"; message: string }
  | { status: "cancelled" }
  | { status: "unavailable" }
  | { status: "failed"; message: string };

async function runCodexReadOnly(
  prompt: string,
  cwd: string,
  signal: AbortSignal
): Promise<CodexRunResult> {
  const bin = process.env.COMPASS_CODEX_BIN?.trim() || "codex";
  const dir = await mkdtemp(join(tmpdir(), "compass-codex-sidecar-"));
  const outPath = join(dir, "last-message.md");
  const timeoutMs = getCodexSidecarTimeoutMs();

  try {
    const args = [
      "exec",
      "--cd",
      cwd,
      "--sandbox",
      "read-only",
      "--ask-for-approval",
      "never",
      "--ephemeral",
      "--output-last-message",
      outPath,
      "-",
    ];

    const result = await runProcess(bin, args, prompt, cwd, signal, timeoutMs);
    if (result.status === "cancelled" || result.status === "unavailable") {
      return result;
    }
    if (result.code !== 0) {
      return {
        status: "failed",
        message: tail(result.stderr || result.stdout || `exit ${result.code}`, 1200),
      };
    }

    const message = await readFile(outPath, "utf-8").catch(() => result.stdout);
    return { status: "ok", message };
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

function runProcess(
  bin: string,
  args: string[],
  stdin: string,
  cwd: string,
  signal: AbortSignal,
  timeoutMs: number
): Promise<
  | { status: "ok"; code: number | null; stdout: string; stderr: string }
  | { status: "cancelled" }
  | { status: "unavailable" }
> {
  return new Promise((resolve) => {
    const child = spawn(bin, args, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let settled = false;
    let stdout = "";
    let stderr = "";
    let timeout: NodeJS.Timeout | null = null;

    const settle = (
      result:
        | { status: "ok"; code: number | null; stdout: string; stderr: string }
        | { status: "cancelled" }
        | { status: "unavailable" }
    ) => {
      if (settled) return;
      settled = true;
      if (timeout) clearTimeout(timeout);
      signal.removeEventListener("abort", onAbort);
      resolve(result);
    };

    const onAbort = () => {
      child.kill("SIGTERM");
      settle({ status: "cancelled" });
    };

    if (signal.aborted) {
      child.kill("SIGTERM");
      settle({ status: "cancelled" });
      return;
    }
    signal.addEventListener("abort", onAbort, { once: true });
    timeout = setTimeout(() => {
      child.kill("SIGTERM");
      stderr += `Codex sidecar timed out after ${timeoutMs}ms.`;
      settle({ status: "ok", code: 124, stdout, stderr });
    }, timeoutMs);

    child.on("error", (err) => {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        settle({ status: "unavailable" });
      } else {
        stderr += String(err);
        settle({ status: "ok", code: 1, stdout, stderr });
      }
    });

    child.stdout?.on("data", (chunk) => {
      stdout += String(chunk);
    });
    child.stderr?.on("data", (chunk) => {
      stderr += String(chunk);
    });
    child.on("close", (code) => {
      settle({ status: "ok", code, stdout, stderr });
    });

    child.stdin?.end(stdin);
  });
}

function tail(text: string, max: number): string {
  return text.length <= max ? text : text.slice(text.length - max);
}

function isNoIssuesReview(text: string): boolean {
  return text.trim().toUpperCase() === "NO_ISSUES";
}

function getCodexSidecarTimeoutMs(): number {
  const raw = process.env.COMPASS_CODEX_SIDECAR_TIMEOUT_MS;
  if (!raw) return DEFAULT_CODEX_SIDECAR_TIMEOUT_MS;
  const parsed = parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_CODEX_SIDECAR_TIMEOUT_MS;
  }
  return parsed;
}
