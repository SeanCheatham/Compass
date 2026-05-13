import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import {
  appendLesson,
  readLessons,
  writeLessons,
} from "./utils/workspace.js";
import {
  codemapToolDefinitions,
  type CompassToolDefinition,
} from "./codemap-tools.js";
import type { PlanState, WorkspaceConfig } from "../state/types.js";

const planNextSchema = z.object({
  plan: z.string().min(1, "immediate.plan must be a non-empty markdown string"),
  verify: z.string().min(1, "immediate.verify must be a non-empty shell command"),
  verifyTimeoutMs: z.number().int().positive().optional(),
  estimatedDifficulty: z.enum(["low", "medium", "high"]).optional(),
});

const planStateSchema = z.object({
  completed: z.array(z.string()),
  immediate: z.union([planNextSchema, z.null()]),
  midTerm: z.string(),
  longTerm: z.string(),
});

function textResult(text: string, isError = false): CallToolResult {
  return {
    content: [{ type: "text", text }],
    ...(isError ? { isError: true } : {}),
  };
}

export interface CodexPlanMcpCallbacks {
  onSetState: (state: PlanState) => void;
  onEscalate?: (message: string) => void;
}

export interface CodexDevMcpCallbacks {
  onSetFeedback: (text: string) => void;
  onSignalComplete: (payload: { bypassVerify: boolean }) => void;
}

export type CodexMcpServerOptions =
  | {
      role: "plan";
      config: WorkspaceConfig;
      allowEscalate: boolean;
      callbacks: CodexPlanMcpCallbacks;
    }
  | {
      role: "develop";
      config: WorkspaceConfig;
      callbacks: CodexDevMcpCallbacks;
    };

export interface RunningCodexMcpServer {
  url: string;
  toolNames: string[];
  close: () => Promise<void>;
}

interface TransportRecord {
  transport: StreamableHTTPServerTransport;
  server: McpServer;
}

const COMMON_TOOL_NAMES = [
  "read_lessons",
  "set_lessons",
  "append_lesson",
  "outline",
  "find_symbol",
  "list_files",
  "importers_of",
  "summary",
  "search",
];

export function codexPlanMcpToolNames(allowEscalate: boolean): string[] {
  return [
    "set_state",
    ...(allowEscalate ? ["escalate"] : []),
    ...COMMON_TOOL_NAMES,
  ];
}

export function codexDevMcpToolNames(): string[] {
  return ["set_feedback", "signal_complete", ...COMMON_TOOL_NAMES];
}

export async function startCodexMcpHttpServer(
  options: CodexMcpServerOptions
): Promise<RunningCodexMcpServer> {
  const token = randomBytes(18).toString("base64url");
  const path = `/mcp/${token}`;
  const transports = new Map<string, TransportRecord>();
  const toolNames =
    options.role === "plan"
      ? codexPlanMcpToolNames(options.allowEscalate)
      : codexDevMcpToolNames();

  const httpServer = createServer((req, res) => {
    void handleMcpRequest(req, res).catch((error) => {
      if (!res.headersSent) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(
          JSON.stringify({
            jsonrpc: "2.0",
            error: { code: -32603, message: `Internal server error: ${error}` },
            id: null,
          })
        );
      } else {
        res.end();
      }
    });
  });

  async function handleMcpRequest(
    req: IncomingMessage,
    res: ServerResponse
  ): Promise<void> {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    if (url.pathname !== path) {
      res.writeHead(404).end("not found");
      return;
    }

    const sessionId = firstHeader(req.headers["mcp-session-id"]);
    if (req.method === "POST") {
      if (sessionId && transports.has(sessionId)) {
        await transports.get(sessionId)!.transport.handleRequest(req, res);
        return;
      }

      if (sessionId) {
        res.writeHead(404).end("unknown MCP session");
        return;
      }

      const record = createTransportRecord(options, transports);
      await record.server.connect(record.transport);
      await record.transport.handleRequest(req, res);
      return;
    }

    if (req.method === "GET" || req.method === "DELETE") {
      if (!sessionId || !transports.has(sessionId)) {
        res.writeHead(400).end("invalid or missing MCP session");
        return;
      }
      await transports.get(sessionId)!.transport.handleRequest(req, res);
      return;
    }

    res.writeHead(405).end("method not allowed");
  }

  await new Promise<void>((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(0, "127.0.0.1", () => {
      httpServer.off("error", reject);
      resolve();
    });
  });

  const address = httpServer.address();
  if (!address || typeof address === "string") {
    await closeHttpServer(httpServer);
    throw new Error("Codex MCP server did not bind to a TCP port.");
  }

  return {
    url: `http://127.0.0.1:${address.port}${path}`,
    toolNames,
    close: async () => {
      for (const record of [...transports.values()]) {
        await record.transport.close().catch(() => {});
        await record.server.close().catch(() => {});
      }
      transports.clear();
      await closeHttpServer(httpServer);
    },
  };
}

function createTransportRecord(
  options: CodexMcpServerOptions,
  transports: Map<string, TransportRecord>
): TransportRecord {
  const mcp = createRoleMcpServer(options);
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: () => randomUUID(),
    onsessioninitialized: (sessionId) => {
      transports.set(sessionId, { transport, server: mcp });
    },
  });
  transport.onclose = () => {
    const sessionId = transport.sessionId;
    if (sessionId) transports.delete(sessionId);
  };
  return { transport, server: mcp };
}

