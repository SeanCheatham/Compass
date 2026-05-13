export type CompassAgentRuntime = "claude" | "codex";

export function parseAgentRuntime(
  value: string | undefined
): CompassAgentRuntime {
  const normalized = (value ?? "claude").trim().toLowerCase();
  if (normalized === "claude" || normalized === "codex") return normalized;
  throw new Error(
    `Unknown agent runtime "${value}". Expected "claude" or "codex".`
  );
}

export function agentRuntimeLabel(runtime: CompassAgentRuntime): string {
  switch (runtime) {
    case "claude":
      return "Claude";
    case "codex":
      return "Codex";
  }
}
