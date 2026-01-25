import { access } from "fs/promises";
import { resolve } from "path";
import {
  getWorkspaceConfig,
  ensureWorkspaceExists,
  readCompassFile,
} from "../mcp/utils/workspace.js";
import { isGitRepo } from "../mcp/utils/git.js";
import type { WorkspaceConfig } from "./types.js";

export interface WorkspaceInitResult {
  config: WorkspaceConfig;
  compassContent: string;
}

export async function initializeWorkspace(
  implRepoPath: string
): Promise<WorkspaceInitResult> {
  const absolutePath = resolve(implRepoPath);

  if (!isGitRepo(absolutePath)) {
    throw new Error(
      `${absolutePath} is not a git repository. Initialize with 'git init' first.`
    );
  }

  const compassContent = await readCompassFile(absolutePath);

  const config = getWorkspaceConfig(absolutePath);

  await ensureWorkspaceExists(config);

  return { config, compassContent };
}

export async function hasCompassFile(implRepoPath: string): Promise<boolean> {
  const compassPath = resolve(implRepoPath, "COMPASS.md");
  try {
    await access(compassPath);
    return true;
  } catch {
    return false;
  }
}
