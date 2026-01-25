import { query, type Options, type SDKMessage } from "@anthropic-ai/claude-code";
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

  const options: Options = {
    customSystemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    model: "sonnet",
    permissionMode: "bypassPermissions",
    mcpServers: {
      compass: compassServer,
    },
  };

  const prompt =
    "Begin your session. Assess the current state and take appropriate action. End the session with end_session when you've completed your work.";

  try {
    const stream = query({ prompt, options });

    for await (const message of stream) {
      handleMessage(message);

      if (mcpContext.sessionEnded) {
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

function handleMessage(message: SDKMessage): void {
  if (message.type === "assistant") {
    const content = message.message.content;
    for (const block of content) {
      if (block.type === "text") {
        process.stdout.write(block.text);
      } else if (block.type === "tool_use") {
        console.log(`\n[Tool: ${block.name}]`);
      }
    }
  } else if (message.type === "result") {
    if (message.subtype === "success") {
      console.log(`\n[Result: ${message.result.slice(0, 100)}...]`);
    }
  }
}