function createRoleMcpServer(options: CodexMcpServerOptions): McpServer {
  const server = new McpServer({
    name: options.role === "plan" ? "compass-plan" : "compass-dev",
    version: "0.1.0",
  });

  const definitions =
    options.role === "plan"
      ? planToolDefinitions(options.config, options.callbacks, options.allowEscalate)
      : devToolDefinitions(options.config, options.callbacks);

  for (const def of definitions) {
    registerCompassTool(server, def);
  }

  return server;
}

function registerCompassTool(server: McpServer, def: CompassToolDefinition): void {
  server.registerTool(
    def.name,
    {
      description: def.description,
      inputSchema: def.inputSchema,
    },
    async (args) => def.handler(args as Record<string, unknown>)
  );
}

function lessonsToolDefinitions(config: WorkspaceConfig): CompassToolDefinition[] {
  return [
    {
      name: "read_lessons",
      description:
        "Read the full contents of lessons.md (long-term memory shared across iterations). Returns an empty string if no lessons have been recorded.",
      inputSchema: {},
      handler: async () => textResult(await readLessons(config)),
    },
    {
      name: "set_lessons",
      description:
        "Replace lessons.md with the given text in full. Use this when compacting or rewriting the lessons; otherwise prefer append_lesson.",
      inputSchema: { text: z.string() },
      handler: async ({ text }) => {
        await writeLessons(config, String(text));
        return textResult("ok");
      },
    },
    {
      name: "append_lesson",
      description:
        "Append a single lesson (a short bullet, one or two sentences) to lessons.md. Use this for the common 'I learned X this iteration' case so concurrent edits don't clobber each other.",
      inputSchema: { text: z.string() },
      handler: async ({ text }) => {
        await appendLesson(config, String(text));
        return textResult("ok");
      },
    },
  ];
}

function planToolDefinitions(
  config: WorkspaceConfig,
  callbacks: CodexPlanMcpCallbacks,
  allowEscalate: boolean
): CompassToolDefinition[] {
  return [
    {
      name: "set_state",
      description:
        "Replace the full state.json contents with the given object. Plan calls this once it has decided the iteration's three horizons: `immediate` (the {plan,verify,estimatedDifficulty?} Develop runs this iteration), `midTerm` (markdown sketch of the next ~3-7 iterations — the promotion queue), and `longTerm` (markdown sketch of the strategic arc, ~10+ iterations out). Use null for `immediate` only when the project is genuinely complete; the runner will idle.",
      inputSchema: planStateSchema.shape,
      handler: async (args) => {
        const parsed = planStateSchema.parse(args);
        callbacks.onSetState(parsed);
        return textResult("ok");
      },
    },
    ...(allowEscalate
      ? [
          {
            name: "escalate",
            description:
              "Escalate this planning iteration to the higher-reasoning planning pass. Call this when the default planning pass is out of its depth: the strategic picture is unclear, drafts conflict in ways you can't reconcile, the codebase reality contradicts what feedback implied, or you're about to set_state on a plan you don't have confidence in. The runner aborts your current stream and restarts the iteration from scratch, threading your `message` through as context. Call this BEFORE `set_state`: any state you set in the first pass is discarded when the higher-reasoning pass starts. First call wins; subsequent escalates are ignored.",
            inputSchema: {
              message: z.string().min(1, "escalate.message must be non-empty"),
            },
            handler: async ({ message }) => {
              callbacks.onEscalate?.(String(message));
              return textResult("ok");
            },
          } satisfies CompassToolDefinition,
        ]
      : []),
    ...lessonsToolDefinitions(config),
    ...codemapToolDefinitions(config),
  ];
}

function devToolDefinitions(
  config: WorkspaceConfig,
  callbacks: CodexDevMcpCallbacks
): CompassToolDefinition[] {
  return [
    {
      name: "set_feedback",
      description:
        "Set the feedback string handed to the next Plan run. STRONGLY recommended — Plan uses it to decide what to plan next. Pass discoveries that should reshape the plan, blockers, or a one-line confirmation if everything went smoothly. Call this BEFORE `signal_complete`. Last call wins; calling again replaces the prior text. Soft cap: 3 KB. If you skip this entirely, Plan will see no feedback and just continue from state alone.",
      inputSchema: { text: z.string() },
      handler: async ({ text }) => {
        callbacks.onSetFeedback(String(text));
        return textResult("ok");
      },
    },
    {
      name: "signal_complete",
      description:
        "Signal that this Develop iteration is finished. Call this exactly once, as your FINAL action — the runner aborts the stream right after this call returns and moves to post-checks (verify + clean tree). Set `bypassVerify: true` ONLY when you have determined mid-implementation that the verify command in the plan can't pass without Plan replanning (e.g. the command is wrong, asserts something impossible, or needs an out-of-scope dependency); the runner will skip the verify post-check (clean-tree still applies) and route your feedback straight to Plan. Always call `set_feedback` first to explain.",
      inputSchema: { bypassVerify: z.boolean().optional() },
      handler: async ({ bypassVerify }) => {
        callbacks.onSignalComplete({ bypassVerify: bypassVerify === true });
        return textResult(
          "Iteration complete. The runner has captured your signal and will terminate this stream momentarily. Do not take any further action; any subsequent assistant text or tool calls will be discarded."
        );
      },
    },
    ...lessonsToolDefinitions(config),
    ...codemapToolDefinitions(config),
  ];
}

function firstHeader(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

async function closeHttpServer(httpServer: ReturnType<typeof createServer>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    httpServer.close((error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}
