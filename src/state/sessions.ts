/**
 * Per-session metadata: the plan+verify Develop ran, the commits it produced,
 * and whether post-checks passed. Surfaced via /api/sessions and the UI.
 */
import { readFileSync } from "node:fs";
import { writeFile, rename } from "node:fs/promises";

export interface SessionCommit {
  sha: string;
  short: string;
  subject: string;
}

export type SessionStatus =
  | "planning"
  | "awaiting_approval"
  | "developing"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "rejected_by_plan"
  | "skipped";

export interface SessionRecord {
  session: number;
  startedAt: number;
  endedAt: number | null;
  plan: string | null;
  verify: string | null;
  beforeSha: string | null;
  afterSha: string | null;
  commits: SessionCommit[];
  status: SessionStatus;
  notes: string[];
}

export interface SessionTrackerOptions {
  /**
   * Path to a JSON file used to persist session records across `compass`
   * restarts. If omitted, records live only in memory.
   */
  recordPath?: string;
}

export interface SessionTracker {
  start(session: number): SessionRecord;
  setPlan(plan: string, verify: string): void;
  setStatus(status: SessionStatus): void;
  setBefore(sha: string): void;
  setAfter(sha: string, commits: SessionCommit[]): void;
  addNote(note: string): void;
  end(status: SessionStatus): void;
  current(): SessionRecord | null;
  all(): SessionRecord[];
  onChange(fn: () => void): () => void;
  /**
   * Await any pending debounced disk write. Useful at shutdown so the final
   * mutation doesn't get dropped, and in tests for deterministic ordering.
   */
  flush(): Promise<void>;
}

const PERSIST_DEBOUNCE_MS = 50;

function isString(x: unknown): x is string {
  return typeof x === "string";
}

function isFiniteNumber(x: unknown): x is number {
  return typeof x === "number" && Number.isFinite(x);
}

function validateCommit(raw: unknown): SessionCommit | null {
  if (!raw || typeof raw !== "object") return null;
  const c = raw as Record<string, unknown>;
  if (!isString(c.sha) || !isString(c.short) || !isString(c.subject)) {
    return null;
  }
  return { sha: c.sha, short: c.short, subject: c.subject };
}

function validateRecord(raw: unknown): SessionRecord | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;

  if (!isFiniteNumber(r.session)) return null;
  if (!isFiniteNumber(r.startedAt)) return null;
  if (r.endedAt !== null && !isFiniteNumber(r.endedAt)) return null;
  if (r.plan !== null && !isString(r.plan)) return null;
  if (r.verify !== null && !isString(r.verify)) return null;
  if (r.beforeSha !== null && !isString(r.beforeSha)) return null;
  if (r.afterSha !== null && !isString(r.afterSha)) return null;
  if (!isString(r.status)) return null;
  if (!Array.isArray(r.notes)) return null;
  if (!Array.isArray(r.commits)) return null;

  const notes = r.notes.filter(isString);
  const commits: SessionCommit[] = [];
  for (const c of r.commits) {
    const v = validateCommit(c);
    if (!v) return null;
    commits.push(v);
  }

  return {
    session: r.session,
    startedAt: r.startedAt,
    endedAt: r.endedAt as number | null,
    plan: r.plan as string | null,
    verify: r.verify as string | null,
    beforeSha: r.beforeSha as string | null,
    afterSha: r.afterSha as string | null,
    commits,
    status: r.status as SessionStatus,
    notes,
  };
}

class SessionTrackerImpl implements SessionTracker {
  private records: SessionRecord[] = [];
  private listeners = new Set<() => void>();
  private recordPath?: string;
  private writeQueue: Promise<void> = Promise.resolve();
  private persistTimer: NodeJS.Timeout | null = null;

  constructor(opts: SessionTrackerOptions = {}) {
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
        `compass: could not read sessions record at ${path}: ${(err as Error).message}`
      );
      return;
    }
    if (!raw.trim()) return;

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      console.warn(
        `compass: sessions record at ${path} is not valid JSON; starting empty (${(err as Error).message})`
      );
      return;
    }
    if (!Array.isArray(parsed)) {
      console.warn(
        `compass: sessions record at ${path} is not an array; starting empty`
      );
      return;
    }

    const valid: SessionRecord[] = [];
    for (const entry of parsed) {
      const v = validateRecord(entry);
      if (v) valid.push(v);
    }
    this.records = valid;
  }

  private emit(): void {
    for (const fn of this.listeners) fn();
  }

  private currentRecord(): SessionRecord | null {
    return this.records[this.records.length - 1] ?? null;
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
    const snapshot = JSON.stringify(this.records, null, 2) + "\n";
    this.writeQueue = this.writeQueue
      .then(async () => {
        const tmp = path + ".tmp";
        await writeFile(tmp, snapshot, "utf-8");
        await rename(tmp, path);
      })
      .catch((err) => {
        console.warn(
          `compass: could not persist sessions record to ${path}: ${(err as Error).message}`
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

  start(session: number): SessionRecord {
    const rec: SessionRecord = {
      session,
      startedAt: Date.now(),
      endedAt: null,
      plan: null,
      verify: null,
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "planning",
      notes: [],
    };
    this.records.push(rec);
    this.emit();
    this.schedulePersist();
    return rec;
  }

  setPlan(plan: string, verify: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.plan = plan;
    r.verify = verify;
    this.emit();
    this.schedulePersist();
  }

  setStatus(status: SessionStatus): void {
    const r = this.currentRecord();
    if (!r) return;
    r.status = status;
    this.emit();
    this.schedulePersist();
  }

  setBefore(sha: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.beforeSha = sha;
    this.emit();
    this.schedulePersist();
  }

  setAfter(sha: string, commits: SessionCommit[]): void {
    const r = this.currentRecord();
    if (!r) return;
    r.afterSha = sha;
    r.commits = commits;
    this.emit();
    this.schedulePersist();
  }

  addNote(note: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.notes.push(note);
    this.emit();
    this.schedulePersist();
  }

  end(status: SessionStatus): void {
    const r = this.currentRecord();
    if (!r) return;
    r.status = status;
    r.endedAt = Date.now();
    this.emit();
    this.schedulePersist();
  }

  current(): SessionRecord | null {
    return this.currentRecord();
  }

  all(): SessionRecord[] {
    return this.records.slice();
  }

  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}

export function createSessionTracker(
  opts?: SessionTrackerOptions
): SessionTracker {
  return new SessionTrackerImpl(opts);
}
