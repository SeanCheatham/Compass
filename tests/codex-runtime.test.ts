import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

import {
  codexDevMcpToolNames,
  codexPlanMcpToolNames,
  startCodexMcpHttpServer,
} from "../src/mcp/codex-http-server.ts";
import { parseAgentRuntime } from "../src/agents/runtime.ts";
import type { PlanState, WorkspaceConfig } from "../src/state/types.ts";
import {
  ensureWorkspaceExists,
  getWorkspaceConfig,
} from "../src/mcp/utils/workspace.ts";

async function tempWorkspace(): Promise<{
  dir: string;
  config: WorkspaceConfig;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-codex-runtime-"));
  const config = getWorkspaceConfig(dir);
  await ensureWorkspaceExists(config);
  return {
    dir,
    config,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

async function connectClient(url: string): Promise<Client> {
  const client = new Client({ name: "compass-test-client", version: "0.0.0" });
  await client.connect(new StreamableHTTPClientTransport(new URL(url)));
  return client;
}

test("agent runtime: parses supported runtimes", () => {
  assert.equal(parseAgentRuntime(undefined), "claude");
  assert.equal(parseAgentRuntime("claude"), "claude");
  assert.equal(parseAgentRuntime(" CODEX "), "codex");
  assert.throws(() => parseAgentRuntime("both"), /Unknown agent runtime/);
});

test("codex MCP tool names are role scoped", () => {
  assert.deepEqual(
    codexPlanMcpToolNames(false).slice(0, 3),
    ["set_state", "read_lessons", "set_lessons"]
  );
  assert.equal(codexPlanMcpToolNames(true).includes("escalate"), true);
  assert.equal(codexPlanMcpToolNames(false).includes("escalate"), false);
  assert.equal(codexDevMcpToolNames().includes("set_feedback"), true);
  assert.equal(codexDevMcpToolNames().includes("signal_complete"), true);
  assert.equal(codexDevMcpToolNames().includes("set_state"), false);
});

test("codex MCP plan server exposes callbacks over Streamable HTTP", async () => {
  const { config, cleanup } = await tempWorkspace();
  let capturedState: PlanState | null = null;
  let escalation = "";
  const server = await startCodexMcpHttpServer({
    role: "plan",
    config,
    allowEscalate: true,
    callbacks: {
      onSetState: (state) => {
        capturedState = state;
      },
      onEscalate: (message) => {
        escalation = message;
      },
    },
  });

  const client = await connectClient(server.url);
  try {
    const tools = await client.listTools();
    const names = tools.tools.map((tool) => tool.name);
    assert.equal(names.includes("set_state"), true);
    assert.equal(names.includes("escalate"), true);
    assert.equal(names.includes("signal_complete"), false);

    const state: PlanState = {
      completed: ["one thing shipped"],
      immediate: {
        plan: "Implement the next thing",
        verify: "npm test",
        estimatedDifficulty: "medium",
      },
      midTerm: "Next queue",
      longTerm: "Long arc",
    };
    const setState = await client.callTool({
      name: "set_state",
      arguments: state,
    });
    assert.equal(setState.content[0]?.type, "text");
    assert.equal(setState.content[0]?.text, "ok");
    assert.deepEqual(capturedState, state);

    await client.callTool({
      name: "escalate",
      arguments: { message: "Need a deeper strategy pass." },
    });
    assert.equal(escalation, "Need a deeper strategy pass.");
  } finally {
    await client.close();
    await server.close();
    await cleanup();
  }
});

test("codex MCP develop server captures completion callbacks", async () => {
  const { config, cleanup } = await tempWorkspace();
  let feedback = "";
  let bypassVerify: boolean | null = null;
  const server = await startCodexMcpHttpServer({
    role: "develop",
    config,
    callbacks: {
      onSetFeedback: (text) => {
        feedback = text;
      },
      onSignalComplete: (payload) => {
        bypassVerify = payload.bypassVerify;
      },
    },
  });

  const client = await connectClient(server.url);
  try {
    const tools = await client.listTools();
    const names = tools.tools.map((tool) => tool.name);
    assert.equal(names.includes("set_feedback"), true);
    assert.equal(names.includes("signal_complete"), true);
    assert.equal(names.includes("set_state"), false);

    await client.callTool({
      name: "set_feedback",
      arguments: { text: "Shipped the Codex path." },
    });
    await client.callTool({
      name: "signal_complete",
      arguments: { bypassVerify: true },
    });

    assert.equal(feedback, "Shipped the Codex path.");
    assert.equal(bypassVerify, true);
  } finally {
    await client.close();
    await server.close();
    await cleanup();
  }
});
