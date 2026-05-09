import {
  createServer,
  type Server,
  type IncomingMessage,
  type ServerResponse,
} from "http";
import { WebSocketServer, WebSocket } from "ws";
import { readFile } from "fs/promises";
import { watch, type FSWatcher } from "fs";
import { randomBytes, timingSafeEqual } from "crypto";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import type { OutputManager, OutputEvent } from "./output-manager.js";
import type { WorkspaceConfig } from "../state/types.js";
import {
  tryReadPlanState,
  readDrafts,
  readLessons,
  appendDraft,
} from "../mcp/utils/workspace.js";
import type { LoopController } from "../state/control.js";
import type { SessionTracker } from "../state/sessions.js";
import type { FeedbackBus } from "../state/feedback.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface CompassServer {
  port: number;
  token: string;
  url: string;
  close(): Promise<void>;
}

interface ServerContext {
  config: WorkspaceConfig;
  outputManager: OutputManager;
  controller: LoopController;
  sessions: SessionTracker;
  feedback: FeedbackBus;
  token: string;
}

function setJsonHeaders(res: ServerResponse): void {
  res.setHeader("Content-Type", "application/json");
}

function setHtmlHeaders(res: ServerResponse): void {
  res.setHeader("Content-Type", "text/html");
}

async function parseJsonBody(
  req: IncomingMessage
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString();
      // Hard cap to keep us from buffering crazy uploads on the local server.
      if (body.length > 1024 * 1024) {
        reject(new Error("Body too large"));
      }
    });
    req.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

function tokensMatch(provided: string | null, expected: string): boolean {
  if (!provided) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function extractToken(req: IncomingMessage): string | null {
  const url = new URL(req.url ?? "/", "http://localhost");
  const fromQuery = url.searchParams.get("t");
  if (fromQuery) return fromQuery;
  const header = req.headers["x-compass-token"];
  if (typeof header === "string") return header;
  if (Array.isArray(header) && header.length > 0) return header[0];
  return null;
}

function isLocalhostOrigin(origin: string | undefined): boolean {
  if (!origin) return true; // same-origin fetch from our own page sends no Origin
  try {
    const u = new URL(origin);
    const h = u.hostname;
    return h === "localhost" || h === "127.0.0.1" || h === "::1";
  } catch {
    return false;
  }
}

async function handleApiRequest(
  req: IncomingMessage,
  res: ServerResponse,
  ctx: ServerContext
): Promise<void> {
  const url = new URL(req.url!, `http://localhost`);
  const path = url.pathname;
  const method = req.method ?? "GET";

  setJsonHeaders(res);

  // For state-changing requests, require a localhost Origin in addition to the
  // token. This neuters the few cases where a malicious page could guess the
  // token (e.g. it leaks via a referer or screen capture).
  if (method !== "GET" && method !== "HEAD") {
    if (!isLocalhostOrigin(req.headers.origin)) {
      res.statusCode = 403;
      res.end(JSON.stringify({ error: "Origin not allowed" }));
      return;
    }
  }

  if (!tokensMatch(extractToken(req), ctx.token)) {
    res.statusCode = 401;
    res.end(JSON.stringify({ error: "Unauthorized" }));
    return;
  }

  try {
    if (path === "/api/state" && method === "GET") {
      res.end(JSON.stringify(await tryReadPlanState(ctx.config)));
    } else if (path === "/api/drafts" && method === "GET") {
      res.end(JSON.stringify({ content: await readDrafts(ctx.config) }));
    } else if (path === "/api/drafts" && method === "POST") {
      const body = await parseJsonBody(req);
      const content = typeof body.content === "string" ? body.content.trim() : "";
      if (!content) {
        res.statusCode = 400;
        res.end(JSON.stringify({ error: "content is required" }));
        return;
      }
      await appendDraft(ctx.config, content);
      res.statusCode = 201;
      res.end(JSON.stringify({ content: await readDrafts(ctx.config) }));
    } else if (path === "/api/feedback" && method === "GET") {
      res.end(JSON.stringify({ content: ctx.feedback.current() }));
    } else if (path === "/api/lessons" && method === "GET") {
      res.end(JSON.stringify({ content: await readLessons(ctx.config) }));
    } else if (path === "/api/status" && method === "GET") {
      res.end(JSON.stringify(ctx.controller.status()));
    } else if (path === "/api/sessions" && method === "GET") {
      res.end(JSON.stringify({ sessions: ctx.sessions.all() }));
    } else if (path === "/api/control/pause" && method === "POST") {
      const body = await parseJsonBody(req).catch(
        () => ({}) as Record<string, unknown>
      );
      const mode =
        body.mode === "after_iteration" ? "after_iteration" : "immediate";
      ctx.controller.pause(mode);
      res.end(JSON.stringify(ctx.controller.status()));
    } else if (path === "/api/control/resume" && method === "POST") {
      ctx.controller.resume();
      res.end(JSON.stringify(ctx.controller.status()));
    } else if (path === "/api/control/cancel" && method === "POST") {
      ctx.controller.cancel();
      res.end(JSON.stringify(ctx.controller.status()));
    } else if (path === "/api/control/approve" && method === "POST") {
      ctx.controller.approve();
      res.end(JSON.stringify(ctx.controller.status()));
    } else if (path === "/api/control/approve-required" && method === "POST") {
      const body = await parseJsonBody(req);
      const value = body.value === true;
      ctx.controller.setApproveRequired(value);
      res.end(JSON.stringify(ctx.controller.status()));
    } else {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: "Not found" }));
    }
  } catch (error) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: String(error) }));
  }
}

