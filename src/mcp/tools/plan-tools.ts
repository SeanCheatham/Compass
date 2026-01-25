import type { WorkspaceConfig } from "../../state/types.js";
import {
  readPlanFile,
  writePlanFile,
  createPlan,
  insertPlanAfter,
  insertPlansAfter,
  removePlan,
  updatePlanStatus,
} from "../utils/plan-store.js";
import type {
  InsertPlanInput,
  InsertPlansInput,
  RemovePlanInput,
  SetPlanStatusInput,
} from "../schemas/plan.js";

export async function listPlans(config: WorkspaceConfig): Promise<string> {
  const planFile = await readPlanFile(config.planPath);
  const plans = planFile.plans;

  if (plans.length === 0) {
    return "No plans defined. Use insert_plan or insert_plans to create initial plans.";
  }

  const pendingCount = plans.filter((p) => p.status === "pending").length;
  const completedCount = plans.filter((p) => p.status === "completed").length;

  const lines = [
    `Plans: ${plans.length} total (${completedCount} completed, ${pendingCount} pending)`,
    "",
  ];

  for (const plan of plans) {
    const statusIcon = plan.status === "completed" ? "✓" : "○";
    const commitInfo = plan.commit ? ` [${plan.commit.slice(0, 7)}]` : "";
    lines.push(`${statusIcon} ${plan.id}: ${plan.content}${commitInfo}`);
  }

  return lines.join("\n");
}

export async function insertPlan(
  config: WorkspaceConfig,
  input: InsertPlanInput
): Promise<string> {
  const planFile = await readPlanFile(config.planPath);
  const newPlan = createPlan(input.content);

  const updatedPlans = insertPlanAfter(
    planFile.plans,
    input.after_id,
    newPlan
  );

  await writePlanFile(config.planPath, { plans: updatedPlans });

  const position =
    input.after_id === null
      ? "at the start"
      : `after plan ${input.after_id}`;

  return `Inserted plan ${newPlan.id}: "${input.content}" ${position}`;
}

export async function insertPlans(
  config: WorkspaceConfig,
  input: InsertPlansInput
): Promise<string> {
  const planFile = await readPlanFile(config.planPath);
  const newPlans = input.contents.map(createPlan);

  const updatedPlans = insertPlansAfter(
    planFile.plans,
    input.after_id,
    newPlans
  );

  await writePlanFile(config.planPath, { plans: updatedPlans });

  const position =
    input.after_id === null
      ? "at the start"
      : `after plan ${input.after_id}`;

  const planIds = newPlans.map((p) => p.id).join(", ");
  return `Inserted ${newPlans.length} plans (${planIds}) ${position}`;
}

export async function removePlanById(
  config: WorkspaceConfig,
  input: RemovePlanInput
): Promise<string> {
  const planFile = await readPlanFile(config.planPath);
  const updatedPlans = removePlan(planFile.plans, input.id);

  await writePlanFile(config.planPath, { plans: updatedPlans });

  return `Removed plan ${input.id}`;
}

export async function setPlanStatus(
  config: WorkspaceConfig,
  input: SetPlanStatusInput
): Promise<string> {
  const planFile = await readPlanFile(config.planPath);
  const updatedPlans = updatePlanStatus(planFile.plans, input.id, input.status);

  await writePlanFile(config.planPath, { plans: updatedPlans });

  return `Updated plan ${input.id} status to ${input.status}`;
}
