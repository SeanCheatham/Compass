export type AgentSdk = "claude" | "codex";

export function parseAgentSdk(value: string | undefined): AgentSdk {
  const normalized = (value ?? "claude").trim().toLowerCase();
  if (normalized === "claude" || normalized === "codex") {
    return normalized;
  }
  throw new Error(
    `Unknown agent SDK "${value}". Expected "claude" or "codex".`
  );
}

export function agentSdkLabel(sdk: AgentSdk): string {
  return sdk === "codex" ? "Codex SDK" : "Claude Agent SDK";
}