async function handleStaticRequest(
  req: IncomingMessage,
  res: ServerResponse,
  ctx: ServerContext
): Promise<void> {
  if (!tokensMatch(extractToken(req), ctx.token)) {
    res.statusCode = 401;
    res.setHeader("Content-Type", "text/plain");
    res.end("Unauthorized — append ?t=<token> to the URL printed by Compass.");
    return;
  }
  try {
    const frontendPath = join(__dirname, "frontend", "index.html");
    const html = await readFile(frontendPath, "utf-8");
    setHtmlHeaders(res);
    res.end(html);
  } catch (error) {
    res.statusCode = 500;
    res.end(`Error loading frontend: ${error}`);
  }
}

export interface StartWebServerOptions {
  config: WorkspaceConfig;
  output: OutputManager;
  controller: LoopController;
  sessions: SessionTracker;
  feedback: FeedbackBus;
}

export async function startWebServer(
  opts: StartWebServerOptions
): Promise<CompassServer> {
  const token = randomBytes(24).toString("base64url");

  const ctx: ServerContext = {
    config: opts.config,
    outputManager: opts.output,
    controller: opts.controller,
    sessions: opts.sessions,
    feedback: opts.feedback,
    token,
  };

  const server: Server = createServer(async (req, res) => {
    const url = new URL(req.url!, `http://localhost`);

    if (url.pathname.startsWith("/api/")) {
      await handleApiRequest(req, res, ctx);
    } else if (url.pathname === "/" || url.pathname === "/index.html") {
      await handleStaticRequest(req, res, ctx);
    } else {
      res.statusCode = 404;
      res.end("Not found");
    }
  });

  const wss = new WebSocketServer({ noServer: true });
  const clients = new Set<WebSocket>();

  server.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname !== "/ws") {
      socket.destroy();
      return;
    }
    if (!tokensMatch(extractToken(req), token)) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }
    if (!isLocalhostOrigin(req.headers.origin as string | undefined)) {
      socket.write("HTTP/1.1 403 Forbidden\r\n\r\n");
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  });

  wss.on("connection", (ws: WebSocket) => {
    clients.add(ws);

    // Replay buffered output events so a fresh client sees prior activity.
    const buffer = opts.output.getBuffer();
    for (const event of buffer) {
      ws.send(JSON.stringify({ kind: "output", event }));
    }

    // Send initial snapshots of state / drafts / feedback / status / sessions.
    void sendSnapshot(ctx, ws);

    ws.on("close", () => clients.delete(ws));
    ws.on("error", () => clients.delete(ws));
  });

  function broadcast(message: object): void {
    const json = JSON.stringify(message);
    for (const client of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(json);
      }
    }
  }

  // Forward all OutputManager events.
  const unsubscribeOutput = opts.output.onEvent((event: OutputEvent) => {
    broadcast({ kind: "output", event });
  });

  // Forward controller status changes.
  const unsubscribeController = opts.controller.onChange((status) => {
    broadcast({ kind: "status", status });
  });

  // Forward session tracker changes.
  const unsubscribeSessions = opts.sessions.onChange(() => {
    broadcast({ kind: "sessions", sessions: opts.sessions.all() });
  });

  // Forward feedback bus changes (Develop's `complete()` payload).
  const unsubscribeFeedback = opts.feedback.onChange((content) => {
    broadcast({ kind: "feedback", content });
  });

  // Watch the workspace dir for file changes (drafts, state, feedback).
  // Push targeted updates so the UI doesn't need to poll.
  let pushDebounce: NodeJS.Timeout | null = null;
  const pendingPaths = new Set<string>();
  const fileWatcher: FSWatcher | null = (() => {
    try {
      return watch(opts.config.workspacePath, (_event, filename) => {
        if (!filename) return;
        pendingPaths.add(filename.toString());
        if (pushDebounce) clearTimeout(pushDebounce);
        pushDebounce = setTimeout(() => {
          void flushFileChanges(ctx, pendingPaths, broadcast);
          pendingPaths.clear();
          pushDebounce = null;
        }, 50);
      });
    } catch {
      return null;
    }
  })();

  return new Promise((resolve, reject) => {
    server.on("error", reject);
    // Loopback only — never expose to the LAN.
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      const port = typeof addr === "object" && addr ? addr.port : 0;
      const url = `http://127.0.0.1:${port}/?t=${token}`;
      resolve({
        port,
        token,
        url,
        async close(): Promise<void> {
          unsubscribeOutput();
          unsubscribeController();
          unsubscribeSessions();
          unsubscribeFeedback();
          if (pushDebounce) clearTimeout(pushDebounce);
          fileWatcher?.close();

          for (const client of clients) client.close();
          wss.close();
          return new Promise((res) => server.close(() => res()));
        },
      });
    });
  });
}

async function sendSnapshot(ctx: ServerContext, ws: WebSocket): Promise<void> {
  const [state, drafts, lessons] = await Promise.all([
    tryReadPlanState(ctx.config),
    readDrafts(ctx.config),
    readLessons(ctx.config),
  ]);
  const payload = [
    { kind: "state", state },
    { kind: "drafts", content: drafts },
    { kind: "feedback", content: ctx.feedback.current() },
    { kind: "lessons", content: lessons },
    { kind: "status", status: ctx.controller.status() },
    { kind: "sessions", sessions: ctx.sessions.all() },
  ];
  for (const msg of payload) {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  }
}

async function flushFileChanges(
  ctx: ServerContext,
  changed: Set<string>,
  broadcast: (msg: object) => void
): Promise<void> {
  if (changed.has("state.json")) {
    broadcast({ kind: "state", state: await tryReadPlanState(ctx.config) });
  }
  if (changed.has("drafts.md")) {
    broadcast({ kind: "drafts", content: await readDrafts(ctx.config) });
  }
  if (changed.has("lessons.md")) {
    broadcast({ kind: "lessons", content: await readLessons(ctx.config) });
  }
}
