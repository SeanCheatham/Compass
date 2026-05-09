import { resolve } from "path";
import {
  getWorkspaceConfig,
  ensureWorkspaceExists,
} from "../mcp/utils/workspace.js";
import { isGitRepo } from "../mcp/utils/git.js";
import type { WorkspaceConfig } from "./types.js";

export async function initializeWorkspace(
  implRepoPath: string
): Promise<WorkspaceConfig> {
  const absolutePath = resolve(implRepoPath);

  if (!isGitRepo(absolutePath)) {
    throw new Error(
      `${absolutePath} is not a git repository. Initialize with 'git init' first.`
    );
  }

  const config = getWorkspaceConfig(absolutePath);
  await ensureWorkspaceExists(config);
  return config;
}
