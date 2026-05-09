import { resolve } from "path";
import {
  mkdir,
  access,
  readFile,
  writeFile,
  rename,
  unlink,
} from "fs/promises";
import {
  EMPTY_PLAN_STATE,
  type PlanState,
  type WorkspaceConfig,
} from "../../state/types.js";

export const WORKSPACE_DIR = ".compass";
export const STATE_FILE = "state.json";
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
  await ensureFile(config.statePath, JSON.stringify(EMPTY_PLAN_STATE, null, 2) + "\n");
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

function normalizePlanState(raw: unknown): PlanState {
  if (!raw || typeof raw !== "object") return { ...EMPTY_PLAN_STATE };

  const obj = raw as Record<string, unknown>;
  const completed = Array.isArray(obj.completed)
    ? obj.completed.filter((x): x is string => typeof x === "string")
    : [];
  const followUp = typeof obj.followUp === "string" ? obj.followUp : "";

  let next: PlanState["next"] = null;
  if (obj.next && typeof obj.next === "object") {
    const n = obj.next as Record<string, unknown>;
    const plan = typeof n.plan === "string" ? n.plan.trim() : "";
    const verify = typeof n.verify === "string" ? n.verify.trim() : "";
    if (plan && verify) {
      next = { plan, verify };
    }
  }

  return { completed, next, followUp };
}

/**
 * Read state.json, parsed and normalized. Returns EMPTY_PLAN_STATE on missing/invalid file.
 */
export async function readPlanState(
  config: WorkspaceConfig
): Promise<PlanState> {
  let raw: string;
  try {
    raw = await readFile(config.statePath, "utf-8");
  } catch {
    return { ...EMPTY_PLAN_STATE };
  }
  if (!raw.trim()) return { ...EMPTY_PLAN_STATE };
  try {
    return normalizePlanState(JSON.parse(raw));
  } catch {
    return { ...EMPTY_PLAN_STATE };
  }
}

/**
 * Read state.json as the raw text the agent will see/edit. Falls back to a pretty-printed
 * empty state if the file is missing or invalid, so agents always see valid JSON.
 */
export async function readStateText(config: WorkspaceConfig): Promise<string> {
  let raw: string;
  try {
    raw = await readFile(config.statePath, "utf-8");
  } catch {
    return JSON.stringify(EMPTY_PLAN_STATE, null, 2) + "\n";
  }
  if (!raw.trim()) return JSON.stringify(EMPTY_PLAN_STATE, null, 2) + "\n";
  try {
    return JSON.stringify(JSON.parse(raw), null, 2) + "\n";
  } catch {
    return raw;
  }
}

export async function writePlanState(
  config: WorkspaceConfig,
  state: PlanState
): Promise<void> {
  await writeFile(
    config.statePath,
    JSON.stringify(state, null, 2) + "\n",
    "utf-8"
  );
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

/**
 * Atomically snapshot a workspace file's contents and clear it.
 * Uses fs.rename so writes during the snapshot land in the fresh empty file.
 * Returns "" if the file did not exist or was empty.
 */
async function snapshotAndConsume(path: string): Promise<string> {
  const snapshotPath = `${path}.snapshot`;
  try {
    await rename(path, snapshotPath);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return "";
    throw err;
  }
  // Re-create empty file so subsequent appends/reads work.
  await writeFile(path, "", "utf-8");
  try {
    return await readFile(snapshotPath, "utf-8");
  } finally {
    await unlink(snapshotPath).catch(() => {});
  }
}

export async function snapshotAndClearDrafts(
  config: WorkspaceConfig
): Promise<string> {
  return snapshotAndConsume(config.draftsPath);
}

export async function snapshotAndClearFeedback(
  config: WorkspaceConfig
): Promise<string> {
  return snapshotAndConsume(config.feedbackPath);
}
