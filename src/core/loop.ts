import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';
import ora from 'ora';
import chalk from 'chalk';
import { buildPlanTree, PlanTree, formatTreeForDisplay, getTreeStats } from '../plans/tree.js';
import { selectNextPlan } from '../plans/prioritizer.js';
import { executePlan, createSubPlansContent, ExecutionContext } from './executor.js';
import { StateTracker } from '../state/tracker.js';
import { invokeClaude } from '../utils/claude.js';
import { logger } from '../utils/logger.js';

export interface LoopConfig {
  projectRoot: string;
  compassDir: string;
  maxIterations?: number;
}

export interface LoopResult {
  success: boolean;
  iterationsRun: number;
  reason: string;
}

/**
 * Check if working directory is clean (no uncommitted changes)
 */
function isGitClean(cwd: string): boolean {
  try {
    const status = execSync('git status --porcelain', { cwd, encoding: 'utf-8' });
    return status.trim() === '';
  } catch {
    // Not a git repo or git not available
    return true;
  }
}

/**
 * Commit changes with a message
 */
function gitCommit(cwd: string, message: string): boolean {
  try {
    execSync('git add -A', { cwd, encoding: 'utf-8' });
    const status = execSync('git status --porcelain', { cwd, encoding: 'utf-8' });
    if (status.trim() === '') {
      logger.debug('No changes to commit');
      return true;
    }
    execSync(`git commit -m "${message.replace(/"/g, '\\"')}"`, { cwd, encoding: 'utf-8' });
    logger.info('Committed changes', { message });
    return true;
  } catch (err) {
    logger.error('Git commit failed', { error: (err as Error).message });
    return false;
  }
}

/**
 * Read file content or return empty string
 */
function readFileOrEmpty(filePath: string): string {
  if (fs.existsSync(filePath)) {
    return fs.readFileSync(filePath, 'utf-8');
  }
  return '';
}

/**
 * Compare two files and return true if they differ
 */
function filesAreDifferent(file1: string, file2: string): boolean {
  const content1 = readFileOrEmpty(file1);
  const content2 = readFileOrEmpty(file2);
  return content1 !== content2;
}

/**
 * Copy file content (creating shadow copy)
 */
function copyFile(src: string, dest: string): void {
  const content = readFileOrEmpty(src);
  const dir = path.dirname(dest);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(dest, content, 'utf-8');
}

/**
 * Run the main Compass loop
 */
