import { z } from "zod";
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-code";
import type { WorkspaceConfig } from "../state/types.js";
import {
  listPlans,
  insertPlan,
  insertPlans,
  removePlanById,
  setPlanStatus,
} from "./tools/plan-tools.js";
import { writeNotes } from "./tools/state-tools.js";

/**
 * Creates the MCP server for the PM agent.
 * PM has plan management tools only - no session control.
 */
export function createPmMcpServer(config: WorkspaceConfig) {
  const listPlansTool = tool(
    "list_plans",
    "View current plans with IDs, status, and completion counts.",
    {},
    async () => {
      const result = await listPlans(config);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const insertPlanTool = tool(
    "insert_plan",
    "Add a single plan after a given ID (use null to insert at the start).",
    {
      after_id: z
        .string()
        .nullable()
        .describe("ID of the plan to insert after, or null for start"),
      content: z.string().describe("The plan content/description"),
    },
    async (input) => {
      const result = await insertPlan(config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const insertPlansTool = tool(
    "insert_plans",
    "Batch insert multiple plans after a given ID.",
    {
      after_id: z
        .string()
        .nullable()
        .describe("ID of the plan to insert after, or null for start"),
      contents: z.array(z.string()).describe("Array of plan contents"),
    },
    async (input) => {
      const result = await insertPlans(config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const removePlanTool = tool(
    "remove_plan",
    "Remove a plan by ID. Cannot remove plans that have been committed.",
    {
      id: z.string().describe("ID of the plan to remove"),
    },
    async (input) => {
      const result = await removePlanById(config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const setPlanStatusTool = tool(
    "set_plan_status",
    "Update a plan's status to pending or completed.",
    {
      id: z.string().describe("ID of the plan to update"),
      status: z
        .enum(["pending", "completed"])
        .describe("New status for the plan"),
    },
    async (input) => {
      const result = await setPlanStatus(config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const writeNotesTool = tool(
    "write_notes",
    "Update notes.md with content that should persist across sessions.",
    {
      content: z.string().describe("Full content to write to notes.md"),
    },
    async (input) => {
      const result = await writeNotes(config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  return createSdkMcpServer({
    name: "compass",
    version: "0.1.0",
    tools: [
      listPlansTool,
      insertPlanTool,
      insertPlansTool,
      removePlanTool,
      setPlanStatusTool,
      writeNotesTool,
    ],
  });
}
