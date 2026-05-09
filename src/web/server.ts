import {
  createServer,
  type Server,
  type IncomingMessage,
  type ServerResponse,
} from "http";
import { WebSocketServer, WebSocket } from "ws";
import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import type { OutputManager, OutputEvent } from "./output-manager.js";
import type { WorkspaceConfig } from "../state/types.js";
import {
  readState,
  readDrafts,
  readFeedback,
  appendDraft,
} from "../mcp/utils/workspace.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface CompassServer {
  port: number;
  close(): Promise<void>;
}

interface ServerContext {
  config: WorkspaceConfig;
  outputManager: OutputManager;
  status: {
    running: boolean;
    phase: string | null;
    session: number;
  };
}

function setJsonHeaders(res: ServerResponse): void {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
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

async function handleApiRequest(
  req: IncomingMessage,
  res: ServerResponse,
  ctx: ServerContext
): Promise<void> {
  const url = new URL(req.url!, `http://localhost`);
  const path = url.pathname;

  setJsonHeaders(res);

  try {
    if (path === "/api/state" && req.method === "GET") {
      res.end(JSON.stringify({ content: await readState(ctx.config) }));
    } else if (path === "/api/drafts" && req.method === "GET") {
      res.end(JSON.stringify({ content: await readDrafts(ctx.config) }));
    } else if (path === "/api/drafts" && req.method === "POST") {
      const body = await parseJsonBody(req);
      const content = typeof body.content === "string" ? body.content.trim() : "";
      if (!content) {
        res.statusCode = 400;
        res.end(JSON.stringify({ error: "content is required" }));
        return;
      }
      await appendDraft(ctx.config, content);
      res.statusCode = 201;
      res.end(
        JSON.stringify({ content: await readDrafts(ctx.config) })
      );
    } else if (path === "/api/feedback" && req.method === "GET") {
      res.end(JSON.stringify({ content: await readFeedback(ctx.config) }));
    } else if (path === "/api/status" && req.method === "GET") {
      res.end(JSON.stringify(ctx.status));
    } else {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: "Not found" }));
    }
  } catch (error) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: String(error) }));
  }
}

async function handleStaticRequest(res: ServerResponse): Promise<void> {
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

export async function startWebServer(
  config: WorkspaceConfig,
  outputManager: OutputManager
): Promise<CompassServer> {
  const ctx: ServerContext = {
    config,
    outputManager,
    status: {
      running: true,
      phase: null,
      session: 0,
    },
  };

  outputManager.onEvent((event: OutputEvent) => {
    if (event.type === "session") {
      ctx.status.session = parseInt(event.data, 10);
    } else if (event.type === "phase") {
      ctx.status.phase = event.data;
    }
  });

  const server: Server = createServer(async (req, res) => {
    const url = new URL(req.url!, `http://localhost`);

    if (url.pathname.startsWith("/api/")) {
      await handleApiRequest(req, res, ctx);
    } else if (url.pathname === "/" || url.pathname === "/index.html") {
      await handleStaticRequest(res);
    } else {
      res.statusCode = 404;
      res.end("Not found");
    }
  });

  const wss = new WebSocketServer({ server, path: "/ws" });
  const clients = new Set<WebSocket>();

  wss.on("connection", (ws: WebSocket) => {
    clients.add(ws);

    const buffer = outputManager.getBuffer();
    for (const event of buffer) {
      ws.send(JSON.stringify(event));
    }

    ws.on("close", () => {
      clients.delete(ws);
    });

    ws.on("error", () => {
      clients.delete(ws);
    });
  });

  const unsubscribe = outputManager.onEvent((event: OutputEvent) => {
    const message = JSON.stringify(event);
    for (const client of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    }
  });

  return new Promise((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, () => {
      const addr = server.address();
      const port = typeof addr === "object" && addr ? addr.port : 0;
      resolve({
        port,
        async close(): Promise<void> {
          unsubscribe();
          ctx.status.running = false;

          for (const client of clients) {
            client.close();
          }

          wss.close();
          return new Promise((res) => server.close(() => res()));
        },
      });
    });
  });
}
