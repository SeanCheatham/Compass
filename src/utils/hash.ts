import { createHash } from "crypto";

export function generatePlanId(content: string): string {
  const hash = createHash("sha256").update(content).digest("hex");
  return hash.slice(0, 6);
}
