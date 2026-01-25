import { z } from "zod";

export const PlanSchema = z.object({
  id: z.string(),
  content: z.string(),
  status: z.enum(["pending", "completed"]),
  commit: z.string().nullable(),
  session: z.string().nullable(),
});

export const PlanFileSchema = z.object({
  plans: z.array(PlanSchema),
});

export type Plan = z.infer<typeof PlanSchema>;
export type PlanFile = z.infer<typeof PlanFileSchema>;

export type EndSessionOutcome =
  | { outcome: "commit"; summary: string }
  | { outcome: "replanned"; summary: string }
  | { outcome: "revert"; revert_to: string; reason: string };

export interface WorkspaceConfig {
  implRepoPath: string;
  workspacePath: string;
  planPath: string;
  notesPath: string;
  sessionsPath: string;
}

export interface SessionContext {
  compass: string;
  plans: PlanFile;
  notes: string;
  sessions: SessionSummary[];
  revertReason?: string;
}

export interface SessionSummary {
  planId: string;
  content: string;
  outcome: "commit" | "replanned" | "revert";
  commitSha: string | null;
  summary: string;
  timestamp: number;
}
