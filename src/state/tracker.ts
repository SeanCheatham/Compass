import * as path from 'path';
import {
  CompassState,
  createEmptyState,
  loadState,
  saveState,
  addExecutionEntry,
  markPlanCompleted,
  getRecentlyCompleted,
} from './persistence.js';
import { logger } from '../utils/logger.js';

export class StateTracker {
  private state: CompassState;
  private stateFile: string;
  private autoSave: boolean;

  constructor(compassDir: string, options?: { autoSave?: boolean }) {
    this.stateFile = path.join(compassDir, 'state.json');
    this.autoSave = options?.autoSave ?? true;

    const loaded = loadState(this.stateFile);
    this.state = loaded || createEmptyState();

    logger.debug('StateTracker initialized', {
      hasExistingState: !!loaded,
      completedPlans: this.state.completedPlans.length,
    });
  }

  /**
   * Get the current state (read-only snapshot)
   */
  getState(): Readonly<CompassState> {
    return this.state;
  }

  /**
   * Get the current plan being executed
   */
  getCurrentPlan(): string | null {
    return this.state.currentPlan;
  }

  /**
   * Set the current plan being executed
   */
  setCurrentPlan(planPath: string | null): void {
    this.state.currentPlan = planPath;
    if (this.autoSave) {
      this.save();
    }
  }

  /**
   * Record a successful plan execution
   */
  recordSuccess(planPath: string, planTitle: string, output?: string): void {
    addExecutionEntry(this.state, {
      planPath,
      planTitle,
      success: true,
      decomposed: false,
      output: output?.slice(0, 1000), // Truncate for storage
    });
    markPlanCompleted(this.state, planPath);
    this.state.iterationCount++;

    if (this.autoSave) {
      this.save();
    }
  }

  /**
   * Record a plan decomposition
   */
  recordDecomposition(planPath: string, planTitle: string, reason: string): void {
    addExecutionEntry(this.state, {
      planPath,
      planTitle,
      success: true,
      decomposed: true,
      output: `Decomposed: ${reason}`,
    });
    this.state.iterationCount++;

    if (this.autoSave) {
      this.save();
    }
  }

  /**
   * Record a failed plan execution
   */
  recordFailure(planPath: string, planTitle: string, error: string): void {
    addExecutionEntry(this.state, {
      planPath,
      planTitle,
      success: false,
      decomposed: false,
      error,
    });

    if (this.autoSave) {
      this.save();
    }
  }

  /**
   * Get recently completed plans
   */
  getRecentlyCompleted(limit?: number): string[] {
    return getRecentlyCompleted(this.state, limit);
  }

  /**
   * Check if a plan has been completed
   */
  isPlanCompleted(planPath: string): boolean {
    return this.state.completedPlans.includes(planPath);
  }

  /**
   * Get execution history
   */
  getHistory(limit?: number): CompassState['executionHistory'] {
    const history = this.state.executionHistory;
    return limit ? history.slice(-limit) : history;
  }

  /**
   * Get iteration count
   */
  getIterationCount(): number {
    return this.state.iterationCount;
  }

  /**
   * Increment iteration count (for reconciliation steps etc.)
   */
  incrementIteration(): void {
    this.state.iterationCount++;
    if (this.autoSave) {
      this.save();
    }
  }

  /**
   * Save state to disk
   */
  save(): void {
    saveState(this.stateFile, this.state);
  }

  /**
   * Reset state (for testing or fresh start)
   */
  reset(): void {
    this.state = createEmptyState();
    if (this.autoSave) {
      this.save();
    }
  }
}
