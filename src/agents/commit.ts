import { query, type Options } from "@anthropic-ai/claude-agent-sdk";
import type { WorkspaceConfig } from "../state/types.js";
import { buildCommitSystemPrompt } from "./prompts/commit-system.js";
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

  const initialPrompt = `Review and commit the changes for the following task:

${taskDescription}

Start by viewing the git status and diff, then:
1. Check for files that shouldn't be committed (secrets, build artifacts, etc.)
2. Update .gitignore if needed
3. Stage the appropriate files with git add
4. Commit with a clear message describing what was done

The working tree should be clean when you're done.`;

  const commitOptions: Options = {
    systemPrompt: systemPrompt,
    cwd: config.implRepoPath,
    permissionMode: "bypassPermissions",
    allowedTools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "LS", "LSP", "Agent", "Skill", "WebFetch", "WebSearch"],
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

    }

    output.agentComplete("Commit");
    return { approved: true };
  } catch (error) {
    output.error(`Commit agent error: ${error}`);
    throw error;
  }
}
