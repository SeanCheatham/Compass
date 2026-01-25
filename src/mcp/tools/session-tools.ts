import { writeFile, readdir, unlink } from "fs/promises";
import { resolve, basename } from "path";
import type { WorkspaceConfig, Plan } from "../../state/types.js";
import type { EndSessionInput } from "../schemas/plan.js";
import {
  readPlanFile,
  writePlanFile,
  getFirstPendingPlan,
  updatePlanCommit,
  updatePlanSession,
  resetPlansAfterCommit,
  findPlanById,
} from "../utils/plan-store.js";
import {
  commit,
  discardChanges,
  resetHard,
  getCurrentCommit,
  isValidCommit,
} from "../utils/git.js";

export interface EndSessionResult {
  done: boolean;
  message: string;
  revertReason?: string;
}

function generateSessionFileName(planId: string): string {
  const timestamp = Math.floor(Date.now() / 1000);
  return `${planId}-${timestamp}.md`;
}

async function writeSessionSummary(
  config: WorkspaceConfig,
  planId: string,
  content: string,
  outcome: string,
  summary: string,
  commitSha: string | null
): Promise<string> {
  const fileName = generateSessionFileName(planId);
  const filePath = resolve(config.sessionsPath, fileName);

  const sessionContent = `# Session: ${planId}

**Plan**: ${content}
**Outcome**: ${outcome}
**Commit**: ${commitSha ?? "N/A"}

## Summary

${summary}
`;

  await writeFile(filePath, sessionContent, "utf-8");
  return fileName;
}

async function deleteSessionsAfter(
  config: WorkspaceConfig,
  plans: Plan[],
  revertToPlanId: string
): Promise<void> {
  const revertIndex = plans.findIndex((p) => p.id === revertToPlanId);
  if (revertIndex === -1) return;

  const plansToReset = plans.slice(revertIndex + 1);
  const sessionFiles = await readdir(config.sessionsPath);

  for (const plan of plansToReset) {
    if (plan.session) {
      const sessionPath = resolve(config.sessionsPath, plan.session);
      try {
        await unlink(sessionPath);
      } catch {
        // Session file may not exist
      }
    }
  }
}

export async function endSession(
  config: WorkspaceConfig,
  input: EndSessionInput
): Promise<EndSessionResult> {
  const planFile = await readPlanFile(config.planPath);
  const currentPlan = getFirstPendingPlan(planFile.plans);

  if (input.outcome === "commit") {
    if (!currentPlan) {
      return {
        done: true,
        message: "No pending plans to commit",
      };
    }

    const commitMessage = `compass: ${currentPlan.content}`;
    const commitSha = await commit(config.implRepoPath, commitMessage);

    const sessionFile = await writeSessionSummary(
      config,
      currentPlan.id,
      currentPlan.content,
      "commit",
      input.summary,
      commitSha
    );

    const updatedPlans = updatePlanCommit(
      planFile.plans,
      currentPlan.id,
      commitSha,
      sessionFile
    );

    await writePlanFile(config.planPath, { plans: updatedPlans });

    const hasMorePending = updatedPlans.some((p) => p.status === "pending");

    return {
      done: !hasMorePending,
      message: `Committed ${currentPlan.id} as ${commitSha.slice(0, 7)}`,
    };
  }

  if (input.outcome === "replanned") {
    await discardChanges(config.implRepoPath);

    if (currentPlan) {
      const currentCommit = await getCurrentCommit(config.implRepoPath);
      const sessionFile = await writeSessionSummary(
        config,
        currentPlan.id,
        currentPlan.content,
        "replanned",
        input.summary,
        currentCommit
      );

      const updatedPlans = updatePlanSession(
        planFile.plans,
        currentPlan.id,
        sessionFile
      );

      await writePlanFile(config.planPath, { plans: updatedPlans });
    }

    const hasMorePending = planFile.plans.some((p) => p.status === "pending");

    return {
      done: !hasMorePending,
      message: "Session ended with replanning. Implementation changes discarded.",
    };
  }

  if (input.outcome === "revert") {
    let revertCommit: string;
    let revertPlanId: string | undefined;

    const plan = findPlanById(planFile.plans, input.revert_to);

    if (plan?.commit) {
      revertCommit = plan.commit;
      revertPlanId = plan.id;
    } else if (await isValidCommit(config.implRepoPath, input.revert_to)) {
      revertCommit = input.revert_to;
      const matchingPlan = planFile.plans.find(
        (p) => p.commit === input.revert_to
      );
      revertPlanId = matchingPlan?.id;
    } else {
      return {
        done: false,
        message: `Invalid revert target: ${input.revert_to}. Must be a valid plan ID with a commit or a valid commit SHA.`,
      };
    }

    await resetHard(config.implRepoPath, revertCommit);

    if (revertPlanId) {
      await deleteSessionsAfter(config, planFile.plans, revertPlanId);
    }

    const updatedPlans = resetPlansAfterCommit(planFile.plans, revertCommit);
    await writePlanFile(config.planPath, { plans: updatedPlans });

    return {
      done: false,
      message: `Reverted to ${revertCommit.slice(0, 7)}. Plans after this point reset to pending.`,
      revertReason: input.reason,
    };
  }

  return {
    done: false,
    message: "Unknown outcome",
  };
}
