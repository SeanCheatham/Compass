import { EventEmitter } from "events";

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
  tool(agent: string, toolName: string): void;

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
}

const MAX_BUFFER_SIZE = 1000;

class OutputManagerImpl extends EventEmitter implements OutputManager {
  private buffer: OutputEvent[] = [];

  private emit_event(event: OutputEvent): void {
    this.buffer.push(event);
    if (this.buffer.length > MAX_BUFFER_SIZE) {
      this.buffer.shift();
    }
    this.emit("event", event);
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
    this.emit_event(this.createEvent("session", String(number)));
  }

  phase(name: string): void {
    this.emit_event(this.createEvent("phase", name));
  }

  tool(agent: string, toolName: string): void {
    this.emit_event(
      this.createEvent("tool", toolName, { agent })
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
}

export function createOutputManager(): OutputManager {
  return new OutputManagerImpl();
}
