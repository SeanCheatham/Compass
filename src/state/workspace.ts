import { access } from "fs/promises";
import { resolve } from "path";
import {
  getWorkspaceConfig,
  ensureWorkspaceExists,
  readCompassFile,
  readShadowCompass,
} from "../mcp/utils/workspace.js";
import { isGitRepo } from "../mcp/utils/git.js";
import {
  detectCompassDiff,
  type CompassDiffResult,
} from "../mcp/utils/compass-diff.js";
import type { WorkspaceConfig } from "./types.js";

export interface WorkspaceInitResult {
  config: WorkspaceConfig;
  compassContent: string;
  compassDiff: CompassDiffResult;
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

  // Read shadow compass and detect diff
  const shadowContent = await readShadowCompass(config.shadowCompassPath);
  const compassDiff = detectCompassDiff(compassContent, shadowContent);

  return { config, compassContent, compassDiff };
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
