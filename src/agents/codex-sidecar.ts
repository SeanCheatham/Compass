import { Codex, type CodexOptions } from "@openai/codex-sdk";
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

const DEFAULT_CODEX_VERIFY_TIMEOUT_MS = 2 * 60 * 1000;
const DEFAULT_CODEX_DIFF_REVIEW_TIMEOUT_MS = 15 * 60 * 1000;

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

  const result = await runCodexReadOnly(prompt, args.config.implRepoPath, args.signal, {
    defaultTimeoutMs: DEFAULT_CODEX_VERIFY_TIMEOUT_MS,
  });
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
  feedback: string;
  output: OutputManager;
  signal: AbortSignal;
}): Promise<string | null> {
  if (!codexSidecarHandlesDiffReview(args.options)) return null;
  if (args.beforeSha && args.beforeSha === args.afterSha) return null;
  if (!args.afterSha) return null;

  args.output.info("Codex sidecar: reviewing committed diff (read-only).");

  const prompt = buildDiffReviewPrompt(
    args.next,
    args.beforeSha,
    args.afterSha,
    args.feedback
  );
  const result = await runCodexReadOnly(prompt, args.config.implRepoPath, args.signal, {
    defaultTimeoutMs: DEFAULT_CODEX_DIFF_REVIEW_TIMEOUT_MS,
  });
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
  afterSha: string,
  feedback: string
): string {
  const target = beforeSha ? `${beforeSha}..${afterSha}` : afterSha;
  const commands = beforeSha
    ? `git show --stat --oneline ${afterSha}
git diff ${beforeSha}..${afterSha}
git status --porcelain`
    : `git show --stat --oneline ${afterSha}
git show --format=fuller --find-renames ${afterSha}
git status --porcelain`;
  const trimmedFeedback = feedback.trim();
  const feedbackSection = trimmedFeedback
    ? `\n## Develop feedback\n\nThis is the note Claude left via \`set_feedback\` before review. Use it as intent/context when judging whether a diff is acceptable, while still blocking concrete correctness issues.\n\n<develop_feedback>\n${trimmedFeedback}\n</develop_feedback>\n`
    : "";
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
${feedbackSection}
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
  signal: AbortSignal,
  options: { defaultTimeoutMs: number }
): Promise<CodexRunResult> {
  const timeoutMs = getCodexSidecarTimeoutMs(options.defaultTimeoutMs);
  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort(new Error(`Codex sidecar timed out after ${timeoutMs}ms.`));
  }, timeoutMs);

  const onAbort = () => controller.abort(signal.reason);
  signal.addEventListener("abort", onAbort, { once: true });
  if (signal.aborted) controller.abort(signal.reason);

  try {
    const codex = new Codex(getCodexOptions());
    const thread = codex.startThread({
      workingDirectory: cwd,
      sandboxMode: "read-only",
      approvalPolicy: "never",
      modelReasoningEffort: "low",
    });

    const turn = await thread.run(prompt, { signal: controller.signal });
    return { status: "ok", message: turn.finalResponse };
  } catch (err) {
    if (signal.aborted) return { status: "cancelled" };
    if (controller.signal.aborted) {
      return { status: "failed", message: getErrorMessage(controller.signal.reason) };
    }
    if (isCodexUnavailableError(err)) return { status: "unavailable" };
    return { status: "failed", message: tail(getErrorMessage(err), 1200) };
  } finally {
    clearTimeout(timeout);
    signal.removeEventListener("abort", onAbort);
  }
}

function tail(text: string, max: number): string {
  return text.length <= max ? text : text.slice(text.length - max);
}

export function getCodexOptionsForTest(
  env: CodexEnv = process.env
): CodexOptions {
  return getCodexOptions(env);
}

export function buildDiffReviewPromptForTest(
  next: PlanNext,
  beforeSha: string | null,
  afterSha: string,
  feedback = ""
): string {
  return buildDiffReviewPrompt(next, beforeSha, afterSha, feedback);
}

interface CodexEnv {
  COMPASS_CODEX_BIN?: string;
  COMPASS_CODEX_SIDECAR_TIMEOUT_MS?: string;
}

function getCodexOptions(env: CodexEnv = process.env): CodexOptions {
  const codexPathOverride = env.COMPASS_CODEX_BIN?.trim();
  return codexPathOverride ? { codexPathOverride } : {};
}

export function isCodexUnavailableErrorForTest(err: unknown): boolean {
  return isCodexUnavailableError(err);
}

export function getDefaultCodexTimeoutsForTest(): {
  verifyMs: number;
  diffReviewMs: number;
} {
  return {
    verifyMs: DEFAULT_CODEX_VERIFY_TIMEOUT_MS,
    diffReviewMs: DEFAULT_CODEX_DIFF_REVIEW_TIMEOUT_MS,
  };
}

function isCodexUnavailableError(err: unknown): boolean {
  const message = getErrorMessage(err);
  const code =
    typeof err === "object" && err !== null && "code" in err
      ? String((err as { code?: unknown }).code)
      : "";
  return (
    code === "ENOENT" ||
    /Unable to locate Codex CLI binaries/i.test(message) ||
    /no such file or directory/i.test(message)
  );
}

function getErrorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  return String(err);
}

function isNoIssuesReview(text: string): boolean {
  return text.trim().toUpperCase() === "NO_ISSUES";
}

export function getCodexSidecarTimeoutMsForTest(
  defaultTimeoutMs: number,
  env: CodexEnv = process.env
): number {
  return getCodexSidecarTimeoutMs(defaultTimeoutMs, env);
}

function getCodexSidecarTimeoutMs(
  defaultTimeoutMs: number,
  env: CodexEnv = process.env
): number {
  const raw = env.COMPASS_CODEX_SIDECAR_TIMEOUT_MS;
  if (!raw) return defaultTimeoutMs;
  const parsed = parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return defaultTimeoutMs;
  }
  return parsed;
}
