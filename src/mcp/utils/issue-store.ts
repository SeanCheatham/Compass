import { readFile, writeFile } from "fs/promises";
import {
  IssueFileSchema,
  type Issue,
  type IssueFile,
} from "../../state/types.js";
import { generatePlanId } from "../../utils/hash.js";

export async function readIssueFile(issuesPath: string): Promise<IssueFile> {
  try {
    const content = await readFile(issuesPath, "utf-8");
    const data = JSON.parse(content);
    return IssueFileSchema.parse(data);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { issues: [] };
    }
    throw error;
  }
}

export async function writeIssueFile(
  issuesPath: string,
  issueFile: IssueFile
): Promise<void> {
  const validated = IssueFileSchema.parse(issueFile);
  await writeFile(issuesPath, JSON.stringify(validated, null, 2));
}

export function createIssue(
  type: "bug" | "enhancement",
  title: string,
  description: string | null = null,
  priority: "low" | "normal" | "high" = "normal"
): Issue {
  return {
    id: generatePlanId(`${type}-${title}-${Date.now()}`),
    type,
    title,
    description,
    status: "open",
    priority,
    createdAt: new Date().toISOString(),
    closedAt: null,
    planId: null,
    commit: null,
  };
}

export function getNextOpenIssue(issues: Issue[]): Issue | undefined {
  const priorityOrder = { high: 0, normal: 1, low: 2 };

  return issues
    .filter((i) => i.status === "open")
    .sort((a, b) => {
      // First by priority (high > normal > low)
      const priorityDiff =
        priorityOrder[a.priority] - priorityOrder[b.priority];
      if (priorityDiff !== 0) return priorityDiff;
      // Then by creation date (oldest first)
      return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
    })[0];
}

export function updateIssueStatus(
  issues: Issue[],
  id: string,
  status: "open" | "in_progress" | "closed",
  planId?: string,
  commit?: string
): Issue[] {
  return issues.map((i) => {
    if (i.id !== id) return i;
    return {
      ...i,
      status,
      planId: planId ?? i.planId,
      commit: commit ?? i.commit,
      closedAt: status === "closed" ? new Date().toISOString() : i.closedAt,
    };
  });
}

export function findIssueByPlanId(
  issues: Issue[],
  planId: string
): Issue | undefined {
  return issues.find((i) => i.planId === planId);
}

export function findIssueById(issues: Issue[], id: string): Issue | undefined {
  return issues.find((i) => i.id === id);
}
