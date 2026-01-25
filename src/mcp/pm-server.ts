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

export interface CompassInvalidation {
  invalidatedCompletedPlanIds: string[];
  invalidatedPendingPlanIds: string[];
  reasoning: string;
}

export interface PmMcpContext {
  compassInvalidation?: CompassInvalidation;
}

/**
 * Creates the MCP server for the PM agent.
 * PM has plan management tools only - no session control.
 */
export function createPmMcpServer(
  config: WorkspaceConfig,
  context?: PmMcpContext
) {
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

  const signalCompassInvalidationTool = tool(
    "signal_compass_invalidation",
    `Signal which plans are invalidated by COMPASS.md changes.

Use this tool after reviewing COMPASS changes to indicate:
- Which completed plans need to be re-done (will trigger code revert)
- Which pending plans need updating

If no completed plans are invalidated, the system will proceed without reverting.
Call this tool ONCE after your analysis, before adjusting plans.`,
    {
      invalidated_completed_plan_ids: z
        .array(z.string())
        .describe(
          "IDs of completed plans that are now invalid and need re-implementation"
        ),
      invalidated_pending_plan_ids: z
        .array(z.string())
        .describe("IDs of pending plans that need to be updated"),
      reasoning: z
        .string()
        .describe("Your analysis of how COMPASS changes affect existing plans"),
    },
    async (input) => {
      if (context) {
        context.compassInvalidation = {
          invalidatedCompletedPlanIds: input.invalidated_completed_plan_ids,
          invalidatedPendingPlanIds: input.invalidated_pending_plan_ids,
          reasoning: input.reasoning,
        };
      }
      return {
        content: [
          {
            type: "text" as const,
            text: `Invalidation signaled. Completed: ${input.invalidated_completed_plan_ids.length}, Pending: ${input.invalidated_pending_plan_ids.length}`,
          },
        ],
      };
    }
  );

  const baseTools = [
    listPlansTool,
    insertPlanTool,
    insertPlansTool,
    removePlanTool,
    setPlanStatusTool,
    writeNotesTool,
  ];

  // Only include the invalidation tool when a context is provided (compass change mode)
  const tools = context
    ? [...baseTools, signalCompassInvalidationTool]
    : baseTools;

  return createSdkMcpServer({
    name: "compass",
    version: "0.1.0",
    tools,
  });
}
