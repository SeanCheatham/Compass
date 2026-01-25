import { writeFile } from "fs/promises";
import type { WorkspaceConfig } from "../../state/types.js";
import type { WriteNotesInput } from "../schemas/plan.js";

export async function writeNotes(
  config: WorkspaceConfig,
  input: WriteNotesInput
): Promise<string> {
  await writeFile(config.notesPath, input.content, "utf-8");
  return "Notes updated successfully";
}
