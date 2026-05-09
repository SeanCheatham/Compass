import { z } from "zod";
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";

export interface PlanMcpContext {
  done: boolean;
  doneReason?: string;
}

/**
 * MCP server for the Plan agent. Exposes a single tool, `signal_done`,
 * that lets the planner declare the project complete.
 */
export function createPlanMcpServer(context: PlanMcpContext) {
  const signalDoneTool = tool(
    "signal_done",
    `Signal that no further work is needed and the project is complete.

Call this only when:
- state.json's "next" is null
- drafts.md is empty (no pending user input)
- the codebase satisfies the work captured in "completed"

The loop drops into idle. If the user adds new drafts later, the loop resumes.`,
    {
      reason: z
        .string()
        .describe("One sentence explaining why the project is done."),
    },
    async (input) => {
      context.done = true;
      context.doneReason = input.reason;
      return {
        content: [
          {
            type: "text" as const,
            text: `Done signaled: ${input.reason}`,
          },
        ],
      };
    }
  );

  return createSdkMcpServer({
    name: "compass",
    version: "0.1.0",
    tools: [signalDoneTool],
  });
}
