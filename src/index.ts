#!/usr/bin/env node

import { Command } from 'commander';
import * as fs from 'fs';
import * as path from 'path';
import chalk from 'chalk';
import ora from 'ora';
import { runLoop } from './core/loop.js';
import { buildPlanTree, formatTreeForDisplay, getTreeStats } from './plans/tree.js';
import { StateTracker } from './state/tracker.js';
import { logger } from './utils/logger.js';

const COMPASS_DIR = '.compass';

const program = new Command();

program
  .name('compass')
  .description('Recursive iteration tool for project development')
  .version('0.1.0');

/**
 * Initialize .compass directory structure
 */
program
  .command('init')
  .description('Initialize Compass in the current project')
  .option('--force', 'Overwrite existing .compass directory')
  .action(async (options) => {
    const projectRoot = process.cwd();
    const compassDir = path.join(projectRoot, COMPASS_DIR);

    if (fs.existsSync(compassDir) && !options.force) {
      console.log(chalk.yellow('Compass already initialized. Use --force to reinitialize.'));
      process.exit(1);
    }

    const spinner = ora('Initializing Compass...').start();

    try {
      // Create directory structure
      const dirs = [
        compassDir,
        path.join(compassDir, 'plans'),
        path.join(compassDir, 'docs'),
      ];

      for (const dir of dirs) {
        if (!fs.existsSync(dir)) {
          fs.mkdirSync(dir, { recursive: true });
        }
      }

      // Create NORTH.md if it doesn't exist
      const northFile = path.join(projectRoot, 'NORTH.md');
      if (!fs.existsSync(northFile)) {
        fs.writeFileSync(northFile, `# NORTH.md - Project Direction

## Project Description
[Describe your project here]

## Goals
- [Goal 1]
- [Goal 2]

## Theme
[What is the guiding principle or theme of this project?]

## Success Criteria
- [Criterion 1]
- [Criterion 2]
`, 'utf-8');
        console.log(chalk.dim('  Created NORTH.md'));
      }

      // Create SOUTH.md if it doesn't exist
      const southFile = path.join(projectRoot, 'SOUTH.md');
      if (!fs.existsSync(southFile)) {
        fs.writeFileSync(southFile, `# SOUTH.md - Anti-patterns & Legacy

## Anti-patterns to Avoid
- [Pattern to avoid 1]
- [Pattern to avoid 2]

## Legacy Code
[List any legacy code that should be removed or refactored]

## Technical Debt
[Track technical debt items here]
`, 'utf-8');
        console.log(chalk.dim('  Created SOUTH.md'));
      }

      // Create initial architecture.md
      const archFile = path.join(compassDir, 'docs', 'architecture.md');
      if (!fs.existsSync(archFile)) {
        fs.writeFileSync(archFile, `# Architecture

## Overview
[High-level architecture description]

## Components
[List main components]

## Data Flow
[Describe how data flows through the system]
`, 'utf-8');
        console.log(chalk.dim('  Created .compass/docs/architecture.md'));
      }

      // Create example plan
      const examplePlan = path.join(compassDir, 'plans', 'plan-1.md');
      if (!fs.existsSync(examplePlan)) {
        fs.writeFileSync(examplePlan, `# Plan: Initial Setup

## Status
pending

## Priority
high

## Dependencies

## Description
Set up the initial project structure and configuration.

## Acceptance Criteria
- [ ] Project structure is in place
- [ ] Configuration files are created
- [ ] Dependencies are installed
`, 'utf-8');
        console.log(chalk.dim('  Created .compass/plans/plan-1.md'));
      }

      // Create .gitignore entries for compass
      const gitignore = path.join(compassDir, '.gitignore');
      fs.writeFileSync(gitignore, `# Compass internal files
state.json
compass.log
.north.md
.south.md
`, 'utf-8');

      spinner.succeed('Compass initialized successfully');

      console.log('\nNext steps:');
      console.log(chalk.cyan('  1. Edit NORTH.md to define your project goals'));
      console.log(chalk.cyan('  2. Edit SOUTH.md to define anti-patterns to avoid'));
      console.log(chalk.cyan('  3. Create plans in .compass/plans/'));
      console.log(chalk.cyan('  4. Run: compass run'));
    } catch (err) {
      spinner.fail('Initialization failed');
      console.error(chalk.red((err as Error).message));
      process.exit(1);
    }
  });

