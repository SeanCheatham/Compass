import { readFile, writeFile } from "fs/promises";
import { PlanFileSchema, type Plan, type PlanFile } from "../../state/types.js";
import { generatePlanId } from "../../utils/hash.js";

export async function readPlanFile(planPath: string): Promise<PlanFile> {
  try {
    const content = await readFile(planPath, "utf-8");
    const data = JSON.parse(content);
    return PlanFileSchema.parse(data);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { plans: [] };
    }
    throw error;
  }
}

export async function writePlanFile(
  planPath: string,
  planFile: PlanFile
): Promise<void> {
  const validated = PlanFileSchema.parse(planFile);
  await writeFile(planPath, JSON.stringify(validated, null, 2));
}

export function createPlan(content: string): Plan {
  return {
    id: generatePlanId(content),
    content,
    status: "pending",
    commit: null,
    session: null,
  };
}

export function findPlanById(plans: Plan[], id: string): Plan | undefined {
  return plans.find((p) => p.id === id);
}

export function findPlanIndex(plans: Plan[], id: string): number {
  return plans.findIndex((p) => p.id === id);
}

export function getFirstPendingPlan(plans: Plan[]): Plan | undefined {
  return plans.find((p) => p.status === "pending");
}

export function insertPlanAfter(
  plans: Plan[],
  afterId: string | null,
  newPlan: Plan
): Plan[] {
  const result = [...plans];

  if (afterId === null) {
    result.unshift(newPlan);
  } else {
    const index = findPlanIndex(result, afterId);
    if (index === -1) {
      throw new Error(`Plan with ID ${afterId} not found`);
    }
    result.splice(index + 1, 0, newPlan);
  }

  return result;
}

export function insertPlansAfter(
  plans: Plan[],
  afterId: string | null,
  newPlans: Plan[]
): Plan[] {
  let result = [...plans];

  if (afterId === null) {
    result = [...newPlans, ...result];
  } else {
    const index = findPlanIndex(result, afterId);
    if (index === -1) {
      throw new Error(`Plan with ID ${afterId} not found`);
    }
    result.splice(index + 1, 0, ...newPlans);
  }

  return result;
}

export function removePlan(plans: Plan[], id: string): Plan[] {
  const plan = findPlanById(plans, id);
  if (!plan) {
    throw new Error(`Plan with ID ${id} not found`);
  }
  if (plan.commit !== null) {
    throw new Error(`Cannot remove committed plan ${id}`);
  }
  return plans.filter((p) => p.id !== id);
}

export function updatePlanStatus(
  plans: Plan[],
  id: string,
  status: "pending" | "completed"
): Plan[] {
  return plans.map((p) => (p.id === id ? { ...p, status } : p));
}

export function updatePlanCommit(
  plans: Plan[],
  id: string,
  commit: string,
  session: string | null = null
): Plan[] {
  return plans.map((p) =>
    p.id === id ? { ...p, commit, session, status: "completed" as const } : p
  );
}

export function updatePlanSession(
  plans: Plan[],
  id: string,
  session: string
): Plan[] {
  return plans.map((p) => (p.id === id ? { ...p, session } : p));
}

export function resetPlansAfterCommit(
  plans: Plan[],
  commitSha: string
): Plan[] {
  let foundCommit = false;

  return plans.map((p) => {
    if (p.commit === commitSha) {
      foundCommit = true;
      return p;
    }

    if (foundCommit) {
      return {
        ...p,
        status: "pending" as const,
        commit: null,
        session: null,
      };
    }

    return p;
  });
}

/**
 * Find the oldest (first in order) completed plan that is in the invalidated list.
 */
export function findOldestInvalidatedPlan(
  plans: Plan[],
  invalidatedIds: string[]
): Plan | null {
  for (const plan of plans) {
    if (plan.status === "completed" && invalidatedIds.includes(plan.id)) {
      return plan;
    }
  }
  return null;
}

/**
 * Get the commit SHA of the plan immediately before the given plan.
 * Returns null if no prior committed plan exists.
 */
export function getCommitBeforePlan(
  plans: Plan[],
  planId: string
): string | null {
  const index = findPlanIndex(plans, planId);
  if (index <= 0) {
    return null;
  }

  // Walk backwards to find the most recent completed plan before this one
  for (let i = index - 1; i >= 0; i--) {
    if (plans[i].commit) {
      return plans[i].commit;
    }
  }
  return null;
}

/**
 * Reset the given plan and all subsequent plans to pending status.
 */
export function resetPlansFromId(plans: Plan[], planId: string): Plan[] {
  const index = findPlanIndex(plans, planId);
  if (index === -1) return plans;

  return plans.map((p, i) => {
    if (i >= index) {
      return {
        ...p,
        status: "pending" as const,
        commit: null,
        session: null,
      };
    }
    return p;
  });
}
