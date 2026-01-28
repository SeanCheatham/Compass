import { createServer, type Server, type IncomingMessage, type ServerResponse } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import type { OutputManager, OutputEvent } from "./output-manager.js";
import type { WorkspaceConfig } from "../state/types.js";
import { readPlanFile } from "../mcp/utils/plan-store.js";
import {
  readIssueFile,
  writeIssueFile,
  createIssue,
} from "../mcp/utils/issue-store.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface CompassServer {
  port: number;
  close(): Promise<void>;
}

interface ServerContext {
  config: WorkspaceConfig;
  compassContent: string;
  outputManager: OutputManager;
  status: {
    running: boolean;
    phase: string | null;
    session: number;
    currentTask: string | null;
  };
}


function setJsonHeaders(res: ServerResponse): void {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
}

async function parseJsonBody(req: IncomingMessage): Promise<Record<string, unknown>> {
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

function setHtmlHeaders(res: ServerResponse): void {
  res.setHeader("Content-Type", "text/html");
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
    if (path === "/api/compass") {
      res.end(JSON.stringify({ content: ctx.compassContent }));
    } else if (path === "/api/plans") {
      const planFile = await readPlanFile(ctx.config.planPath);
      const completed = planFile.plans.filter(p => p.status === "completed").length;
      const pending = planFile.plans.filter(p => p.status === "pending").length;
      res.end(JSON.stringify({
        plans: planFile.plans,
        summary: {
          total: planFile.plans.length,
          completed,
          pending,
        },
      }));
    } else if (path === "/api/notes") {
      let content = "";
      try {
        content = await readFile(ctx.config.notesPath, "utf-8");
      } catch {
        content = "";
      }
      res.end(JSON.stringify({ content }));
    } else if (path === "/api/status") {
      res.end(JSON.stringify(ctx.status));
    } else if (path === "/api/issues") {
      if (req.method === "GET") {
        const issueFile = await readIssueFile(ctx.config.issuesPath);
        const open = issueFile.issues.filter((i) => i.status === "open").length;
        const inProgress = issueFile.issues.filter(
          (i) => i.status === "in_progress"
        ).length;
        const closed = issueFile.issues.filter(
          (i) => i.status === "closed"
        ).length;
        res.end(
          JSON.stringify({
            issues: issueFile.issues,
            summary: {
              total: issueFile.issues.length,
              open,
              inProgress,
              closed,
            },
          })
        );
      } else if (req.method === "POST") {
        const body = await parseJsonBody(req);
        const type = body.type as string | undefined;
        const title = body.title as string | undefined;
        const description = body.description as string | undefined;
        const priority = body.priority as string | undefined;
        if (!type || !title || (type !== "bug" && type !== "enhancement")) {
          res.statusCode = 400;
          res.end(JSON.stringify({ error: "type (bug|enhancement) and title are required" }));
          return;
        }
        const validPriority = priority === "high" || priority === "low" ? priority : "normal";
        const issueFile = await readIssueFile(ctx.config.issuesPath);
        const newIssue = createIssue(
          type,
          title,
          description || null,
          validPriority
        );
        issueFile.issues.push(newIssue);
        await writeIssueFile(ctx.config.issuesPath, issueFile);
        res.statusCode = 201;
        res.end(JSON.stringify({ issue: newIssue }));
      } else {
        res.statusCode = 405;
        res.end(JSON.stringify({ error: "Method not allowed" }));
      }
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
  res: ServerResponse
): Promise<void> {
  try {
    // Read the bundled frontend HTML from dist
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
  compassContent: string,
  outputManager: OutputManager
): Promise<CompassServer> {

  const ctx: ServerContext = {
    config,
    compassContent,
    outputManager,
    status: {
      running: true,
      phase: null,
      session: 0,
      currentTask: null,
    },
  };

  // Track status from output events
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

    // Send buffered events to new connection
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

  // Broadcast new events to all connected clients
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

          // Close all WebSocket connections
          for (const client of clients) {
            client.close();
          }

          // Close servers
          wss.close();
          return new Promise((res) => server.close(() => res()));
        },
      });
    });
  });
}
