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

export interface WorkspaceConfig {
  implRepoPath: string;
  workspacePath: string;
  planPath: string;
  notesPath: string;
  sessionsPath: string; // kept for potential future use
  shadowCompassPath: string; // shadow copy of COMPASS.md for diff detection
}
