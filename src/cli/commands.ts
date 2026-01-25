import { initializeWorkspace, hasCompassFile } from "../state/workspace.js";
import { runPmAgent } from "../agents/pm.js";
import { runDevAgent } from "../agents/dev.js";
import { runCommitAgent } from "../agents/commit.js";
import {
  readPlanFile,
  getFirstPendingPlan,
  updatePlanCommit,
  writePlanFile,
} from "../mcp/utils/plan-store.js";
import {
  commit,
  discardChanges,
  hasUncommittedChanges,
} from "../mcp/utils/git.js";

export interface RunOptions {
  maxIterations?: number;
}

export async function runCompass(
  cwd: string,
  options: RunOptions = {}
): Promise<void> {
  const maxIterations = options.maxIterations ?? 100;

  if (!(await hasCompassFile(cwd))) {
    console.error("Error: COMPASS.md not found in current directory.");
    console.error(
      "Create a COMPASS.md file with your project vision to get started."
    );
    process.exit(1);
  }

  console.log("🧭 Compass - Autonomous Project Development\n");

  const { config, compassContent } = await initializeWorkspace(cwd);

  console.log(`Impl repo: ${config.implRepoPath}`);
  console.log(`Workspace: ${config.workspacePath}\n`);

  let iteration = 0;
  let revertReason: string | undefined;

  while (iteration < maxIterations) {
    iteration++;

    console.log(`\n${"=".repeat(60)}`);
    console.log(`Session ${iteration}`);
    console.log("=".repeat(60));

    // Phase 1: PM Agent (read-only, planning)
    console.log("\n--- PM Phase ---");
    const pmResult = await runPmAgent(config, compassContent, revertReason);

    // Clear revert reason after PM has seen it
    revertReason = undefined;

    // Check if all done
    if (!pmResult.hasPendingPlans) {
      console.log("\n✅ All plans completed! Project is done.");
      break;
    }

    // Phase 2: Dev Agent (read-write, implementation)
    console.log("\n--- Dev Phase ---");

    const planFile = await readPlanFile(config.planPath);
    const currentTask = getFirstPendingPlan(planFile.plans);

    if (!currentTask) {
      console.log("No pending tasks found. PM may need to create plans.");
      continue;
    }

    console.log(`Task: ${currentTask.content}`);

    const devResult = await runDevAgent(config, currentTask);

    // Phase 3: Handle result
    if (devResult.success) {
      // Check for changes to commit
      if (await hasUncommittedChanges(config.implRepoPath)) {
        // Phase 3a: Commit Agent (review and prepare commit)
        console.log("\n--- Commit Phase ---");
        const commitResult = await runCommitAgent(config, currentTask.content);

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

          console.log(`\n✅ Committed: ${commitSha.slice(0, 7)}`);
        } else {
          console.log("\n⚠️ Commit not approved, discarding changes");
          await discardChanges(config.implRepoPath);
          revertReason = "Commit agent did not approve the changes";
        }
      } else {
        console.log("\n⚠️ No changes to commit");
      }
    } else {
      // Revert - discard changes
      console.log(`\n↩️ Reverting: ${devResult.revertReason}`);
      await discardChanges(config.implRepoPath);
      revertReason = devResult.revertReason;
    }
  }

  if (iteration >= maxIterations) {
    console.log(`\n⚠️ Reached maximum iterations (${maxIterations})`);
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
