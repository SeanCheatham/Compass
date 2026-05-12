/**
 * Runtime controls for the Plan + Develop loop.
 *
 * Phases the runner moves through:
 *   - idle              waiting for drafts or a non-null `immediate`
 *   - planning          Plan agent is running
 *   - awaiting_approval Plan finished, runner is gated on user before Develop
 *   - developing        Develop agent is running
 *   - paused            user explicitly paused; loop will not advance phases
 *
 * The user-facing knobs (HTTP endpoints) translate to:
 *   - pause(mode) → set the pause flag; the runner honours it at gates
 *                   per the mode (immediate = next gate; after_iteration =
 *                   only the pre-iteration gate, so Plan→Develop runs through)
 *   - resume()   → clear the pause flag
 *   - cancel()   → abort the in-flight agent and skip the rest of this iteration
 *   - approve()  → release the awaiting_approval gate
 *   - setApproveRequired(b) → toggle whether each Develop run waits for approve()
 */
export type LoopPhase =
  | "idle"
  | "planning"
  | "awaiting_approval"
  | "developing"
  | "paused";

/**
 * How aggressively a pause request takes effect:
 *   - immediate       honour at every gate (post-Plan and pre-iteration)
 *   - after_iteration skip the post-Plan gate so the current Develop runs;
 *                     only the pre-iteration gate honours the pause
 */
export type PauseMode = "immediate" | "after_iteration";

export interface LoopStatus {
  phase: LoopPhase;
  paused: boolean;
  pauseMode: PauseMode;
  approveRequired: boolean;
  session: number;
  pendingApproval: {
    plan: string;
    verify: string;
  } | null;
}

export interface LoopController {
  status(): LoopStatus;

  /** Set true to require approve() before each Develop run. */
  setApproveRequired(value: boolean): void;
  pause(mode?: PauseMode): void;
  resume(): void;
  /** Approve the pending immediate plan so Develop can run. */
  approve(): void;
  /** Abort the current agent (if any) and skip the rest of this iteration. */
  cancel(): void;

  // --- runner-side helpers (not exposed on HTTP) ---

  /** Called by the runner when entering a new phase. */
  setPhase(phase: LoopPhase): void;
  setSession(n: number): void;

  /**
   * Wait until paused == false. Returns false if cancelled while waiting.
   * The runner calls this between phases.
   */
  waitWhilePaused(signal: AbortSignal): Promise<boolean>;

  /**
   * Block until the user clicks Approve (or skip immediately if approveRequired
   * is false). Returns false if cancelled while waiting.
   */
  awaitApproval(
    pending: { plan: string; verify: string },
    signal: AbortSignal
  ): Promise<boolean>;

  /**
   * Get an AbortSignal for the current iteration. Aborted by cancel() or
   * by the parent process abort signal. Each call returns a fresh signal —
   * the runner should call it per Plan/Develop invocation.
   */
  iterationSignal(parent: AbortSignal): AbortSignal;

  /** Subscribe to status changes (for pushing over WebSocket). */
  onChange(fn: (status: LoopStatus) => void): () => void;

  /** Clear cancellation state at the start of each new iteration. */
  resetIteration(): void;
}

interface Waiter {
  resolve: (ok: boolean) => void;
  // Cleanup for any signal listener we attached.
  detach: () => void;
}

class LoopControllerImpl implements LoopController {
  private phase: LoopPhase = "idle";
  private paused = false;
  private pauseMode: PauseMode = "immediate";
  private approveRequired: boolean;
  private session = 0;
  private cancelled = false;
  private currentAbort: AbortController | null = null;

  private pendingApproval: { plan: string; verify: string } | null = null;
  private approvalWaiters: Waiter[] = [];
  private pauseWaiters: Waiter[] = [];

  private listeners = new Set<(s: LoopStatus) => void>();

  constructor(opts: { approveRequired: boolean }) {
    this.approveRequired = opts.approveRequired;
  }