/**
 * Run the autonomous execution loop
 */
program
  .command('run')
  .description('Start autonomous plan execution')
  .option('-n, --max-iterations <number>', 'Maximum iterations to run', parseInt)
  .option('--dry-run', 'Show what would be executed without running')
  .action(async (options) => {
    const projectRoot = process.cwd();
    const compassDir = path.join(projectRoot, COMPASS_DIR);

    // Check if compass is initialized
    if (!fs.existsSync(compassDir)) {
      console.log(chalk.red('Compass not initialized. Run: compass init'));
      process.exit(1);
    }

    // Check for NORTH.md
    const northFile = path.join(projectRoot, 'NORTH.md');
    if (!fs.existsSync(northFile)) {
      console.log(chalk.red('NORTH.md not found. This file is required.'));
      process.exit(1);
    }

    if (options.dryRun) {
      console.log(chalk.yellow('Dry run mode - showing current state\n'));
      await showStatus(compassDir);
      return;
    }

    console.log(chalk.bold('\n🧭 Compass - Autonomous Plan Execution\n'));

    try {
      const result = await runLoop({
        projectRoot,
        compassDir,
        maxIterations: options.maxIterations,
      });

      console.log('\n' + chalk.bold('─'.repeat(50)));

      if (result.success) {
        console.log(chalk.green(`\n✓ ${result.reason}`));
        console.log(chalk.dim(`  Iterations run: ${result.iterationsRun}`));
      } else {
        console.log(chalk.red(`\n✗ ${result.reason}`));
        console.log(chalk.dim(`  Iterations run: ${result.iterationsRun}`));
        process.exit(1);
      }
    } catch (err) {
      logger.error('Loop crashed', { error: (err as Error).message });
      console.error(chalk.red('\nLoop crashed: ' + (err as Error).message));
      process.exit(1);
    }
  });

/**
 * Show current status
 */
program
  .command('status')
  .description('Show current Compass status')
  .action(async () => {
    const projectRoot = process.cwd();
    const compassDir = path.join(projectRoot, COMPASS_DIR);

    if (!fs.existsSync(compassDir)) {
      console.log(chalk.red('Compass not initialized. Run: compass init'));
      process.exit(1);
    }

    await showStatus(compassDir);
  });

async function showStatus(compassDir: string): Promise<void> {
  const plansDir = path.join(compassDir, 'plans');

  console.log(chalk.bold('\n🧭 Compass Status\n'));

  // Build and display plan tree
  const tree = await buildPlanTree(plansDir);
  const stats = getTreeStats(tree);

  console.log(chalk.bold('Plan Tree:'));
  if (stats.total === 0) {
    console.log(chalk.dim('  No plans found'));
  } else {
    console.log(formatTreeForDisplay(tree));
  }

  console.log('\n' + chalk.bold('Statistics:'));
  console.log(`  Total plans:  ${stats.total}`);
  console.log(`  Leaf plans:   ${stats.leaves}`);
  console.log(`  ${chalk.green('Completed:')}   ${stats.completed}`);
  console.log(`  ${chalk.yellow('In Progress:')} ${stats.inProgress}`);
  console.log(`  ${chalk.gray('Pending:')}     ${stats.pending}`);
  console.log(`  ${chalk.red('Blocked:')}     ${stats.blocked}`);

  // Show state tracker info
  const stateTracker = new StateTracker(compassDir, { autoSave: false });
  const state = stateTracker.getState();

  console.log('\n' + chalk.bold('Execution State:'));
  console.log(`  Iterations run: ${state.iterationCount}`);
  console.log(`  Current plan:   ${state.currentPlan || chalk.dim('none')}`);

  if (state.executionHistory.length > 0) {
    console.log('\n' + chalk.bold('Recent History:'));
    const recent = state.executionHistory.slice(-5);
    for (const entry of recent) {
      const icon = entry.success ? (entry.decomposed ? '🔀' : '✓') : '✗';
      const status = entry.success ? chalk.green(icon) : chalk.red(icon);
      const time = new Date(entry.timestamp).toLocaleTimeString();
      console.log(`  ${status} ${chalk.dim(time)} ${entry.planTitle}`);
    }
  }

  console.log();
}

program.parse();
