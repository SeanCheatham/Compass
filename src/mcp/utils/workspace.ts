import { resolve } from "path";
import {
  mkdir,
  access,
  readFile,
  writeFile,
  appendFile,
  rename,
  unlink,
  copyFile,
} from "fs/promises";
import {
  EMPTY_PLAN_STATE,
  type PlanState,
  type WorkspaceConfig,
} from "../../state/types.js";

export const WORKSPACE_DIR = ".compass";
export const STATE_FILE = "state.json";
export const STATE_BACKUP_FILE = "state.json.bak";
export const DRAFTS_FILE = "drafts.md";
export const LESSONS_FILE = "lessons.md";
export const COMPASS_FILE = "COMPASS.md";

let atomicWriteCounter = 0;

/**
 * Thrown when state.json exists on disk but cannot be parsed/normalized.
 * The runner catches this and halts the loop rather than silently wiping
 * `completed` history.
 */
export class StateParseError extends Error {
  constructor(
    message: string,
    readonly path: string,
    readonly raw: string
  ) {
    super(message);
    this.name = "StateParseError";
  }
}

export function getWorkspaceConfig(implRepoPath: string): WorkspaceConfig {
  const workspacePath = resolve(implRepoPath, WORKSPACE_DIR);
  return {
    implRepoPath,
    workspacePath,
    statePath: resolve(workspacePath, STATE_FILE),
    stateBackupPath: resolve(workspacePath, STATE_BACKUP_FILE),
    draftsPath: resolve(workspacePath, DRAFTS_FILE),
    lessonsPath: resolve(workspacePath, LESSONS_FILE),
    compassPath: resolve(workspacePath, COMPASS_FILE),
    sessionsPath: resolve(workspacePath, "sessions"),
    sessionsRecordPath: resolve(workspacePath, "sessions.json"),
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

async function writeFileAtomic(path: string, content: string): Promise<void> {
  const tmp = `${path}.${process.pid}.${Date.now()}.${atomicWriteCounter++}.tmp`;
  try {
    await writeFile(tmp, content, "utf-8");
    await rename(tmp, path);
  } catch (err) {
    await unlink(tmp).catch(() => {});
    throw err;
  }
}

export async function ensureWorkspaceExists(
  config: WorkspaceConfig
): Promise<void> {
  await mkdir(config.workspacePath, { recursive: true });
  await mkdir(config.sessionsPath, { recursive: true });
  await ensureFile(config.statePath, JSON.stringify(EMPTY_PLAN_STATE, null, 2) + "\n");
  await ensureFile(config.draftsPath);
  await ensureFile(config.lessonsPath);
  await ensureFile(config.compassPath);
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

/**
 * Normalize parsed JSON into a PlanState. Returns null on shape mismatch so
 * callers can decide whether to throw or fall back.
 */
export function normalizePlanState(raw: unknown): PlanState | null {
  if (!raw || typeof raw !== "object") return null;

  const obj = raw as Record<string, unknown>;
  if (!Array.isArray(obj.completed)) return null;
  const completed = obj.completed.filter((x): x is string => typeof x === "string");

  const midTerm = typeof obj.midTerm === "string" ? obj.midTerm : "";
  const longTerm = typeof obj.longTerm === "string" ? obj.longTerm : "";

  let immediate: PlanState["immediate"] = null;
  if (obj.immediate === null || obj.immediate === undefined) {
    immediate = null;
  } else if (typeof obj.immediate === "object") {
    const n = obj.immediate as Record<string, unknown>;
    const plan = typeof n.plan === "string" ? n.plan.trim() : "";
    const verify = typeof n.verify === "string" ? n.verify.trim() : "";
    if (!plan || !verify) return null;
    const rawTimeout = n.verifyTimeoutMs;
    const verifyTimeoutMs =
      typeof rawTimeout === "number" &&
      Number.isFinite(rawTimeout) &&
      Number.isInteger(rawTimeout) &&
      rawTimeout > 0
        ? rawTimeout
        : undefined;
    const rawDifficulty = n.estimatedDifficulty;
    const estimatedDifficulty =
      rawDifficulty === "low" ||
      rawDifficulty === "medium" ||
      rawDifficulty === "high"
        ? rawDifficulty
        : undefined;
    immediate = {
      plan,
      verify,
      ...(verifyTimeoutMs !== undefined ? { verifyTimeoutMs } : {}),
      ...(estimatedDifficulty !== undefined ? { estimatedDifficulty } : {}),
    };
  } else {
    return null;
  }

  return { completed, immediate, midTerm, longTerm };
}

/**
 * Read state.json, parsed and normalized.
 * - Missing or empty file → EMPTY_PLAN_STATE (this is a fresh workspace).
 * - Corrupt or shape-invalid file → throws StateParseError (caller halts).
 *
 * Never silently returns EMPTY for a non-empty corrupt file — that masks
 * data loss.
 */
export async function readPlanState(
  config: WorkspaceConfig
): Promise<PlanState> {
  let raw: string;
  try {
    raw = await readFile(config.statePath, "utf-8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { ...EMPTY_PLAN_STATE };
    }
    throw err;
  }
  if (!raw.trim()) return { ...EMPTY_PLAN_STATE };

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new StateParseError(
      `state.json is not valid JSON: ${(err as Error).message}`,
      config.statePath,
      raw
    );
  }
  const normalized = normalizePlanState(parsed);
  if (!normalized) {
    throw new StateParseError(
      "state.json does not match the expected schema (completed: string[], immediate: object|null, midTerm: string, longTerm: string)",
      config.statePath,
      raw
    );
  }
  return normalized;
}

/**
 * Lenient read — returns EMPTY_PLAN_STATE on any failure. Use only for status
 * displays where masking corruption is acceptable.
 */
export async function tryReadPlanState(
  config: WorkspaceConfig
): Promise<PlanState> {
  try {
    return await readPlanState(config);
  } catch {
    return { ...EMPTY_PLAN_STATE };
  }
}

/**
 * Copy the current state.json to state.json.bak. No-op if state.json doesn't
 * exist yet. Called before each Plan run so an unparseable write can be
 * recovered manually.
 */
export async function backupStateFile(
  config: WorkspaceConfig
): Promise<void> {
  try {
    await copyFile(config.statePath, config.stateBackupPath);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
    throw err;
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
  await writeFileAtomic(
    config.statePath,
    JSON.stringify(state, null, 2) + "\n"
  );
}

export async function readDrafts(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.draftsPath, "utf-8");
  } catch {
    return "";
  }
}

export async function readLessons(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.lessonsPath, "utf-8");
  } catch {
    return "";
  }
}

