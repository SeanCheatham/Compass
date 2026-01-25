import { initializeWorkspace, hasCompassFile } from "../state/workspace.js";
import { runPmSession } from "../agents/pm.js";
import { readPlanFile } from "../mcp/utils/plan-store.js";

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
    console.error("Create a COMPASS.md file with your project vision to get started.");
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

    const plans = await readPlanFile(config.planPath);
    const pendingCount = plans.plans.filter((p) => p.status === "pending").length;

    if (pendingCount === 0 && plans.plans.length > 0) {
      console.log("\n✅ All plans completed! Project is done.");
      break;
    }

    console.log(`\n--- Session ${iteration} ---`);
    if (pendingCount > 0) {
      console.log(`Pending plans: ${pendingCount}`);
    } else {
      console.log("No plans yet - will create initial plans from COMPASS.md");
    }
    console.log("");

    try {
      const result = await runPmSession(config, compassContent, revertReason);

      revertReason = result.revertReason;

      if (result.done) {
        console.log("\n✅ All plans completed! Project is done.");
        break;
      }
    } catch (error) {
      console.error("\n❌ Session error:", error);
      console.log("Waiting before retry...");
      await new Promise((resolve) => setTimeout(resolve, 5000));
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

  console.log(`Plans: ${plans.plans.length} total (${completed} completed, ${pending} pending)\n`);

  for (const plan of plans.plans) {
    const statusIcon = plan.status === "completed" ? "✓" : "○";
    const commitInfo = plan.commit ? ` [${plan.commit.slice(0, 7)}]` : "";
    console.log(`${statusIcon} ${plan.id}: ${plan.content}${commitInfo}`);
  }
}
