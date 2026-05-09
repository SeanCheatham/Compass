/**
 * Per-session metadata: the plan+verify Develop ran, the commits it produced,
 * and whether post-checks passed. Surfaced via /api/sessions and the UI.
 */
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
}

class SessionTrackerImpl implements SessionTracker {
  private records: SessionRecord[] = [];
  private listeners = new Set<() => void>();

  private emit(): void {
    for (const fn of this.listeners) fn();
  }

  private currentRecord(): SessionRecord | null {
    return this.records[this.records.length - 1] ?? null;
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
    return rec;
  }

  setPlan(plan: string, verify: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.plan = plan;
    r.verify = verify;
    this.emit();
  }

  setStatus(status: SessionStatus): void {
    const r = this.currentRecord();
    if (!r) return;
    r.status = status;
    this.emit();
  }

  setBefore(sha: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.beforeSha = sha;
    this.emit();
  }

  setAfter(sha: string, commits: SessionCommit[]): void {
    const r = this.currentRecord();
    if (!r) return;
    r.afterSha = sha;
    r.commits = commits;
    this.emit();
  }

  addNote(note: string): void {
    const r = this.currentRecord();
    if (!r) return;
    r.notes.push(note);
    this.emit();
  }

  end(status: SessionStatus): void {
    const r = this.currentRecord();
    if (!r) return;
    r.status = status;
    r.endedAt = Date.now();
    this.emit();
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

export function createSessionTracker(): SessionTracker {
  return new SessionTrackerImpl();
}
