import {
  query,
  type Options,
  type SDKUserMessage,
} from "@anthropic-ai/claude-code";
import type { WorkspaceConfig, SessionSummary } from "../state/types.js";
import { readPlanFile } from "../mcp/utils/plan-store.js";
import { readFile, readdir } from "fs/promises";
import { resolve } from "path";
import { buildPmSystemPrompt } from "./prompts/pm-system.js";
import { createCompassMcpServer, type McpServerContext } from "../mcp/index.js";

async function loadSessionSummaries(
  sessionsPath: string
): Promise<SessionSummary[]> {
  try {
    const files = await readdir(sessionsPath);
    const sessions: SessionSummary[] = [];

    for (const file of files.sort()) {
      if (!file.endsWith(".md")) continue;

      const content = await readFile(resolve(sessionsPath, file), "utf-8");
      const planIdMatch = file.match(/^([a-f0-9]+)-/);
      const planId = planIdMatch?.[1] ?? "unknown";

      const outcomeMatch = content.match(/\*\*Outcome\*\*:\s*(\w+)/);
      const outcome = (outcomeMatch?.[1] ?? "unknown") as
        | "commit"
        | "replanned"
        | "revert";

      const commitMatch = content.match(/\*\*Commit\*\*:\s*(\S+)/);
      const commitSha =
        commitMatch?.[1] === "N/A" ? null : commitMatch?.[1] ?? null;

      const summaryMatch = content.match(/## Summary\n\n([\s\S]+)$/);
      const summary = summaryMatch?.[1]?.trim() ?? "";

      const timestampMatch = file.match(/-(\d+)\.md$/);
      const timestamp = timestampMatch ? parseInt(timestampMatch[1], 10) : 0;

      const planMatch = content.match(/\*\*Plan\*\*:\s*(.+)/);
      const planContent = planMatch?.[1] ?? "";

      sessions.push({
        planId,
        content: planContent,
        outcome,
        commitSha,
        summary,
        timestamp,
      });
    }

    return sessions;
  } catch {
    return [];
  }
}

export interface PmSessionResult {
  done: boolean;
  revertReason?: string;
}

/**
 * Runs a PM session with bidirectional communication to a Dev agent.
 *
 * Architecture:
 * - PM only uses MCP tools (plan management, end_session)
 * - PM sends text messages to Dev for codebase interaction
 * - Dev has full code tools (Read, Write, Edit, Bash, Glob, Grep)
 * - Dev's responses become PM's next input message
 *
 * Flow:
 * 1. PM receives initial prompt
 * 2. PM outputs text (instructions to Dev) or MCP tool calls
 * 3. Text outputs are forwarded to Dev as instructions
 * 4. Dev executes and responds
 * 5. Dev's response becomes PM's next input
 * 6. Repeat until PM calls end_session
 */
export async function runPmSession(
  config: WorkspaceConfig,
  compassContent: string,
  revertReason?: string
): Promise<PmSessionResult> {
  const plans = await readPlanFile(config.planPath);

  let notes = "";
  try {
    notes = await readFile(config.notesPath, "utf-8");
  } catch {
    notes = "";
  }

  const sessions = await loadSessionSummaries(config.sessionsPath);

  const systemPrompt = buildPmSystemPrompt({
    compass: compassContent,
    plans,
    notes,
    sessions,
    revertReason,
  });

  const mcpContext: McpServerContext = {
    config,
    sessionEnded: false,
  };

  const compassServer = createCompassMcpServer(mcpContext);

  // Message queue for PM input - Dev responses get pushed here
  const pmInputQueue: SDKUserMessage[] = [];
  let pmInputResolver: ((value: SDKUserMessage | null) => void) | null = null;
  let pmInputClosed = false;

  function pushToPmInput(msg: SDKUserMessage) {
    if (pmInputResolver) {
      const resolve = pmInputResolver;
      pmInputResolver = null;
      resolve(msg);
    } else {
      pmInputQueue.push(msg);
    }
  }

  function closePmInput() {
    pmInputClosed = true;
    if (pmInputResolver) {
      pmInputResolver(null);
    }
  }

  async function pullFromPmInput(): Promise<SDKUserMessage | null> {
    if (pmInputQueue.length > 0) {
      return pmInputQueue.shift()!;
    }
    if (pmInputClosed) {
      return null;
    }
    return new Promise((resolve) => {
      pmInputResolver = resolve;
    });
  }

  // Async generator for PM input
  async function* createPmInput(): AsyncIterable<SDKUserMessage> {
    // First message is the initial prompt
    yield {
      type: "user",
      message: {
        role: "user" as const,
        content:
          "Begin your session. Assess the current state and take appropriate action. End the session with end_session when you've completed your work.",
      },
      parent_tool_use_id: null,
      session_id: "pm-session",
    };

    // Subsequent messages come from Dev's responses
    while (true) {
      const msg = await pullFromPmInput();
      if (!msg) break;
      yield msg;
    }
  }

  const pmOptions: Options = {
    customSystemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    model: "sonnet",
    permissionMode: "bypassPermissions",
    mcpServers: {
      compass: compassServer,
    },
    // PM only has MCP tools - no direct code access
    allowedTools: [
      "mcp__compass__list_plans",
      "mcp__compass__insert_plan",
      "mcp__compass__insert_plans",
      "mcp__compass__remove_plan",
      "mcp__compass__set_plan_status",
      "mcp__compass__write_notes",
      "mcp__compass__end_session",
    ],
  };

  const pmInput = createPmInput();

  try {
    const pmStream = query({ prompt: pmInput, options: pmOptions });

    for await (const message of pmStream) {
      // Collect text output from PM - this will be sent to Dev
      if (message.type === "assistant") {
        const textParts: string[] = [];

        for (const block of message.message.content) {
          if (block.type === "text") {
            process.stdout.write(block.text);
            textParts.push(block.text);
          } else if (block.type === "tool_use") {
            console.log(`\n[PM Tool: ${block.name}]`);
          }
        }

        // If PM produced text output, send it to Dev as instructions
        const pmText = textParts.join("").trim();
        if (pmText && !mcpContext.sessionEnded) {
          // Run Dev with PM's text as instructions
          const devResponse = await runDevSession(config.implRepoPath, pmText);

          // Push Dev's response as PM's next input
          console.log(`\n[Dev Response]`);
          process.stdout.write(devResponse);

          pushToPmInput({
            type: "user",
            message: {
              role: "user" as const,
              content: `Developer response:\n\n${devResponse}`,
            },
            parent_tool_use_id: null,
            session_id: "pm-session",
          });
        }
      } else if (message.type === "result") {
        if (message.subtype === "success") {
          console.log(`\n[Result: ${message.result.slice(0, 100)}...]`);
        }
      }

      if (mcpContext.sessionEnded) {
        closePmInput();
        break;
      }
    }
  } catch (error) {
    console.error("PM session error:", error);
    throw error;
  }

  return {
    done: mcpContext.sessionResult?.done ?? false,
    revertReason: mcpContext.sessionResult?.revertReason,
  };
}

/**
 * Runs the Dev agent with instructions from PM.
 * Dev has full code tools and executes PM's requests.
 */
async function runDevSession(cwd: string, instructions: string): Promise<string> {
  const devOptions: Options = {
    customSystemPrompt: `You are a Developer agent working under the direction of a Product Manager (PM).

You have full access to the codebase via code tools:
- Read - Read file contents
- Write - Write new files
- Edit - Edit existing files
- Bash - Run shell commands
- Glob - Find files by pattern
- Grep - Search file contents

Execute the PM's instructions carefully and report back with:
- What you found or did
- Any issues encountered
- Relevant details the PM needs to know

Be concise but thorough. The PM will use your response to make decisions.`,
    cwd,
    model: "sonnet",
    permissionMode: "bypassPermissions",
    allowedTools: [
      "Read",
      "Write",
      "Edit",
      "Bash",
      "Glob",
      "Grep",
      "LS",
    ],
  };

  const outputParts: string[] = [];

  try {
    const devStream = query({ prompt: instructions, options: devOptions });

    for await (const message of devStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            outputParts.push(block.text);
          } else if (block.type === "tool_use") {
            console.log(`\n[Dev Tool: ${block.name}]`);
          }
        }
      }
    }

    return outputParts.join("") || "Task completed.";
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return `Error: ${errorMessage}`;
  }
}
