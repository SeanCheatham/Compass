import { query, type Options } from "@anthropic-ai/claude-code";
import type { WorkspaceConfig } from "../state/types.js";
import { buildCommitSystemPrompt } from "./prompts/commit-system.js";
import {
  createCommitMcpServer,
  type CommitMcpContext,
} from "../mcp/commit-server.js";
import type { OutputManager } from "../web/output-manager.js";

export interface CommitAgentResult {
  approved: boolean;
  commitMessage?: string;
}

/**
 * Runs the Commit agent to review changes and prepare for commit.
 *
 * The Commit agent:
 * - Reviews the git diff
 * - Updates .gitignore if needed
 * - Approves changes for commit
 */
export async function runCommitAgent(
  config: WorkspaceConfig,
  taskDescription: string,
  output: OutputManager
): Promise<CommitAgentResult> {
  const systemPrompt = buildCommitSystemPrompt({
    taskDescription,
  });

  const mcpContext: CommitMcpContext = {
    cwd: config.implRepoPath,
    approved: false,
  };

  const mcpServer = createCommitMcpServer(mcpContext);

  const initialPrompt = `Review the changes for the following task and prepare them for commit:

${taskDescription}

Start by viewing the git status and diff, then:
1. Check for files that shouldn't be committed
2. Update .gitignore if needed
3. Approve the commit when ready`;

  const commitOptions: Options = {
    customSystemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    model: "haiku",
    permissionMode: "bypassPermissions",
    mcpServers: {
      compass: mcpServer,
    },
    allowedTools: [
      "mcp__compass__get_diff",
      "mcp__compass__get_status",
      "mcp__compass__update_gitignore",
      "mcp__compass__approve_commit",
    ],
  };

  output.agentStart("Commit");

  try {
    const commitStream = query({
      prompt: initialPrompt,
      options: commitOptions,
    });

    for await (const message of commitStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            output.log(block.text);
          } else if (block.type === "tool_use") {
            output.tool("Commit", block.name);
          }
        }
      }

      // Check if approved
      if (mcpContext.approved) {
        output.agentComplete("Commit", "Approved");
        return {
          approved: true,
          commitMessage: mcpContext.commitMessage,
        };
      }
    }

    output.agentComplete("Commit");
  } catch (error) {
    output.error(`Commit agent error: ${error}`);
    throw error;
  }

  return {
    approved: mcpContext.approved,
    commitMessage: mcpContext.commitMessage,
  };
}
