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
  session: string
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
