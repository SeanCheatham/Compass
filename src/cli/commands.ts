import { initializeWorkspace, hasCompassFile } from "../state/workspace.js";
import { runPmAgent } from "../agents/pm.js";
import { runDevAgent } from "../agents/dev.js";
import { runCommitAgent } from "../agents/commit.js";
import {
  readPlanFile,
  getFirstPendingPlan,
  updatePlanCommit,
  writePlanFile,
  findOldestInvalidatedPlan,
  getCommitBeforePlan,
  resetPlansFromId,
  createPlan,
  insertPlanAfter,
} from "../mcp/utils/plan-store.js";
import {
  readIssueFile,
  writeIssueFile,
  getNextOpenIssue,
  updateIssueStatus,
  findIssueByPlanId,
} from "../mcp/utils/issue-store.js";
import {
  commit,
  discardChanges,
  hasUncommittedChanges,
  resetHard,
  isValidCommit,
} from "../mcp/utils/git.js";
import { writeShadowCompass } from "../mcp/utils/workspace.js";
import type { OutputManager } from "../web/output-manager.js";

export interface RunOptions {
  maxIterations?: number;
  output: OutputManager;
}

export async function runCompass(
  cwd: string,
  options: RunOptions
): Promise<void> {
  const maxIterations = options.maxIterations ?? 100;
  const output = options.output;

  output.info("Compass - Autonomous Project Development\n");

  const { config, compassContent, compassDiff } = await initializeWorkspace(cwd);

  output.info(`Impl repo: ${config.implRepoPath}`);
  output.info(`Workspace: ${config.workspacePath}\n`);

  // Handle COMPASS.md changes at startup
  if (compassDiff.isFirstRun) {
    output.info("First run - initializing COMPASS shadow copy\n");
    await writeShadowCompass(config.shadowCompassPath, compassContent);
  } else if (compassDiff.hasDiff) {
    output.info("COMPASS.md has changed since last session");
    output.info(`Changes: ${compassDiff.diffSummary}\n`);

    // Run PM in compass change mode
    const pmResult = await runPmAgent(
      config,
      compassContent,
      output,
      undefined, // no revert reason
      {
        previousCompass: compassDiff.shadowContent!,
        currentCompass: compassContent,
        diffSummary: compassDiff.diffSummary!,
      }
    );

    // Handle invalidation result
    if (pmResult.compassInvalidation) {
      const { invalidatedCompletedPlanIds, reasoning } =
        pmResult.compassInvalidation;

      output.info(`\nPM Analysis: ${reasoning}`);

      if (invalidatedCompletedPlanIds.length > 0) {
        // Need to revert code
        const planFile = await readPlanFile(config.planPath);
        const oldestInvalidated = findOldestInvalidatedPlan(
          planFile.plans,
          invalidatedCompletedPlanIds
        );

        if (oldestInvalidated) {
          const revertToCommit = getCommitBeforePlan(
            planFile.plans,
            oldestInvalidated.id
          );

          if (revertToCommit && (await isValidCommit(config.implRepoPath, revertToCommit))) {
            output.info(
              `\nReverting to commit ${revertToCommit.slice(0, 7)} (before plan ${oldestInvalidated.id})`
            );

            // Discard any uncommitted changes first
            if (await hasUncommittedChanges(config.implRepoPath)) {
              output.info("Discarding uncommitted changes...");
              await discardChanges(config.implRepoPath);
            }

            await resetHard(config.implRepoPath, revertToCommit);
          } else if (!revertToCommit) {
            output.info(
              "\nNo prior commit found - cannot revert code state"
            );
          } else {
            output.info(
              `\nCommit ${revertToCommit.slice(0, 7)} is invalid - cannot revert`
            );
          }

          // Reset plans from the oldest invalidated one
          const resetPlans = resetPlansFromId(
            planFile.plans,
            oldestInvalidated.id
          );
          await writePlanFile(config.planPath, { plans: resetPlans });
          output.info(
            `Reset ${invalidatedCompletedPlanIds.length} completed plan(s) to pending`
          );
        }
      }
    }

    // Update shadow copy after handling changes
    await writeShadowCompass(config.shadowCompassPath, compassContent);
    output.info("\nCOMPASS shadow updated. Proceeding with normal operation.\n");
  }

  let iteration = 0;
  let revertReason: string | undefined;

  while (iteration < maxIterations) {
    iteration++;

    output.session(iteration);

    // Issue injection: check for open issues and create a plan for the next one
    const issueFile = await readIssueFile(config.issuesPath);
    const nextIssue = getNextOpenIssue(issueFile.issues);

    if (nextIssue) {
      const issueLabel = nextIssue.type === "bug" ? "BUG" : "ENHANCEMENT";
      const planContent = `[${issueLabel}] ${nextIssue.title}${
        nextIssue.description ? `: ${nextIssue.description}` : ""
      }`;

      output.info(`Processing issue: ${nextIssue.type} - ${nextIssue.title}`);

      // Create a plan for this issue and insert at position 0
      const planFile = await readPlanFile(config.planPath);
      const issuePlan = createPlan(planContent);
      const updatedPlans = insertPlanAfter(planFile.plans, null, issuePlan);
      await writePlanFile(config.planPath, { plans: updatedPlans });

      // Mark issue as in_progress and link to plan
      const updatedIssues = updateIssueStatus(
        issueFile.issues,
        nextIssue.id,
        "in_progress",
        issuePlan.id
      );
      await writeIssueFile(config.issuesPath, { issues: updatedIssues });
    }

    // Phase 1: PM Agent (read-only, planning)
    output.phase("PM Phase");
    const pmResult = await runPmAgent(config, compassContent, output, revertReason);

    // Clear revert reason after PM has seen it
    revertReason = undefined;

    // Check if all done
    if (!pmResult.hasPendingPlans) {
      output.info("\nAll plans completed! Project is done.");
      break;
    }

    // Phase 2: Dev Agent (read-write, implementation)
    output.phase("Dev Phase");

    const planFile = await readPlanFile(config.planPath);
    const currentTask = getFirstPendingPlan(planFile.plans);

    if (!currentTask) {
      output.info("No pending tasks found. PM may need to create plans.");
      continue;
    }

    output.info(`Task: ${currentTask.content}`);

    const devResult = await runDevAgent(config, currentTask, output);

    // Phase 3: Handle result
    if (devResult.success) {
      // Check for changes to commit
      if (await hasUncommittedChanges(config.implRepoPath)) {
        // Phase 3a: Commit Agent (review and prepare commit)
        output.phase("Commit Phase");
        const commitResult = await runCommitAgent(config, currentTask.content, output);

        if (commitResult.approved) {
          const commitMessage = commitResult.commitMessage
            ? `compass: ${currentTask.content}\n\n${commitResult.commitMessage}`
            : `compass: ${currentTask.content}`;
          const commitSha = await commit(config.implRepoPath, commitMessage);

          // Update plan with commit
          const updatedPlans = updatePlanCommit(
            planFile.plans,
            currentTask.id,
            commitSha
          );
          await writePlanFile(config.planPath, { plans: updatedPlans });

          // Close any linked issue
          const currentIssueFile = await readIssueFile(config.issuesPath);
          const linkedIssue = findIssueByPlanId(currentIssueFile.issues, currentTask.id);
          if (linkedIssue) {
            const closedIssues = updateIssueStatus(
              currentIssueFile.issues,
              linkedIssue.id,
              "closed",
              currentTask.id,
              commitSha
            );
            await writeIssueFile(config.issuesPath, { issues: closedIssues });
            output.info(`Closed issue ${linkedIssue.id}: ${linkedIssue.title}`);
          }

          output.commit(commitSha);
        } else {
          output.info("\nCommit not approved, discarding changes");
          await discardChanges(config.implRepoPath);
          revertReason = "Commit agent did not approve the changes";
        }
      } else {
        output.info("\nNo changes to commit");
      }
    } else {
      // Revert - discard changes
      output.info(`\nReverting: ${devResult.revertReason}`);
      await discardChanges(config.implRepoPath);
      revertReason = devResult.revertReason;
    }
  }

  if (iteration >= maxIterations) {
    output.info(`\nReached maximum iterations (${maxIterations})`);
  }
}

export async function showStatus(cwd: string): Promise<void> {
  if (!(await hasCompassFile(cwd))) {
    console.error("Error: COMPASS.md not found in current directory.");
    process.exit(1);
  }

  const { config } = await initializeWorkspace(cwd);
  const plans = await readPlanFile(config.planPath);

  console.log("🧭 Compass Status\n");
  console.log(`Workspace: ${config.workspacePath}\n`);

  if (plans.plans.length === 0) {
    console.log("No plans defined yet.");
    return;
  }

  const completed = plans.plans.filter((p) => p.status === "completed").length;
  const pending = plans.plans.filter((p) => p.status === "pending").length;

  console.log(
    `Plans: ${plans.plans.length} total (${completed} completed, ${pending} pending)\n`
  );

  for (const plan of plans.plans) {
    const statusIcon = plan.status === "completed" ? "✓" : "○";
    const commitInfo = plan.commit ? ` [${plan.commit.slice(0, 7)}]` : "";
    console.log(`${statusIcon} ${plan.id}: ${plan.content}${commitInfo}`);
  }
}
