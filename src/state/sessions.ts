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

export interface VerifyOutput {
  command: string;
  exitCode: number | null;
  tail: string;
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
  verifyOutput: VerifyOutput | null;
  /**
   * Text Develop passed to its `set_feedback` MCP tool during this iteration.
   * Null when Develop didn't call set_feedback (or the iteration hadn't reached
   * Develop yet). Read by the next Plan run via `previousFeedback()`.
   */
  feedback: string | null;
}

export interface SessionTrackerOptions {
  /**
   * Path to a JSON file used to persist session records across `compass`
   * restarts. If omitted, records live only in memory.
   */
  recordPath?: string;
  /**
   * Maximum number of records kept in memory and on disk. When exceeded, the
   * oldest records are dropped (prior-run records first; the in-flight session
   * is always preserved because it lives at the tail). Defaults to 200.
   */
  maxPersisted?: number;
}

export interface SessionTracker {
  start(session: number): SessionRecord;
  setPlan(plan: string, verify: string): void;
  setStatus(status: SessionStatus): void;
  setBefore(sha: string): void;
  setAfter(sha: string, commits: SessionCommit[]): void;
  setVerifyOutput(out: VerifyOutput | null): void;
  addNote(note: string): void;
  setFeedback(text: string): void;
  end(status: SessionStatus): void;
  current(): SessionRecord | null;
  /**
   * Feedback from the most recently *ended* session — i.e. the session that
   * preceded the in-flight one. Returns "" when there is no prior session or
   * the prior session never recorded feedback. Used by the runner to thread
   * Develop's `set_feedback` text into the next Plan run.
   */
  previousFeedback(): string;
  all(): SessionRecord[];
  onChange(fn: () => void): () => void;
  /**
   * Number of records that existed on disk at startup. Records at indices
   * `[0, priorRunsCount)` are "prior runs" — they predate this process and
   * are eligible to be cleared. Records at indices `[priorRunsCount, ...)`
   * belong to the current run (including any in-flight session) and are never
   * cleared by `clearPriorRuns`.
   */
  priorRunsCount(): number;
  /**
   * Drop every record from prior runs. After this call `priorRunsCount()`
   * returns 0 and `all()` returns only sessions started in this process.
   * No-op if there are no prior runs.
   */
  clearPriorRuns(): void;
  /**
   * Await any pending debounced disk write. Useful at shutdown so the final
   * mutation doesn't get dropped, and in tests for deterministic ordering.
   */
  flush(): Promise<void>;
}

const PERSIST_DEBOUNCE_MS = 50;
const DEFAULT_MAX_PERSISTED_SESSIONS = 200;

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

function validateVerifyOutput(raw: unknown): VerifyOutput | null {
  if (!raw || typeof raw !== "object") return null;
  const v = raw as Record<string, unknown>;
  if (!isString(v.command)) return null;
  if (v.exitCode !== null && !isFiniteNumber(v.exitCode)) return null;
  if (!isString(v.tail)) return null;
  return {
    command: v.command,
    exitCode: v.exitCode as number | null,
    tail: v.tail,
  };
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

  // Tolerant: missing/null/invalid verifyOutput defaults to null so older
  // session files predating this field still load.
  const verifyOutput =
    r.verifyOutput === undefined || r.verifyOutput === null
      ? null
      : validateVerifyOutput(r.verifyOutput);

  // Tolerant: missing/null/non-string feedback defaults to null so older session
  // files predating this field still load.
  const feedback = isString(r.feedback) ? r.feedback : null;

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
    verifyOutput,
    feedback,
  };
}

class SessionTrackerImpl implements SessionTracker {
  private records: SessionRecord[] = [];
  private priorRunsCount_ = 0;
  private listeners = new Set<() => void>();
  private recordPath?: string;
  private writeQueue: Promise<void> = Promise.resolve();
  private persistTimer: NodeJS.Timeout | null = null;
  private readonly maxPersisted: number;

  constructor(opts: SessionTrackerOptions = {}) {
    this.recordPath = opts.recordPath;
    this.maxPersisted = Math.max(
      1,
      opts.maxPersisted ?? DEFAULT_MAX_PERSISTED_SESSIONS
    );
    if (this.recordPath) {
      this.loadFromDisk(this.recordPath);
    }
  }

  /**
   * If `records.length` exceeds the cap, drop the oldest records from the
   * front. Adjusts `priorRunsCount_` so it never references dropped indices.
   * Returns the number of records dropped (0 if no trim was necessary).
   * Never touches the in-flight session: it lives at the tail, and overflow
   * is always < records.length because maxPersisted >= 1.
   */
  private trimToMax(): number {
    const overflow = this.records.length - this.maxPersisted;
    if (overflow <= 0) return 0;
    this.records = this.records.slice(overflow);
    this.priorRunsCount_ = Math.max(0, this.priorRunsCount_ - overflow);
    return overflow;
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
    const dropped = this.trimToMax();
    this.priorRunsCount_ = this.records.length;
    if (dropped > 0) this.schedulePersist();
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
      verifyOutput: null,
      feedback: null,
    };
    this.records.push(rec);
    this.trimToMax();
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

  setVerifyOutput(out: VerifyOutput | null): void {
    const r = this.currentRecord();
    if (!r) return;
    r.verifyOutput = out;
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

  setFeedback(text: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.feedback = text;
    this.emit();
    this.schedulePersist();
  }

  previousFeedback(): string {
    // The in-flight session lives at the tail; the prior session is the one
    // whose feedback Plan should see this iteration.
    const prior = this.records[this.records.length - 2];
    return prior?.feedback ?? "";
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

  priorRunsCount(): number {
    return this.priorRunsCount_;
  }

  clearPriorRuns(): void {
    if (this.priorRunsCount_ === 0) return;
    // Invariant: every record at index >= priorRunsCount was appended after
    // loadFromDisk completed, so the in-flight session (if any) lives in that
    // tail and survives this slice. Don't add a separate guard for it.
    this.records = this.records.slice(this.priorRunsCount_);
    this.priorRunsCount_ = 0;
    this.emit();
    this.schedulePersist();
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
