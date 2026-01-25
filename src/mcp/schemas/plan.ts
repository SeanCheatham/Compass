import { z } from "zod";

export const ListPlansInputSchema = z.object({});

export const InsertPlanInputSchema = z.object({
  after_id: z
    .string()
    .nullable()
    .describe("ID of the plan to insert after, or null to insert at the start"),
  content: z.string().describe("The plan content/description"),
});

export const InsertPlansInputSchema = z.object({
  after_id: z
    .string()
    .nullable()
    .describe(
      "ID of the plan to insert after, or null to insert at the start"
    ),
  contents: z.array(z.string()).describe("Array of plan contents to insert"),
});

export const RemovePlanInputSchema = z.object({
  id: z.string().describe("ID of the plan to remove"),
});

export const SetPlanStatusInputSchema = z.object({
  id: z.string().describe("ID of the plan to update"),
  status: z
    .enum(["pending", "completed"])
    .describe("New status for the plan"),
});

export const WriteNotesInputSchema = z.object({
  content: z.string().describe("Full content to write to notes.md"),
});

export type ListPlansInput = z.infer<typeof ListPlansInputSchema>;
export type InsertPlanInput = z.infer<typeof InsertPlanInputSchema>;
export type InsertPlansInput = z.infer<typeof InsertPlansInputSchema>;
export type RemovePlanInput = z.infer<typeof RemovePlanInputSchema>;
export type SetPlanStatusInput = z.infer<typeof SetPlanStatusInputSchema>;
export type WriteNotesInput = z.infer<typeof WriteNotesInputSchema>;
