import { z } from "zod";
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-code";

export interface DevMcpContext {
  reverted: boolean;
  revertReason?: string;
}

/**
 * Creates the MCP server for the Dev agent.
 * Dev only has a signal_revert tool to abort implementation.
 */
export function createDevMcpServer(context: DevMcpContext) {
  const signalRevertTool = tool(
    "signal_revert",
    `Signal that implementation cannot be completed within scope.

Use this when:
- The task requires changes outside the planned scope
- You've discovered the approach won't work
- There's a blocking issue that needs PM attention

This will abort the current implementation and discard all changes.
The PM agent will receive your reason and can adjust plans.`,
    {
      reason: z
        .string()
        .describe("Why you cannot complete the task within scope"),
    },
    async (input) => {
      context.reverted = true;
      context.revertReason = input.reason;
      return {
        content: [
          {
            type: "text" as const,
            text: `Revert signaled: ${input.reason}. Implementation will be aborted.`,
          },
        ],
      };
    }
  );

  return createSdkMcpServer({
    name: "compass",
    version: "0.1.0",
    tools: [signalRevertTool],
  });
}
