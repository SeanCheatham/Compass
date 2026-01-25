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
import { endSession, type EndSessionResult } from "./tools/session-tools.js";

export interface McpServerContext {
  config: WorkspaceConfig;
  sessionEnded: boolean;
  sessionResult?: EndSessionResult;
}

export function createCompassMcpServer(context: McpServerContext) {
  const listPlansTool = tool(
    "list_plans",
    "View current plans with IDs, status, and completion counts. Use this to understand the current state of the project plan.",
    {},
    async () => {
      const result = await listPlans(context.config);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const insertPlanTool = tool(
    "insert_plan",
    "Add a single plan after a given ID (use null for after_id to insert at the start). Returns the new plan's ID.",
    {
      after_id: z
        .string()
        .nullable()
        .describe(
          "ID of the plan to insert after, or null to insert at the start"
        ),
      content: z.string().describe("The plan content/description"),
    },
    async (input) => {
      const result = await insertPlan(context.config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const insertPlansTool = tool(
    "insert_plans",
    "Batch insert multiple plans after a given ID. Useful for task decomposition. Returns the new plan IDs.",
    {
      after_id: z
        .string()
        .nullable()
        .describe(
          "ID of the plan to insert after, or null to insert at the start"
        ),
      contents: z.array(z.string()).describe("Array of plan contents to insert"),
    },
    async (input) => {
      const result = await insertPlans(context.config, input);
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
      const result = await removePlanById(context.config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const setPlanStatusTool = tool(
    "set_plan_status",
    "Update a plan's status to pending or completed. Typically used internally.",
    {
      id: z.string().describe("ID of the plan to update"),
      status: z.enum(["pending", "completed"]).describe("New status for the plan"),
    },
    async (input) => {
      const result = await setPlanStatus(context.config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const writeNotesTool = tool(
    "write_notes",
    "Update notes.md with new content. Use for cross-session learnings and context that should persist.",
    {
      content: z.string().describe("Full content to write to notes.md"),
    },
    async (input) => {
      const result = await writeNotes(context.config, input);
      return { content: [{ type: "text" as const, text: result }] };
    }
  );

  const endSessionTool = tool(
    "end_session",
    `End the current session with one of three outcomes:
- commit: Stage and commit all changes, mark current plan as completed
- replanned: Discard implementation changes but keep plan modifications
- revert: Reset to a previous commit/plan, reset subsequent plans to pending

For commit/replanned, provide a summary. For revert, provide the target and reason.`,
    {
      outcome: z
        .enum(["commit", "replanned", "revert"])
        .describe("The session outcome type"),
      summary: z
        .string()
        .optional()
        .describe("Summary of what was accomplished (for commit/replanned)"),
      revert_to: z
        .string()
        .optional()
        .describe("Plan ID or commit SHA to revert to (for revert)"),
      reason: z.string().optional().describe("Reason for reverting (for revert)"),
    },
    async (input) => {
      let endSessionInput;

      if (input.outcome === "commit") {
        endSessionInput = {
          outcome: "commit" as const,
          summary: input.summary ?? "",
        };
      } else if (input.outcome === "replanned") {
        endSessionInput = {
          outcome: "replanned" as const,
          summary: input.summary ?? "",
        };
      } else {
        endSessionInput = {
          outcome: "revert" as const,
          revert_to: input.revert_to ?? "",
          reason: input.reason ?? "",
        };
      }

      const result = await endSession(context.config, endSessionInput);
      context.sessionEnded = true;
      context.sessionResult = result;
      return { content: [{ type: "text" as const, text: result.message }] };
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
      endSessionTool,
    ],
  });
}
