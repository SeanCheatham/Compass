import { EventEmitter } from "events";
import { appendFile, mkdir } from "fs/promises";
import { readFileSync, readdirSync, renameSync, statSync, unlinkSync } from "fs";
import { join } from "path";
import type { ToolDetail } from "../agents/tool-details.js";

export type OutputEventType =
  | "log"
  | "session"
  | "phase"
  | "tool"
  | "commit"
  | "error"
  | "info"
  | "agent_start"
  | "agent_complete";

export interface OutputEvent {
  type: OutputEventType;
  timestamp: number;
  data: string;
  metadata?: Record<string, unknown>;
}

export interface OutputManager {
  /** General log output (agent text) */
  log(message: string): void;

  /** Session start marker */
  session(number: number): void;

  /** Phase marker (PM, Dev, Commit) */
  phase(name: string): void;

  /** Tool usage by an agent */
  tool(agent: string, toolName: string, detail?: ToolDetail): void;

  /** Successful commit */
  commit(sha: string): void;

  /** Error message */
  error(message: string): void;

  /** Info message */
  info(message: string): void;

  /** Agent started */
  agentStart(agent: string, context?: string): void;

  /** Agent completed */
  agentComplete(agent: string, status?: string): void;

  /** Subscribe to events */
  onEvent(handler: (event: OutputEvent) => void): () => void;

  /** Get buffered events for new connections */
  getBuffer(): OutputEvent[];

  /** Path of the file events are being persisted to (null if no persistence). */
  getActivityLogPath(): string | null;
}

export const DEFAULT_MAX_BUFFER_SIZE = 1000;
export const DEFAULT_MAX_PRE_SESSION_ARCHIVES = 20;
export const DEFAULT_MAX_SESSION_LOGS = 200;

export interface OutputManagerOptions {
  /**
   * Directory to write activity logs to. Each session opens a new
   * `session-NNN.jsonl` file; events before the first session land in
   * `pre-session.jsonl`. If omitted, no persistence happens.
   */
  sessionsDir?: string;
  /**
   * Maximum number of events kept in the in-memory ring buffer (replayed to
   * each new WS client). Defaults to {@link DEFAULT_MAX_BUFFER_SIZE}. Exposed
   * primarily for tests.
   */
  maxBuffer?: number;
  /**
   * Maximum number of rotated `pre-session-*.jsonl` archives to keep on
   * disk after each startup sweep. Defaults to {@link DEFAULT_MAX_PRE_SESSION_ARCHIVES}.
   * Floored at 1. Exposed primarily for tests.
   */
  maxPreSessionArchives?: number;
  /**
   * Maximum number of `session-NNN.jsonl` files to keep on disk after each
   * startup sweep. Defaults to {@link DEFAULT_MAX_SESSION_LOGS}. Floored at 1.
   * Exposed primarily for tests.
   */
  maxSessionLogs?: number;
}

function isOutputEvent(value: unknown): value is OutputEvent {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.type === "string" &&
    typeof v.timestamp === "number" &&
    Number.isFinite(v.timestamp) &&
    typeof v.data === "string"
  );
}

class OutputManagerImpl extends EventEmitter implements OutputManager {
  private buffer: OutputEvent[] = [];
  private sessionsDir?: string;
  private currentLogPath: string | null = null;
  private writeQueue = Promise.resolve();
  private readonly maxBuffer: number;
  private readonly maxPreSessionArchives: number;
  private readonly maxSessionLogs: number;

  constructor(opts: OutputManagerOptions = {}) {
    super();
    this.sessionsDir = opts.sessionsDir;
    this.maxBuffer = Math.max(1, opts.maxBuffer ?? DEFAULT_MAX_BUFFER_SIZE);
    this.maxPreSessionArchives = Math.max(
      1,
      opts.maxPreSessionArchives ?? DEFAULT_MAX_PRE_SESSION_ARCHIVES
    );
    this.maxSessionLogs = Math.max(
      1,
      opts.maxSessionLogs ?? DEFAULT_MAX_SESSION_LOGS
    );
    if (this.sessionsDir) {
      this.currentLogPath = join(this.sessionsDir, "pre-session.jsonl");
      this.rotatePreSession();
      this.gcPreSessionArchives();
      this.gcSessionLogs();
      this.loadBufferFromDisk();
    }
  }

  private rotatePreSession(): void {
    if (!this.sessionsDir) return;
    const path = join(this.sessionsDir, "pre-session.jsonl");
    let size: number;
    try {
      size = statSync(path).size;
    } catch {
      return; // doesn't exist — nothing to rotate
    }
    if (size === 0) return; // nothing to preserve

    // ISO with `:` replaced for filesystem portability.
    const stamp = new Date().toISOString().replace(/:/g, "-");
    const dest = join(this.sessionsDir, `pre-session-${stamp}.jsonl`);
    try {
      renameSync(path, dest);
    } catch {
      // Rotation failed — fall back to prior behaviour (events get interleaved).
    }
  }

  private gcPreSessionArchives(): void {
    if (!this.sessionsDir) return;
    let names: string[];
    try {
      names = readdirSync(this.sessionsDir);
    } catch {
      return;
    }
    const archives = names
      .filter((n) => /^pre-session-.+\.jsonl$/.test(n))
      .sort(); // ISO-8601 lex order == chronological
    const excess = archives.length - this.maxPreSessionArchives;
    if (excess <= 0) return;
    for (let i = 0; i < excess; i++) {
      try {
        unlinkSync(join(this.sessionsDir, archives[i]));
      } catch {
        // best-effort; surface nothing
      }
    }
  }

