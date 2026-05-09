import { resolve } from "path";
import { mkdir, access, readFile, writeFile } from "fs/promises";
import type { WorkspaceConfig } from "../../state/types.js";

export const WORKSPACE_DIR = ".compass";
export const STATE_FILE = "state.md";
export const DRAFTS_FILE = "drafts.md";
export const FEEDBACK_FILE = "feedback.md";

export function getWorkspaceConfig(implRepoPath: string): WorkspaceConfig {
  const workspacePath = resolve(implRepoPath, WORKSPACE_DIR);
  return {
    implRepoPath,
    workspacePath,
    statePath: resolve(workspacePath, STATE_FILE),
    draftsPath: resolve(workspacePath, DRAFTS_FILE),
    feedbackPath: resolve(workspacePath, FEEDBACK_FILE),
  };
}

async function ensureFile(path: string, defaultContent = ""): Promise<void> {
  const exists = await access(path)
    .then(() => true)
    .catch(() => false);
  if (!exists) {
    await writeFile(path, defaultContent, "utf-8");
  }
}

export async function ensureWorkspaceExists(
  config: WorkspaceConfig
): Promise<void> {
  await mkdir(config.workspacePath, { recursive: true });
  await ensureFile(config.statePath);
  await ensureFile(config.draftsPath);
  await ensureFile(config.feedbackPath);
  await ensureGitignore(config.implRepoPath);
}

export async function ensureGitignore(implRepoPath: string): Promise<void> {
  const gitignorePath = resolve(implRepoPath, ".gitignore");
  const entry = `${WORKSPACE_DIR}/`;

  let existing = "";
  try {
    existing = await readFile(gitignorePath, "utf-8");
  } catch {
    existing = "";
  }

  const lines = existing.split("\n").map((l) => l.trim());
  if (lines.includes(entry) || lines.includes(WORKSPACE_DIR)) {
    return;
  }

  const updated = existing.length === 0 || existing.endsWith("\n")
    ? existing + entry + "\n"
    : existing + "\n" + entry + "\n";
  await writeFile(gitignorePath, updated, "utf-8");
}

export async function readState(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.statePath, "utf-8");
  } catch {
    return "";
  }
}

export async function readDrafts(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.draftsPath, "utf-8");
  } catch {
    return "";
  }
}

export async function readFeedback(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.feedbackPath, "utf-8");
  } catch {
    return "";
  }
}

export async function appendDraft(
  config: WorkspaceConfig,
  content: string
): Promise<void> {
  const trimmed = content.trim();
  if (!trimmed) return;

  const existing = await readDrafts(config);
  const separator = existing.length === 0 || existing.endsWith("\n\n")
    ? ""
    : existing.endsWith("\n")
      ? "\n"
      : "\n\n";
  const block = `- ${trimmed}\n`;
  await writeFile(config.draftsPath, existing + separator + block, "utf-8");
}

export async function clearDrafts(config: WorkspaceConfig): Promise<void> {
  await writeFile(config.draftsPath, "", "utf-8");
}

export async function clearFeedback(config: WorkspaceConfig): Promise<void> {
  await writeFile(config.feedbackPath, "", "utf-8");
}
