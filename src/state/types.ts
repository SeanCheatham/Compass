export interface WorkspaceConfig {
  implRepoPath: string;
  workspacePath: string;
  statePath: string;
  stateBackupPath: string;
  draftsPath: string;
  lessonsPath: string;
  compassPath: string;
  sessionsPath: string;
  sessionsRecordPath: string;
}

/**
 * The single concrete plan Develop will implement next iteration.
 * `verify` is the shell command that must exit 0 before the iteration is accepted.
 */
export interface PlanNext {
  plan: string;
  verify: string;
  /**
   * Optional override for COMPASS_VERIFY_TIMEOUT_MS, in milliseconds. Must be a
   * positive finite integer. When unset, the env var (or its 10-min default)
   * applies. Use this for plans whose verify is unusually slow (e.g. e2e) or
   * unusually fast (e.g. typecheck-only).
   */
  verifyTimeoutMs?: number;
  /**
   * Plan's estimate of how hard the implementation will be. Selects the Develop
   * model: low → Haiku, medium → Sonnet, high → Opus. When omitted the runner
   * defaults to Sonnet.
   */
  estimatedDifficulty?: "low" | "medium" | "high";
}

/**
 * Structured contents of `.compass/state.json`.
 *
 * Three horizons:
 *   - `immediate`: the single concrete plan Develop runs this iteration.
 *   - `midTerm`:   markdown sketch of the next ~3-7 iterations (the promotion queue).
 *   - `longTerm`:  markdown sketch of the strategic arc (~10+ iterations) — Plan's
 *                  read on how to reach the vision in COMPASS.md.
 *
 * Plan owns this file via the `set_state` MCP tool. The runner persists it to
 * disk after each Plan run.
 */
export interface PlanState {
  completed: string[];
  immediate: PlanNext | null;
  midTerm: string;
  longTerm: string;
}

export const EMPTY_PLAN_STATE: PlanState = {
  completed: [],
  immediate: null,
  midTerm: "",
  longTerm: "",
};
