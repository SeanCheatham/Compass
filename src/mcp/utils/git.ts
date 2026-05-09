import { execSync, exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

export interface GitResult {
  success: boolean;
  stdout: string;
  stderr: string;
}

function runGitSync(cwd: string, args: string[]): string {
  return execSync(`git ${args.join(" ")}`, {
    cwd,
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

async function runGit(cwd: string, args: string[]): Promise<GitResult> {
  try {
    const { stdout, stderr } = await execAsync(`git ${args.join(" ")}`, {
      cwd,
      encoding: "utf-8",
    });
    return { success: true, stdout: stdout.trim(), stderr: stderr.trim() };
  } catch (error) {
    const err = error as { stdout?: string; stderr?: string };
    return {
      success: false,
      stdout: err.stdout?.trim() ?? "",
      stderr: err.stderr?.trim() ?? "",
    };
  }
}

export async function getCurrentCommit(cwd: string): Promise<string> {
  const result = await runGit(cwd, ["rev-parse", "HEAD"]);
  if (!result.success) {
    throw new Error(`Failed to get current commit: ${result.stderr}`);
  }
  return result.stdout;
}

export async function getShortCommit(cwd: string): Promise<string> {
  const result = await runGit(cwd, ["rev-parse", "--short", "HEAD"]);
  if (!result.success) {
    throw new Error(`Failed to get short commit: ${result.stderr}`);
  }
  return result.stdout;
}

export async function hasUncommittedChanges(cwd: string): Promise<boolean> {
  const result = await runGit(cwd, ["status", "--porcelain"]);
  return result.stdout.length > 0;
}

export async function stageAllChanges(cwd: string): Promise<void> {
  const result = await runGit(cwd, ["add", "-A"]);
  if (!result.success) {
    throw new Error(`Failed to stage changes: ${result.stderr}`);
  }
}

export async function commit(cwd: string, message: string): Promise<string> {
  await stageAllChanges(cwd);

  const result = await runGit(cwd, [
    "commit",
    "-m",
    `"${message.replace(/"/g, '\\"')}"`,
  ]);
  if (!result.success) {
    throw new Error(`Failed to commit: ${result.stderr}`);
  }

  return getCurrentCommit(cwd);
}

export async function stashChanges(cwd: string): Promise<void> {
  const result = await runGit(cwd, [
    "stash",
    "push",
    "-m",
    "compass-auto-stash",
  ]);
  if (!result.success) {
    throw new Error(`Failed to stash changes: ${result.stderr}`);
  }
}

export async function discardChanges(cwd: string): Promise<void> {
  const checkout = await runGit(cwd, ["checkout", "--", "."]);
  if (!checkout.success) {
    throw new Error(`Failed to discard changes: ${checkout.stderr}`);
  }

  const clean = await runGit(cwd, ["clean", "-fd"]);
  if (!clean.success) {
    throw new Error(`Failed to clean untracked files: ${clean.stderr}`);
  }
}

export async function resetHard(cwd: string, commitSha: string): Promise<void> {
  const result = await runGit(cwd, ["reset", "--hard", commitSha]);
  if (!result.success) {
    throw new Error(`Failed to reset to ${commitSha}: ${result.stderr}`);
  }
}

export async function getCommitForPlan(
  cwd: string,
  planId: string,
  plans: { id: string; commit: string | null }[]
): Promise<string | null> {
  const plan = plans.find((p) => p.id === planId);
  return plan?.commit ?? null;
}

export async function isValidCommit(
  cwd: string,
  commitSha: string
): Promise<boolean> {
  const result = await runGit(cwd, ["cat-file", "-t", commitSha]);
  return result.success && result.stdout === "commit";
}

export function isGitRepo(cwd: string): boolean {
  try {
    runGitSync(cwd, ["rev-parse", "--git-dir"]);
    return true;
  } catch {
    return false;
  }
}

export async function initRepo(cwd: string): Promise<void> {
  const result = await runGit(cwd, ["init"]);
  if (!result.success) {
    throw new Error(`Failed to init repo: ${result.stderr}`);
  }
}

export interface CommitInfo {
  sha: string;
  short: string;
  subject: string;
}

/**
 * Returns the commits introduced going from `before` to `after` (i.e. commits
 * reachable from `after` but not `before`). Order is oldest-first.
 *
 * If `before` is null (e.g. fresh repo), returns the single commit at `after`
 * if it exists.
 */
export async function commitsBetween(
  cwd: string,
  before: string | null,
  after: string
): Promise<CommitInfo[]> {
  if (before === after) return [];
  const range = before ? `${before}..${after}` : after;
  const result = await runGit(cwd, [
    "log",
    "--reverse",
    "--pretty=format:%H%x09%h%x09%s",
    range,
  ]);
  if (!result.success) return [];
  if (!result.stdout) return [];
  return result.stdout
    .split("\n")
    .map((line) => {
      const [sha, short, ...rest] = line.split("\t");
      return { sha, short, subject: rest.join("\t") };
    })
    .filter((c) => c.sha);
}

export async function tryGetCurrentCommit(cwd: string): Promise<string | null> {
  const result = await runGit(cwd, ["rev-parse", "HEAD"]);
  if (!result.success) return null;
  return result.stdout || null;
}

/**
 * List all tracked + untracked-but-not-ignored files, repo-relative paths.
 * Honours .gitignore for free. Returns [] on failure.
 */
export async function listTrackedAndUntracked(cwd: string): Promise<string[]> {
  const result = await runGit(cwd, [
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
  ]);
  if (!result.success || !result.stdout) return [];
  return result.stdout.split("\n").filter((l) => l.length > 0);
}
