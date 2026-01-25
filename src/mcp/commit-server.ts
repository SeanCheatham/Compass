import { z } from "zod";
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-code";
import { exec } from "child_process";
import { promisify } from "util";
import { readFile, writeFile } from "fs/promises";
import { join } from "path";

const execAsync = promisify(exec);

export interface CommitMcpContext {
  cwd: string;
  approved: boolean;
  commitMessage?: string;
}

/**
 * Creates the MCP server for the Commit agent.
 * Provides tools to review and clean up changes before committing.
 */
export function createCommitMcpServer(context: CommitMcpContext) {
  const getDiffTool = tool(
    "get_diff",
    `View the current git diff showing all staged and unstaged changes.
Use this to review what will be committed.`,
    {},
    async () => {
      try {
        // Get both staged and unstaged changes
        const { stdout: stagedDiff } = await execAsync("git diff --cached", {
          cwd: context.cwd,
        });
        const { stdout: unstagedDiff } = await execAsync("git diff", {
          cwd: context.cwd,
        });

        let output = "";

        if (stagedDiff.trim()) {
          output += "=== STAGED CHANGES ===\n" + stagedDiff + "\n";
        }

        if (unstagedDiff.trim()) {
          output += "=== UNSTAGED CHANGES ===\n" + unstagedDiff + "\n";
        }

        if (!output) {
          output = "No changes detected.";
        }

        return {
          content: [{ type: "text" as const, text: output }],
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Error getting diff: ${error}`,
            },
          ],
        };
      }
    }
  );

  const getStatusTool = tool(
    "get_status",
    `View the current git status showing all modified, added, and untracked files.
Use this to see which files have changes.`,
    {},
    async () => {
      try {
        const { stdout } = await execAsync("git status", {
          cwd: context.cwd,
        });

        return {
          content: [{ type: "text" as const, text: stdout }],
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Error getting status: ${error}`,
            },
          ],
        };
      }
    }
  );

  const updateGitignoreTool = tool(
    "update_gitignore",
    `Add patterns to the .gitignore file.
Use this when you find files that should not be committed.`,
    {
      patterns: z
        .array(z.string())
        .describe("List of patterns to add to .gitignore (e.g., ['*.log', 'node_modules/', '.env'])"),
    },
    async (input) => {
      try {
        const gitignorePath = join(context.cwd, ".gitignore");

        // Read existing .gitignore or start empty
        let existingContent = "";
        try {
          existingContent = await readFile(gitignorePath, "utf-8");
        } catch {
          // File doesn't exist, start fresh
        }

        const existingLines = new Set(
          existingContent.split("\n").map((line) => line.trim())
        );

        // Filter out patterns that already exist
        const newPatterns = input.patterns.filter(
          (pattern) => !existingLines.has(pattern.trim())
        );

        if (newPatterns.length === 0) {
          return {
            content: [
              {
                type: "text" as const,
                text: "All patterns already exist in .gitignore",
              },
            ],
          };
        }

        // Append new patterns
        const newContent = existingContent.trim()
          ? existingContent.trim() + "\n" + newPatterns.join("\n") + "\n"
          : newPatterns.join("\n") + "\n";

        await writeFile(gitignorePath, newContent);

        // Remove now-ignored files from git tracking
        for (const pattern of newPatterns) {
          try {
            await execAsync(`git rm -r --cached --ignore-unmatch "${pattern}"`, {
              cwd: context.cwd,
            });
          } catch {
            // Ignore errors - pattern might not match any tracked files
          }
        }

        return {
          content: [
            {
              type: "text" as const,
              text: `Added to .gitignore:\n${newPatterns.map((p) => `  - ${p}`).join("\n")}`,
            },
          ],
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Error updating .gitignore: ${error}`,
            },
          ],
        };
      }
    }
  );

  const approveCommitTool = tool(
    "approve_commit",
    `Approve the changes for commit with a descriptive message.
Call this once you've reviewed the diff and made any necessary .gitignore updates.
The changes will be staged and committed after approval.`,
    {
      message: z
        .string()
        .describe(
          "A concise commit message describing what was changed (will be combined with the task description)"
        ),
    },
    async (input) => {
      context.approved = true;
      context.commitMessage = input.message;
      return {
        content: [
          {
            type: "text" as const,
            text: `Changes approved for commit with message: ${input.message}`,
          },
        ],
      };
    }
  );

  return createSdkMcpServer({
    name: "compass",
    version: "0.1.0",
    tools: [getDiffTool, getStatusTool, updateGitignoreTool, approveCommitTool],
  });
}