export async function readCompass(config: WorkspaceConfig): Promise<string> {
  try {
    return await readFile(config.compassPath, "utf-8");
  } catch {
    return "";
  }
}

export async function writeCompass(
  config: WorkspaceConfig,
  content: string
): Promise<void> {
  await writeFileAtomic(config.compassPath, content);
}

export async function writeLessons(
  config: WorkspaceConfig,
  content: string
): Promise<void> {
  await writeFileAtomic(config.lessonsPath, content);
}

export async function appendLesson(
  config: WorkspaceConfig,
  text: string
): Promise<void> {
  const trimmed = text.trim();
  if (!trimmed) return;

  const existing = await readLessons(config);
  const separator = existing.length === 0 || existing.endsWith("\n")
    ? ""
    : "\n";
  await appendFile(config.lessonsPath, separator + trimmed + "\n", "utf-8");
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
  await appendFile(config.draftsPath, separator + block, "utf-8");
}

/**
 * Atomically snapshot a workspace file's contents and clear it.
 * Uses fs.rename so writes during the snapshot land in the fresh empty file.
 * Returns "" if the file did not exist or was empty.
 *
 * Exported for tests; prefer the typed `snapshotAndClear*` wrappers below.
 */
export async function snapshotAndConsume(path: string): Promise<string> {
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
