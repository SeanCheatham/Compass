import * as fs from 'fs';
import * as path from 'path';
import { logger } from '../utils/logger.js';

export interface CompassState {
  version: string;
  lastUpdated: string;
  currentPlan: string | null;
  completedPlans: string[];
  executionHistory: ExecutionEntry[];
  iterationCount: number;
}

export interface ExecutionEntry {
  planPath: string;
  planTitle: string;
  timestamp: string;
  success: boolean;
  decomposed: boolean;
  output?: string;
  error?: string;
}

const STATE_VERSION = '1.0.0';

/**
 * Create a new empty state
 */
export function createEmptyState(): CompassState {
  return {
    version: STATE_VERSION,
    lastUpdated: new Date().toISOString(),
    currentPlan: null,
    completedPlans: [],
    executionHistory: [],
    iterationCount: 0,
  };
}

/**
 * Load state from disk
 */
export function loadState(stateFile: string): CompassState | null {
  if (!fs.existsSync(stateFile)) {
    logger.debug('No state file found', { stateFile });
    return null;
  }

  try {
    const content = fs.readFileSync(stateFile, 'utf-8');
    const state = JSON.parse(content) as CompassState;

    // Version migration could happen here
    if (state.version !== STATE_VERSION) {
      logger.warn('State version mismatch, may need migration', {
        found: state.version,
        expected: STATE_VERSION,
      });
    }

    logger.debug('Loaded state', {
      completedPlans: state.completedPlans.length,
      iterationCount: state.iterationCount,
    });

    return state;
  } catch (err) {
    logger.error('Failed to load state', { error: (err as Error).message });
    return null;
  }
}

/**
 * Save state to disk
 */
export function saveState(stateFile: string, state: CompassState): void {
  state.lastUpdated = new Date().toISOString();

  const dir = path.dirname(stateFile);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  try {
    const content = JSON.stringify(state, null, 2);
    fs.writeFileSync(stateFile, content, 'utf-8');
    logger.debug('Saved state', { stateFile });
  } catch (err) {
    logger.error('Failed to save state', { error: (err as Error).message });
    throw err;
  }
}

/**
 * Add an execution entry to state
 */
export function addExecutionEntry(
  state: CompassState,
  entry: Omit<ExecutionEntry, 'timestamp'>
): void {
  state.executionHistory.push({
    ...entry,
    timestamp: new Date().toISOString(),
  });

  // Keep only last 100 entries to prevent unbounded growth
  if (state.executionHistory.length > 100) {
    state.executionHistory = state.executionHistory.slice(-100);
  }
}

/**
 * Mark a plan as completed in state
 */
export function markPlanCompleted(state: CompassState, planPath: string): void {
  if (!state.completedPlans.includes(planPath)) {
    state.completedPlans.push(planPath);
  }
  if (state.currentPlan === planPath) {
    state.currentPlan = null;
  }
}

/**
 * Get recently completed plan paths (last N)
 */
export function getRecentlyCompleted(state: CompassState, limit: number = 5): string[] {
  return state.completedPlans.slice(-limit);
}
