import { query, type Options } from "@anthropic-ai/claude-code";
import type { WorkspaceConfig } from "../state/types.js";
import { buildCommitSystemPrompt } from "./prompts/commit-system.js";
import {
  createCommitMcpServer,
  type CommitMcpContext,
} from "../mcp/commit-server.js";

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
  taskDescription: string
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

  console.log(`\n[Commit Agent Starting]`);

  try {
    const commitStream = query({
      prompt: initialPrompt,
      options: commitOptions,
    });

    for await (const message of commitStream) {
      if (message.type === "assistant") {
        for (const block of message.message.content) {
          if (block.type === "text") {
            process.stdout.write(block.text);
          } else if (block.type === "tool_use") {
            console.log(`\n[Commit Tool: ${block.name}]`);
          }
        }
      }

      // Check if approved
      if (mcpContext.approved) {
        console.log(`\n[Commit Agent Approved]`);
        return {
          approved: true,
          commitMessage: mcpContext.commitMessage,
        };
      }
    }

    console.log("\n[Commit Agent Complete]");
  } catch (error) {
    console.error("Commit agent error:", error);
    throw error;
  }

  return {
    approved: mcpContext.approved,
    commitMessage: mcpContext.commitMessage,
  };
}
