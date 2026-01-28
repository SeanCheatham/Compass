import { z } from "zod";

export const PlanSchema = z.object({
  id: z.string(),
  content: z.string(),
  status: z.enum(["pending", "completed"]),
  commit: z.string().nullable(),
  session: z.string().nullable(), // kept for backward compatibility
});

export const PlanFileSchema = z.object({
  plans: z.array(PlanSchema),
});

export type Plan = z.infer<typeof PlanSchema>;
export type PlanFile = z.infer<typeof PlanFileSchema>;

export const IssueSchema = z.object({
  id: z.string(),
  type: z.enum(["bug", "enhancement"]),
  title: z.string(),
  description: z.string().nullable(),
  status: z.enum(["open", "in_progress", "closed"]),
  priority: z.enum(["low", "normal", "high"]),
  createdAt: z.string(),
  closedAt: z.string().nullable(),
  planId: z.string().nullable(),
  commit: z.string().nullable(),
});

export const IssueFileSchema = z.object({
  issues: z.array(IssueSchema),
});

export type Issue = z.infer<typeof IssueSchema>;
export type IssueFile = z.infer<typeof IssueFileSchema>;

export interface WorkspaceConfig {
  implRepoPath: string;
  workspacePath: string;
  planPath: string;
  notesPath: string;
  sessionsPath: string; // kept for potential future use
  shadowCompassPath: string; // shadow copy of COMPASS.md for diff detection
  issuesPath: string;
}
