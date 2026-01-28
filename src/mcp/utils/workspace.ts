import { homedir } from "os";
import { resolve, sep } from "path";
import { mkdir, access, readFile, writeFile } from "fs/promises";
import type { WorkspaceConfig } from "../../state/types.js";

export function sanitizePath(path: string): string {
  const home = homedir();
  let normalized = path;

  if (normalized.startsWith(home)) {
    normalized = normalized.slice(home.length);
  }

  return normalized
    .split(sep)
    .filter(Boolean)
    .join("-");
}

export function getWorkspacePath(implRepoPath: string): string {
  const sanitized = sanitizePath(implRepoPath);
  return resolve(homedir(), ".compass", sanitized);
}

export function getWorkspaceConfig(implRepoPath: string): WorkspaceConfig {
  const workspacePath = getWorkspacePath(implRepoPath);
  return {
    implRepoPath,
    workspacePath,
    planPath: resolve(workspacePath, "plan.json"),
    notesPath: resolve(workspacePath, "notes.md"),
    sessionsPath: resolve(workspacePath, "sessions"),
    shadowCompassPath: resolve(workspacePath, "compass-shadow.md"),
    issuesPath: resolve(workspacePath, "issues.json"),
  };
}

export async function ensureWorkspaceExists(
  config: WorkspaceConfig
): Promise<void> {
  await mkdir(config.workspacePath, { recursive: true });
  await mkdir(config.sessionsPath, { recursive: true });

  const planExists = await access(config.planPath)
    .then(() => true)
    .catch(() => false);

  if (!planExists) {
    await writeFile(config.planPath, JSON.stringify({ plans: [] }, null, 2));
  }

  const notesExists = await access(config.notesPath)
    .then(() => true)
    .catch(() => false);

  if (!notesExists) {
    await writeFile(config.notesPath, "");
  }

  const issuesExists = await access(config.issuesPath)
    .then(() => true)
    .catch(() => false);

  if (!issuesExists) {
    await writeFile(config.issuesPath, JSON.stringify({ issues: [] }, null, 2));
  }
}

export async function readCompassFile(implRepoPath: string): Promise<string> {
  const compassPath = resolve(implRepoPath, "COMPASS.md");
  try {
    return await readFile(compassPath, "utf-8");
  } catch {
    throw new Error(`COMPASS.md not found in ${implRepoPath}`);
  }
}

export async function readShadowCompass(
  shadowPath: string
): Promise<string | null> {
  try {
    return await readFile(shadowPath, "utf-8");
  } catch {
    return null; // No shadow exists yet (first run)
  }
}

export async function writeShadowCompass(
  shadowPath: string,
  content: string
): Promise<void> {
  await writeFile(shadowPath, content, "utf-8");
}
