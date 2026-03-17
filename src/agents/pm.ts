import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig } from "../state/types.js";
import { readPlanFile } from "../mcp/utils/plan-store.js";
import { readFile } from "fs/promises";
import {
  buildPmSystemPrompt,
  type CompassChangeMode,
} from "./prompts/pm-system.js";
import {
  createPmMcpServer,
  type PmMcpContext,
  type CompassInvalidation,
} from "../mcp/pm-server.js";
import type { OutputManager } from "../web/output-manager.js";

export interface PmAgentResult {
  hasPendingPlans: boolean;
  compassInvalidation?: CompassInvalidation;
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
  output: OutputManager,
  revertReason?: string,
  compassChangeMode?: CompassChangeMode
): Promise<PmAgentResult> {
  const planFile = await readPlanFile(config.planPath);

  let notes = "";
  try {
    notes = await readFile(config.notesPath, "utf-8");
  } catch {
    notes = "";
  }

  // Create context to capture invalidation results (only in compass change mode)
  const pmContext: PmMcpContext | undefined = compassChangeMode
    ? {}
    : undefined;

  const systemPrompt = buildPmSystemPrompt({
    compass: compassContent,
    plans: planFile,
    notes,
    revertReason,
    compassChangeMode,
  });

  const mcpServer = createPmMcpServer(config, pmContext);

  const hasPlans = planFile.plans.length > 0;
  const hasPendingPlans = planFile.plans.some((p) => p.status === "pending");

  let initialPrompt: string;
  if (compassChangeMode) {
    // Special prompt for COMPASS change mode
    initialPrompt = `COMPASS.md has been modified since your last session.

Your task:
1. Review the changes between previous and current COMPASS.md (shown in system prompt)
2. Review all existing plans (completed and pending)
3. Determine which plans (if any) are invalidated by the changes
4. FIRST: Use signal_compass_invalidation to report your findings
5. THEN: Adjust plans as needed (add, remove, modify)

Begin by analyzing the COMPASS changes and their impact on existing plans.`;
  } else if (!hasPlans) {
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

  // PM has READ-only access to code + plan MCP tools
  const allowedTools = [
    "Read",
    "Glob",
    "Grep",
    "LS",
    "LSP",
    "Agent",
    "Skill",
    "WebFetch",
    "WebSearch",
    "NotebookRead",
    "mcp__compass__list_plans",
    "mcp__compass__insert_plan",
    "mcp__compass__insert_plans",
    "mcp__compass__remove_plan",
    "mcp__compass__set_plan_status",
    "mcp__compass__write_notes",
  ];

  // Add invalidation tool when in compass change mode
  if (compassChangeMode) {
    allowedTools.push("mcp__compass__signal_compass_invalidation");
  }

  const pmOptions: Options = {
    systemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    mcpServers: {
      compass: mcpServer,
    },
    allowedTools,
  };

  output.agentStart("PM");

  try {
    const pmStream = query({ prompt: initialPrompt, options: pmOptions });

    for await (const message of pmStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool("PM", block.name);
          }
        }
      }
    }

    output.agentComplete("PM");
  } catch (error) {
    output.error(`PM agent error: ${error}`);
    throw error;
  }

  // Re-read plan file to get updated state
  const updatedPlanFile = await readPlanFile(config.planPath);
  const updatedHasPending = updatedPlanFile.plans.some(
    (p) => p.status === "pending"
  );

  return {
    hasPendingPlans: updatedHasPending,
    compassInvalidation: pmContext?.compassInvalidation,
  };
}
