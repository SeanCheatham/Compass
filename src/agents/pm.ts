import { query, type Options } from "@anthropic-ai/claude-code";
import type { WorkspaceConfig } from "../state/types.js";
import { readPlanFile } from "../mcp/utils/plan-store.js";
import { readFile } from "fs/promises";
import { buildPmSystemPrompt } from "./prompts/pm-system.js";
import { createPmMcpServer } from "../mcp/pm-server.js";

export interface PmAgentResult {
  hasPendingPlans: boolean;
}

/**
 * Runs the PM agent with READ-only access to the repository.
 *
 * The PM agent:
 * - Analyzes the current codebase state (read-only)
 * - Reviews and adjusts plans via MCP tools
 * - Completes naturally when satisfied
 *
 * It does NOT implement anything - that's the Dev agent's job.
 */
export async function runPmAgent(
  config: WorkspaceConfig,
  compassContent: string,
  revertReason?: string
): Promise<PmAgentResult> {
  const planFile = await readPlanFile(config.planPath);

  let notes = "";
  try {
    notes = await readFile(config.notesPath, "utf-8");
  } catch {
    notes = "";
  }

  const systemPrompt = buildPmSystemPrompt({
    compass: compassContent,
    plans: planFile,
    notes,
    revertReason,
  });

  const mcpServer = createPmMcpServer(config);

  const hasPlans = planFile.plans.length > 0;
  const hasPendingPlans = planFile.plans.some((p) => p.status === "pending");

  let initialPrompt: string;
  if (!hasPlans) {
    initialPrompt = `Begin your analysis. There are no plans yet.

Your task:
1. Read and understand COMPASS.md (provided in system prompt)
2. Explore the codebase to understand its current state
3. Create initial plans using insert_plans
4. Complete when you've established a solid plan`;
  } else if (!hasPendingPlans) {
    initialPrompt = `All plans are complete.

Review the codebase and COMPASS.md to determine if:
- The project is truly done, or
- Additional plans are needed

If done, simply confirm completion. If more work is needed, add plans.`;
  } else {
    initialPrompt = `Review the current state. There are ${planFile.plans.filter((p) => p.status === "pending").length} pending plans.

Your task:
1. Analyze the codebase to verify the current plan is still appropriate
2. Adjust plans if needed (insert, remove, reorder)
3. Complete when you're satisfied the first pending plan is ready for implementation

The Dev agent will handle implementation after you complete.`;
  }

  const pmOptions: Options = {
    customSystemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    model: "sonnet",
    permissionMode: "bypassPermissions",
    mcpServers: {
      compass: mcpServer,
    },
    // PM has READ-only access to code + plan MCP tools
    allowedTools: [
      "Read",
      "Glob",
      "Grep",
      "LS",
      "mcp__compass__list_plans",
      "mcp__compass__insert_plan",
      "mcp__compass__insert_plans",
      "mcp__compass__remove_plan",
      "mcp__compass__set_plan_status",
      "mcp__compass__write_notes",
    ],
  };

  console.log("\n[PM Agent Starting]");

  try {
    const pmStream = query({ prompt: initialPrompt, options: pmOptions });

    for await (const message of pmStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            process.stdout.write(block.text);
          } else if (block.type === "tool_use") {
            console.log(`\n[PM Tool: ${block.name}]`);
          }
        }
      }
    }

    console.log("\n[PM Agent Complete]");
  } catch (error) {
    console.error("PM agent error:", error);
    throw error;
  }

  // Re-read plan file to get updated state
  const updatedPlanFile = await readPlanFile(config.planPath);
  const updatedHasPending = updatedPlanFile.plans.some(
    (p) => p.status === "pending"
  );

  return {
    hasPendingPlans: updatedHasPending,
  };
}
