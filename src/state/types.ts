export interface WorkspaceConfig {
  implRepoPath: string;
  workspacePath: string;
  statePath: string;
  stateBackupPath: string;
  draftsPath: string;
  lessonsPath: string;
  sessionsPath: string;
  sessionsRecordPath: string;
}

/**
 * The single concrete plan Develop will implement next.
 * `verify` is the shell command that must exit 0 before the iteration is accepted.
 */
export interface PlanNext {
  plan: string;
  verify: string;
}

/**
 * Structured contents of `.compass/state.json`.
 * Plan owns this file via the `set_state` MCP tool. The runner persists it to disk
 * after each Plan run.
 */
export interface PlanState {
  completed: string[];
  next: PlanNext | null;
  followUp: string;
}

export const EMPTY_PLAN_STATE: PlanState = {
  completed: [],
  next: null,
  followUp: "",
};