  status(): LoopStatus {
    return {
      phase: this.phase,
      paused: this.paused,
      pauseMode: this.pauseMode,
      approveRequired: this.approveRequired,
      session: this.session,
      pendingApproval: this.pendingApproval,
    };
  }

  onChange(fn: (status: LoopStatus) => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit(): void {
    const s = this.status();
    for (const fn of this.listeners) fn(s);
  }

  setApproveRequired(value: boolean): void {
    this.approveRequired = value;
    this.emit();
  }

  pause(mode: PauseMode = "immediate"): void {
    // Allow upgrading an already-set "after_iteration" pause to "immediate",
    // but never downgrade an "immediate" pause to "after_iteration".
    if (this.paused && (mode === "after_iteration" || mode === this.pauseMode)) {
      return;
    }
    this.paused = true;
    this.pauseMode = mode;
    this.emit();
  }

  resume(): void {
    if (!this.paused) return;
    this.paused = false;
    this.pauseMode = "immediate";
    const waiters = this.pauseWaiters;
    this.pauseWaiters = [];
    for (const w of waiters) {
      w.detach();
      w.resolve(true);
    }
    this.emit();
  }

  approve(): void {
    if (!this.pendingApproval) return;
    this.pendingApproval = null;
    const waiters = this.approvalWaiters;
    this.approvalWaiters = [];
    for (const w of waiters) {
      w.detach();
      w.resolve(true);
    }
    this.emit();
  }

  cancel(): void {
    this.cancelled = true;
    if (this.currentAbort) this.currentAbort.abort();
    // Release any blocked waiters.
    const ap = this.approvalWaiters;
    this.approvalWaiters = [];
    for (const w of ap) {
      w.detach();
      w.resolve(false);
    }
    const pw = this.pauseWaiters;
    this.pauseWaiters = [];
    for (const w of pw) {
      w.detach();
      w.resolve(false);
    }
    this.pendingApproval = null;
    this.emit();
  }

  setPhase(phase: LoopPhase): void {
    this.phase = phase;
    this.emit();
  }

  setSession(n: number): void {
    this.session = n;
    this.emit();
  }

  resetIteration(): void {
    this.cancelled = false;
    this.currentAbort = null;
  }

  async waitWhilePaused(signal: AbortSignal): Promise<boolean> {
    if (this.cancelled || signal.aborted) return false;
    if (!this.paused) return true;
    return new Promise<boolean>((resolve) => {
      const onAbort = () => {
        this.pauseWaiters = this.pauseWaiters.filter((w) => w !== waiter);
        resolve(false);
      };
      const waiter: Waiter = {
        resolve,
        detach: () => signal.removeEventListener("abort", onAbort),
      };
      signal.addEventListener("abort", onAbort, { once: true });
      this.pauseWaiters.push(waiter);
    });
  }

  async awaitApproval(
    pending: { plan: string; verify: string },
    signal: AbortSignal
  ): Promise<boolean> {
    if (this.cancelled || signal.aborted) return false;
    if (!this.approveRequired) return true;
    this.pendingApproval = pending;
    this.emit();
    return new Promise<boolean>((resolve) => {
      const onAbort = () => {
        this.approvalWaiters = this.approvalWaiters.filter((w) => w !== waiter);
        this.pendingApproval = null;
        this.emit();
        resolve(false);
      };
      const waiter: Waiter = {
        resolve,
        detach: () => signal.removeEventListener("abort", onAbort),
      };
      signal.addEventListener("abort", onAbort, { once: true });
      this.approvalWaiters.push(waiter);
    });
  }

  iterationSignal(parent: AbortSignal): AbortSignal {
    const ctl = new AbortController();
    this.currentAbort = ctl;

    if (parent.aborted) ctl.abort();
    else parent.addEventListener("abort", () => ctl.abort(), { once: true });

    if (this.cancelled) ctl.abort();
    return ctl.signal;
  }
}

export function createLoopController(opts: {
  approveRequired: boolean;
}): LoopController {
  return new LoopControllerImpl(opts);
}
