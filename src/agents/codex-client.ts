import {
  Codex,
  type CodexOptions,
  type ModelReasoningEffort,
} from "@openai/codex-sdk";

export type { ModelReasoningEffort };

export const DEFAULT_CODEMAP_MODEL = "gpt-5.4";
export const CODEMAP_MODEL_ENV = "COMPASS_CODEX_CODEMAP_MODEL";

export function buildCodexOptions(args: {
  mcpUrl?: string;
  toolNames?: string[];
} = {}): CodexOptions {
  const options: CodexOptions = {};
  const codexPathOverride = process.env.COMPASS_CODEX_BIN?.trim();
  if (codexPathOverride) options.codexPathOverride = codexPathOverride;
  if (args.mcpUrl && args.toolNames) {
    options.config = {
      mcp_servers: {
        compass: {
          url: args.mcpUrl,
          enabled_tools: args.toolNames,
          default_tools_approval_mode: "approve",
          tool_timeout_sec: 600,
        },
      },
    };
  }
  return options;
}

export function codexModelFromEnv(
  key: string,
  fallback?: string
): string | undefined {
  const model = process.env[key]?.trim();
  return model ? model : fallback;
}

export async function runCodexReadOnlyTurn(args: {
  prompt: string;
  cwd: string;
  reasoningEffort: ModelReasoningEffort;
  model?: string;
  signal?: AbortSignal;
  outputSchema?: unknown;
}): Promise<string> {
  const codex = new Codex(buildCodexOptions());
  const thread = codex.startThread({
    workingDirectory: args.cwd,
    skipGitRepoCheck: true,
    sandboxMode: "read-only",
    approvalPolicy: "never",
    modelReasoningEffort: args.reasoningEffort,
    networkAccessEnabled: false,
    webSearchEnabled: false,
    webSearchMode: "disabled",
    ...(args.model ? { model: args.model } : {}),
  });
  const turn = await thread.run(args.prompt, {
    signal: args.signal,
    ...(args.outputSchema ? { outputSchema: args.outputSchema } : {}),
  });
  return turn.finalResponse.trim();
}