export async function runLoop(config: LoopConfig): Promise<LoopResult> {
  const { projectRoot, compassDir, maxIterations } = config;

  // Paths
  const northFile = path.join(projectRoot, 'NORTH.md');
  const southFile = path.join(projectRoot, 'SOUTH.md');
  const shadowNorth = path.join(compassDir, '.north.md');
  const shadowSouth = path.join(compassDir, '.south.md');
  const plansDir = path.join(compassDir, 'plans');
  const architectureFile = path.join(compassDir, 'docs', 'architecture.md');
  const logFile = path.join(compassDir, 'compass.log');

  // Initialize logger with log file
  logger.setLogFile(logFile);

  // Check for clean workspace
  if (!isGitClean(projectRoot)) {
    logger.error('Working directory has uncommitted changes. Commit or stash before running compass.');
    return {
      success: false,
      iterationsRun: 0,
      reason: 'Uncommitted changes in working directory',
    };
  }

  // Initialize state tracker
  const stateTracker = new StateTracker(compassDir);
  let iterationsRun = 0;

  logger.info('Starting Compass loop', {
    maxIterations: maxIterations ?? 'unlimited',
    resumingFrom: stateTracker.getIterationCount(),
  });

  // Main loop
  while (true) {
    // Check iteration limit
    if (maxIterations !== undefined && iterationsRun >= maxIterations) {
      logger.info('Reached iteration limit', { maxIterations });
      return {
        success: true,
        iterationsRun,
        reason: `Completed ${iterationsRun} iterations (limit reached)`,
      };
    }

    const spinner = ora('Checking for direction changes...').start();

    // Step 0: Check for NORTH/SOUTH changes
    const northChanged = filesAreDifferent(northFile, shadowNorth);
    const southChanged = filesAreDifferent(southFile, shadowSouth);
    const directionChanged = northChanged || southChanged;

    if (directionChanged) {
      spinner.text = 'Direction changed, running full reconciliation...';
      logger.info('Direction files changed, updating shadow copies', { northChanged, southChanged });

      // Update shadow copies
      copyFile(northFile, shadowNorth);
      copyFile(southFile, shadowSouth);
    }

    // Read current direction
    const northContent = readFileOrEmpty(northFile);
    const southContent = readFileOrEmpty(southFile);

    if (!northContent) {
      spinner.fail('NORTH.md not found or empty');
      return {
        success: false,
        iterationsRun,
        reason: 'NORTH.md is required but not found',
      };
    }

    // Step 1-2: Reconciliation (only if direction changed)
    if (directionChanged) {
      spinner.text = 'Reconciling architecture with direction...';

      const architectureContent = readFileOrEmpty(architectureFile);
      const reconcileResult = await reconcileArchitecture(
        northContent,
        southContent,
        architectureContent,
        projectRoot
      );

      if (reconcileResult.needsUpdate) {
        spinner.text = 'Updating architecture documentation...';
        fs.writeFileSync(architectureFile, reconcileResult.updatedArchitecture, 'utf-8');
        gitCommit(projectRoot, 'compass: reconcile architecture with direction');
      }
    }

    // Step 3: Build plan tree
    spinner.text = 'Building plan tree...';
    const tree = await buildPlanTree(plansDir);
    const stats = getTreeStats(tree);

    if (stats.total === 0) {
      spinner.fail('No plans found');
      logger.warn('No plans found in plans directory');
      return {
        success: true,
        iterationsRun,
        reason: 'No plans to execute',
      };
    }

    if (stats.pending === 0 && stats.inProgress === 0) {
      spinner.succeed('All plans completed!');
      logger.info('All plans have been completed');
      return {
        success: true,
        iterationsRun,
        reason: 'All plans completed',
      };
    }

    // Step 4: Select next plan
    spinner.text = 'Selecting next plan...';
    const prioritization = await selectNextPlan({
      northContent,
      southContent,
      recentlyCompleted: stateTracker.getRecentlyCompleted(),
      tree,
    });

    if (!prioritization.selectedPlan) {
      spinner.warn('No executable plans available');
      logger.info('No executable plans (all blocked or in progress)');
      return {
        success: true,
        iterationsRun,
        reason: 'No executable plans available',
      };
    }

    const selectedPlan = prioritization.selectedPlan;
    spinner.succeed(`Selected: ${chalk.cyan(selectedPlan.plan.title)}`);
    logger.info('Selected plan for execution', {
      plan: selectedPlan.plan.title,
      reasoning: prioritization.reasoning,
    });

    // Step 5: Execute plan
    const execSpinner = ora(`Executing: ${selectedPlan.plan.title}`).start();
    stateTracker.setCurrentPlan(selectedPlan.plan.path);

    const executionContext: ExecutionContext = {
      northContent,
      southContent,
      architectureContent: readFileOrEmpty(architectureFile),
      projectRoot,
      compassDir,
    };

    const result = await executePlan(selectedPlan, executionContext);

    if (!result.success) {
      execSpinner.fail(`Execution failed: ${selectedPlan.plan.title}`);
      stateTracker.recordFailure(selectedPlan.plan.path, selectedPlan.plan.title, result.error || 'Unknown error');

      logger.error('Plan execution failed, stopping loop', {
        plan: selectedPlan.plan.title,
        error: result.error,
      });

      return {
        success: false,
        iterationsRun,
        reason: `Execution failed: ${result.error}`,
      };
    }

    // Handle decomposition
    if (result.decomposition) {
      execSpinner.info(`Plan decomposed: ${selectedPlan.plan.title}`);

      // Create sub-plans directory
      const parentFileName = path.basename(selectedPlan.plan.path, '.md');
      const subPlansDir = path.join(path.dirname(selectedPlan.plan.path), parentFileName);

      if (!fs.existsSync(subPlansDir)) {
        fs.mkdirSync(subPlansDir, { recursive: true });
      }

      // Write sub-plan files
      const subPlans = createSubPlansContent(selectedPlan, result.decomposition);
      for (const [fileName, content] of subPlans) {
        const filePath = path.join(subPlansDir, fileName);
        fs.writeFileSync(filePath, content, 'utf-8');
        logger.info('Created sub-plan', { path: filePath });
      }

      stateTracker.recordDecomposition(
        selectedPlan.plan.path,
        selectedPlan.plan.title,
        result.decomposition.reason
      );

      gitCommit(projectRoot, `compass: decompose "${selectedPlan.plan.title}"`);
    } else {
      // Step 6: Commit changes
      execSpinner.succeed(`Completed: ${selectedPlan.plan.title}`);
      stateTracker.recordSuccess(selectedPlan.plan.path, selectedPlan.plan.title, result.output);

      gitCommit(projectRoot, `compass: complete "${selectedPlan.plan.title}"`);
    }

    iterationsRun++;
    stateTracker.setCurrentPlan(null);

    // Brief pause between iterations
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
}

interface ReconciliationResult {
  needsUpdate: boolean;
  updatedArchitecture: string;
}

async function reconcileArchitecture(
  northContent: string,
  southContent: string,
  architectureContent: string,
  projectRoot: string
): Promise<ReconciliationResult> {
  const prompt = `You are reconciling project architecture documentation with the project's direction.

## Project Goals (NORTH.md)
${northContent}

## Anti-patterns to Avoid (SOUTH.md)
${southContent}

## Current Architecture Documentation
${architectureContent || 'No architecture documentation exists yet.'}

## Instructions
Review the architecture documentation against NORTH.md and SOUTH.md:
1. If the architecture aligns with the direction, respond with: ALIGNED
2. If the architecture needs updates, respond with:
   NEEDS_UPDATE
   [Updated architecture markdown content]

Only suggest changes that are necessary to align with the project direction.
Do not add speculative features or over-engineer the architecture.`;

  const response = await invokeClaude({
    prompt,
    cwd: projectRoot,
    timeout: 120000,
  });

  if (!response.success) {
    logger.warn('Architecture reconciliation failed', { error: response.error });
    return { needsUpdate: false, updatedArchitecture: architectureContent };
  }

  if (response.output.includes('ALIGNED')) {
    return { needsUpdate: false, updatedArchitecture: architectureContent };
  }

  const updateMatch = response.output.match(/NEEDS_UPDATE\s*([\s\S]+)/);
  if (updateMatch) {
    return {
      needsUpdate: true,
      updatedArchitecture: updateMatch[1].trim(),
    };
  }

  return { needsUpdate: false, updatedArchitecture: architectureContent };
}