  private gcSessionLogs(): void {
    if (!this.sessionsDir) return;
    let names: string[];
    try {
      names = readdirSync(this.sessionsDir);
    } catch {
      return;
    }
    const SESSION = /^session-(\d+)\.jsonl$/;
    const sessions: Array<{ n: number; name: string }> = [];
    for (const name of names) {
      const m = name.match(SESSION);
      if (!m) continue;
      sessions.push({ n: parseInt(m[1], 10), name });
    }
    sessions.sort((a, b) => a.n - b.n); // ascending — oldest first
    const excess = sessions.length - this.maxSessionLogs;
    if (excess <= 0) return;
    for (let i = 0; i < excess; i++) {
      try {
        unlinkSync(join(this.sessionsDir, sessions[i].name));
      } catch {
        // best-effort; surface nothing
      }
    }
  }

  private loadBufferFromDisk(): void {
    if (!this.sessionsDir) return;
    let names: string[];
    try {
      names = readdirSync(this.sessionsDir);
    } catch {
      return;
    }

    const ROTATED = /^pre-session-.+\.jsonl$/;
    const SESSION = /^session-\d+\.jsonl$/;
    const matched = names.filter(
      (n) => n === "pre-session.jsonl" || ROTATED.test(n) || SESSION.test(n)
    );

    type Loaded = { firstTs: number; events: OutputEvent[] };
    const loaded: Loaded[] = [];

    for (const name of matched) {
      let content: string;
      try {
        content = readFileSync(join(this.sessionsDir, name), "utf-8");
      } catch {
        continue;
      }
      const events: OutputEvent[] = [];
      let firstTs: number | null = null;
      for (const line of content.split("\n")) {
        if (!line) continue;
        let parsed: unknown;
        try {
          parsed = JSON.parse(line);
        } catch {
          continue;
        }
        if (!isOutputEvent(parsed)) continue;
        events.push(parsed);
        if (firstTs === null) firstTs = parsed.timestamp;
      }
      if (events.length === 0 || firstTs === null) continue;
      loaded.push({ firstTs, events });
    }

    loaded.sort((a, b) => a.firstTs - b.firstTs);

    for (const { events } of loaded) {
      for (const event of events) {
        this.buffer.push(event);
        if (this.buffer.length > this.maxBuffer) this.buffer.shift();
      }
    }
  }

  private emit_event(event: OutputEvent): void {
    this.buffer.push(event);
    if (this.buffer.length > this.maxBuffer) {
      this.buffer.shift();
    }
    this.emit("event", event);
    this.persist(event);
  }

  private persist(event: OutputEvent): void {
    if (!this.sessionsDir || !this.currentLogPath) return;
    const path = this.currentLogPath;
    const line = JSON.stringify(event) + "\n";
    // Serialize writes so events stay ordered even under burst.
    this.writeQueue = this.writeQueue
      .then(async () => {
        await mkdir(this.sessionsDir!, { recursive: true });
        await appendFile(path, line, "utf-8");
      })
      .catch(() => {
        // Swallow write errors — losing transcript persistence shouldn't kill
        // the loop. Errors will surface on the next mkdir/append attempt.
      });
  }

  private createEvent(
    type: OutputEventType,
    data: string,
    metadata?: Record<string, unknown>
  ): OutputEvent {
    return {
      type,
      timestamp: Date.now(),
      data,
      metadata,
    };
  }

  log(message: string): void {
    this.emit_event(this.createEvent("log", message));
  }

  session(number: number): void {
    if (this.sessionsDir) {
      this.currentLogPath = join(
        this.sessionsDir,
        `session-${String(number).padStart(3, "0")}.jsonl`
      );
    }
    this.emit_event(this.createEvent("session", String(number)));
  }

  phase(name: string): void {
    this.emit_event(this.createEvent("phase", name));
  }

  tool(agent: string, toolName: string, detail?: ToolDetail): void {
    this.emit_event(
      this.createEvent("tool", toolName, {
        agent,
        ...(detail ? { summary: detail.summary, full: detail.full } : {}),
      })
    );
  }

  commit(sha: string): void {
    this.emit_event(this.createEvent("commit", sha));
  }

  error(message: string): void {
    this.emit_event(this.createEvent("error", message));
  }

  info(message: string): void {
    this.emit_event(this.createEvent("info", message));
  }

  agentStart(agent: string, context?: string): void {
    this.emit_event(
      this.createEvent("agent_start", agent, context ? { context } : undefined)
    );
  }

  agentComplete(agent: string, status?: string): void {
    this.emit_event(
      this.createEvent("agent_complete", agent, status ? { status } : undefined)
    );
  }

  onEvent(handler: (event: OutputEvent) => void): () => void {
    this.on("event", handler);
    return () => this.off("event", handler);
  }

  getBuffer(): OutputEvent[] {
    return [...this.buffer];
  }

  getActivityLogPath(): string | null {
    return this.currentLogPath;
  }
}

export function createOutputManager(
  opts: OutputManagerOptions = {}
): OutputManager {
  return new OutputManagerImpl(opts);
}
