/**
 * In-memory holder for the most recent feedback string passed to Develop's
 * `set_feedback` MCP tool. Lives between the end of a Develop run and the start
 * of the next Plan run; cleared when Plan starts so the UI matches the same
 * "consumed once" semantics the old feedback.md file had.
 *
 * The web server subscribes via onChange to broadcast updates over WebSocket.
 *
 * Optionally persists to disk so feedback survives a `compass run` restart
 * between Develop's `set_feedback` and the next Plan tick. Mirrors the
 * SessionTracker pattern: synchronous load in the constructor, debounced
 * atomic-rename writes via a writeQueue, and `flush()` on shutdown.
 */
import { readFileSync } from "node:fs";
import { writeFile, rename } from "node:fs/promises";

export interface FeedbackBus {
  /** The feedback string currently held (empty when none). */
  current(): string;
  /** Set the feedback string. Emits a change event. */
  set(feedback: string): void;
  /** Clear the feedback. Emits a change event if the value changes. */
  clear(): void;
  /** Subscribe to changes. Returns an unsubscribe function. */
  onChange(fn: (feedback: string) => void): () => void;
  /**
   * Await any pending debounced disk write. Useful at shutdown so the final
   * mutation doesn't get dropped, and in tests for deterministic ordering.
   */
  flush(): Promise<void>;
}

export interface FeedbackBusOptions {
  /**
   * Path to a JSON file used to persist the latest feedback string across
   * `compass` restarts. If omitted, feedback lives only in memory.
   */
  recordPath?: string;
}

const PERSIST_DEBOUNCE_MS = 50;

class FeedbackBusImpl implements FeedbackBus {
  private value = "";
  private listeners = new Set<(feedback: string) => void>();
  private recordPath?: string;
  private writeQueue: Promise<void> = Promise.resolve();
  private persistTimer: NodeJS.Timeout | null = null;

  constructor(opts: FeedbackBusOptions = {}) {
    this.recordPath = opts.recordPath;
    if (this.recordPath) {
      this.loadFromDisk(this.recordPath);
    }
  }

  private loadFromDisk(path: string): void {
    let raw: string;
    try {
      raw = readFileSync(path, "utf-8");
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === "ENOENT") return;
      console.warn(
        `compass: could not read feedback record at ${path}: ${(err as Error).message}`
      );
      return;
    }
    if (!raw.trim()) return;

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      console.warn(
        `compass: feedback record at ${path} is not valid JSON; starting empty (${(err as Error).message})`
      );
      return;
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.warn(
        `compass: feedback record at ${path} is not the expected shape; starting empty`
      );
      return;
    }
    const obj = parsed as Record<string, unknown>;
    if (obj.content === undefined) {
      // Tolerant: missing content field → empty.
      return;
    }
    if (typeof obj.content !== "string") {
      console.warn(
        `compass: feedback record at ${path} is not the expected shape; starting empty`
      );
      return;
    }
    this.value = obj.content;
  }

  current(): string {
    return this.value;
  }

  set(feedback: string): void {
    this.value = feedback;
    this.emit();
    this.schedulePersist();
  }

  clear(): void {
    if (this.value === "") return;
    this.value = "";
    this.emit();
    this.schedulePersist();
  }

  onChange(fn: (feedback: string) => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit(): void {
    for (const fn of this.listeners) fn(this.value);
  }

  private schedulePersist(): void {
    if (!this.recordPath) return;
    if (this.persistTimer) {
      clearTimeout(this.persistTimer);
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      this.enqueueWrite();
    }, PERSIST_DEBOUNCE_MS);
  }

  private enqueueWrite(): void {
    if (!this.recordPath) return;
    const path = this.recordPath;
    // Snapshot at enqueue time so the on-disk file matches state at the moment
    // the timer fired, not whatever later mutations have done.
    const snapshot = JSON.stringify({ content: this.value }, null, 2) + "\n";
    this.writeQueue = this.writeQueue
      .then(async () => {
        const tmp = path + ".tmp";
        await writeFile(tmp, snapshot, "utf-8");
        await rename(tmp, path);
      })
      .catch((err) => {
        console.warn(
          `compass: could not persist feedback record to ${path}: ${(err as Error).message}`
        );
      });
  }

  async flush(): Promise<void> {
    if (this.persistTimer) {
      clearTimeout(this.persistTimer);
      this.persistTimer = null;
      this.enqueueWrite();
    }
    await this.writeQueue;
  }
}

export function createFeedbackBus(opts: FeedbackBusOptions = {}): FeedbackBus {
  return new FeedbackBusImpl(opts);
}
