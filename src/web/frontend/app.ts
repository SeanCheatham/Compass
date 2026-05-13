import { renderMarkdown } from "./markdown.js";

interface OutputEvent {
  type: string;
  timestamp: number;
  data: string;
  metadata?: Record<string, unknown>;
}

interface PlanNext {
  plan: string;
  verify: string;
  verifyTimeoutMs?: number;
}

interface PlanState {
  completed: string[];
  immediate: PlanNext | null;
  midTerm: string;
  longTerm: string;
}

type PauseMode = "immediate" | "after_iteration";

interface LoopStatus {
  phase: "idle" | "planning" | "awaiting_approval" | "developing" | "paused";
  paused: boolean;
  pauseMode: PauseMode;
  approveRequired: boolean;
  session: number;
  cancellationRequested: boolean;
  pendingApproval: { plan: string; verify: string } | null;
}

interface SessionCommit {
  sha: string;
  short: string;
  subject: string;
}

interface SessionRecord {
  session: number;
  startedAt: number;
  endedAt: number | null;
  plan: string | null;
  verify: string | null;
  beforeSha: string | null;
  afterSha: string | null;
  commits: SessionCommit[];
  status: string;
  notes: string[];
  verifyOutput: { command: string; exitCode: number | null; tail: string } | null;
}

type WsMessage =
  | { kind: "output"; event: OutputEvent }
  | { kind: "state"; state: PlanState }
  | { kind: "drafts"; content: string }
  | { kind: "feedback"; content: string }
  | { kind: "lessons"; content: string }
  | { kind: "compass"; content: string }
  | { kind: "status"; status: LoopStatus }
  | { kind: "sessions"; sessions: SessionRecord[]; priorRunsCount: number };

class CompassApp {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelay = 1000;
  private autoScroll = true;
  private currentTab = "activity";
  private token: string;
  private status: LoopStatus | null = null;
  private compassRemote = "";
  private compassRemoteSeen = false;

  constructor() {
    const params = new URLSearchParams(window.location.search);
    this.token = params.get("t") ?? "";
    this.init();
  }

  private apiHeaders(extra: Record<string, string> = {}): Record<string, string> {
    return {
      "X-Compass-Token": this.token,
      ...extra,
    };
  }

  private async init(): Promise<void> {
    if (!this.token) {
      this.updateConn("error", "Missing token in URL");
      const log = document.getElementById("activity-log");
      if (log) {
        const entry = document.createElement("div");
        entry.className = "log-entry error";
        entry.textContent =
          "No access token in URL. Use the URL printed by `compass run`.";
        log.appendChild(entry);
      }
      return;
    }

    this.setupTabs();
    this.setupDraftForm();
    this.setupVisionForm();
    this.setupControls();
    this.connectWebSocket();
    this.setupAutoScroll();
  }

  private setupTabs(): void {
    document.querySelectorAll(".tab").forEach((tab) => {
      tab.addEventListener("click", () => {
        const tabName = (tab as HTMLElement).dataset.tab;
        if (tabName) this.switchTab(tabName);
      });
    });
  }

  private switchTab(tabName: string): void {
    this.currentTab = tabName;

    document.querySelectorAll(".tab").forEach((tab) => {
      tab.classList.toggle(
        "active",
        (tab as HTMLElement).dataset.tab === tabName
      );
    });

    document.querySelectorAll(".panel").forEach((panel) => {
      panel.classList.toggle("active", panel.id === `${tabName}-panel`);
    });
  }

  private setupControls(): void {
    this.setupPauseMenu();
    document.getElementById("resume-btn")?.addEventListener("click", () => {
      void this.postControl("resume");
    });
    document.getElementById("cancel-btn")?.addEventListener("click", () => {
      if (
        !confirm("Cancel the current iteration? The agent will be aborted.")
      )
        return;
      void this.postControl("cancel");
    });
    document.getElementById("approve-btn")?.addEventListener("click", () => {
      void this.postControl("approve");
    });
    const toggle = document.getElementById(
      "approve-required-toggle"
    ) as HTMLInputElement | null;
    toggle?.addEventListener("change", () => {
      void this.postApproveRequired(toggle.checked);
    });
  }

  private async postControl(action: string): Promise<void> {
    try {
      await fetch(`/api/control/${action}`, {
        method: "POST",
        headers: this.apiHeaders(),
      });
    } catch (err) {
      console.error("control failed:", err);
    }
  }

  private async postPause(mode: PauseMode): Promise<void> {
    try {
      await fetch(`/api/control/pause`, {
        method: "POST",
        headers: this.apiHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({ mode }),
      });
    } catch (err) {
      console.error("pause failed:", err);
    }
  }

  private setupPauseMenu(): void {
    const trigger = document.getElementById("pause-btn") as HTMLButtonElement | null;
    const list = document.getElementById("pause-menu-list") as HTMLDivElement | null;
    if (!trigger || !list) return;

    const setOpen = (open: boolean): void => {
      list.hidden = !open;
      trigger.setAttribute("aria-expanded", open ? "true" : "false");
    };

    trigger.addEventListener("click", (e) => {
      e.stopPropagation();
      setOpen(list.hidden);
    });

    list.querySelectorAll<HTMLButtonElement>(".ctrl-menu-item").forEach((item) => {
      item.addEventListener("click", (e) => {
        e.stopPropagation();
        const mode = (item.dataset.pauseMode as PauseMode | undefined) ?? "immediate";
        setOpen(false);
        void this.postPause(mode);
      });
    });

    document.addEventListener("click", (e) => {
      if (list.hidden) return;
      const target = e.target as Node | null;
      if (target && (trigger.contains(target) || list.contains(target))) return;
      setOpen(false);
    });

    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !list.hidden) setOpen(false);
    });
  }

  private async postApproveRequired(value: boolean): Promise<void> {
    try {
      await fetch(`/api/control/approve-required`, {
        method: "POST",
        headers: this.apiHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({ value }),
      });
    } catch (err) {
      console.error("approve-required failed:", err);
    }
  }

  private renderText(elId: string, content: string, emptyMessage: string): void {
    const el = document.getElementById(elId)!;
    el.replaceChildren();
    if (content.trim()) {
      const pre = document.createElement("pre");
      pre.className = "text-block";
      pre.textContent = content;
      el.appendChild(pre);
    } else {
      const span = document.createElement("span");
      span.className = "empty";
      span.textContent = emptyMessage;
      el.appendChild(span);
    }
  }

  private renderMarkdownInto(
    elId: string,
    content: string,
    emptyMessage: string
  ): void {
    const el = document.getElementById(elId)!;
    el.replaceChildren();
    if (content.trim()) {
      const block = document.createElement("div");
      block.className = "markdown-block";
      block.appendChild(renderMarkdown(content));
      el.appendChild(block);
    } else {
      const span = document.createElement("span");
      span.className = "empty";
      span.textContent = emptyMessage;
      el.appendChild(span);
    }
  }

  private renderState(state: PlanState): void {
    const el = document.getElementById("state-content")!;
    el.replaceChildren();

    el.appendChild(this.makeHeading("Completed"));
    if (state.completed.length === 0) {
      el.appendChild(this.makeEmpty("No iterations shipped yet."));
    } else {
      const ul = document.createElement("ul");
      ul.className = "completed-list";
      for (const c of state.completed) {
        const li = document.createElement("li");
        const md = document.createElement("div");
        md.className = "markdown-block markdown-inline";
        md.appendChild(renderMarkdown(c));
        li.appendChild(md);
        ul.appendChild(li);
      }
      el.appendChild(ul);
    }

    el.appendChild(this.makeHeading("Immediate"));
    if (state.immediate) {
      const block = document.createElement("div");
      block.className = "markdown-block";
      block.appendChild(renderMarkdown(state.immediate.plan));
      el.appendChild(block);

      el.appendChild(this.makeVerifyRow(state.immediate.verify));
    } else {
      el.appendChild(
        this.makeEmpty("No immediate plan. Add a draft to get started.")
      );
    }

    el.appendChild(this.makeHeading("Mid-term"));
    if (state.midTerm.trim()) {
      const block = document.createElement("div");
      block.className = "markdown-block";
      block.appendChild(renderMarkdown(state.midTerm));
      el.appendChild(block);
    } else {
      el.appendChild(this.makeEmpty("No mid-term plan sketched."));
    }

    el.appendChild(this.makeHeading("Long-term"));
    if (state.longTerm.trim()) {
      const block = document.createElement("div");
      block.className = "markdown-block";
      block.appendChild(renderMarkdown(state.longTerm));
      el.appendChild(block);
    } else {
      el.appendChild(this.makeEmpty("No long-term plan sketched."));
    }
  }

  private makeVerifyRow(verify: string): HTMLElement {
    const verifyRow = document.createElement("div");
    verifyRow.className = "verify-row";
    const verifyLabel = document.createElement("span");
    verifyLabel.className = "verify-label";
    verifyLabel.textContent = "verify";
    const verifyCmd = document.createElement("code");
    verifyCmd.className = "verify-cmd";
    verifyCmd.textContent = verify;
    verifyRow.appendChild(verifyLabel);
    verifyRow.appendChild(verifyCmd);
    return verifyRow;
  }

  private renderSessions(
    sessions: SessionRecord[],
    priorRunsCount: number
  ): void {
    const badge = document.getElementById("sessions-badge")!;
    badge.textContent = sessions.length > 0 ? String(sessions.length) : "";

    const el = document.getElementById("sessions-content")!;
    el.replaceChildren();

    if (sessions.length === 0) {
      el.appendChild(this.makeEmpty("No sessions yet."));
      return;
    }

    // Clamp so a stale UI render with a smaller `sessions` array degrades
    // gracefully (no out-of-bounds slicing).
    const clamped = Math.min(priorRunsCount, sessions.length);
    const priorRuns = sessions.slice(0, clamped);
    const currentRuns = sessions.slice(clamped);

    for (const s of [...currentRuns].reverse()) {
      el.appendChild(this.renderSessionCard(s));
    }

    if (priorRuns.length > 0) {
      el.appendChild(this.renderPriorRunsDivider(priorRuns.length));
      for (const s of [...priorRuns].reverse()) {
        el.appendChild(this.renderSessionCard(s));
      }
    }
  }

  private renderPriorRunsDivider(count: number): HTMLElement {
    const wrapper = document.createElement("div");
    wrapper.className = "sessions-divider";

    const leftRule = document.createElement("hr");
    wrapper.appendChild(leftRule);

    const btn = document.createElement("button");
    btn.className = "clear-prior-btn";
    btn.textContent = `Clear prior runs (${count})`;
    btn.addEventListener("click", () => {
      if (
        !confirm(
          `Clear ${count} prior session(s)? This cannot be undone.`
        )
      )
        return;
      void this.postClearPrior();
    });
    wrapper.appendChild(btn);

    const rightRule = document.createElement("hr");
    wrapper.appendChild(rightRule);

    return wrapper;
  }

  private async postClearPrior(): Promise<void> {
    try {
      await fetch("/api/sessions/clear-prior", {
        method: "POST",
        headers: this.apiHeaders(),
      });
    } catch (err) {
      console.error("clear-prior failed:", err);
    }
  }

  private renderSessionCard(s: SessionRecord): HTMLElement {
    const card = document.createElement("div");
    card.className = `session-card session-status-${s.status}`;

    const header = document.createElement("div");
    header.className = "session-header";

    const num = document.createElement("span");
    num.className = "session-num";
    num.textContent = `Session ${s.session}`;
    header.appendChild(num);

    const status = document.createElement("span");
    status.className = "session-status";
    status.textContent = s.status;
    header.appendChild(status);

    if (s.endedAt) {
      const dur = document.createElement("span");
      dur.className = "session-dur";
      const seconds = Math.round((s.endedAt - s.startedAt) / 1000);
      dur.textContent = `${seconds}s`;
      header.appendChild(dur);
    }

    card.appendChild(header);

    if (s.plan) {
      const planBlock = document.createElement("div");
      planBlock.className = "session-plan";
      const firstLine = s.plan.split("\n")[0].slice(0, 200);
      planBlock.textContent = firstLine;
      card.appendChild(planBlock);
    }

    if (s.verify) {
      card.appendChild(this.makeVerifyRow(s.verify));
    }

    if (s.commits.length > 0) {
      const commits = document.createElement("ul");
      commits.className = "session-commits";
      for (const c of s.commits) {
        const li = document.createElement("li");
        const sha = document.createElement("code");
        sha.className = "commit-sha";
        sha.textContent = c.short;
        const subj = document.createElement("span");
        subj.className = "commit-subj";
        subj.textContent = c.subject;
        li.appendChild(sha);
        li.appendChild(subj);
        commits.appendChild(li);
      }
      card.appendChild(commits);
    } else if (
      s.status === "succeeded" ||
      s.status === "failed" ||
      s.status === "cancelled"
    ) {
      const none = document.createElement("div");
      none.className = "session-no-commits";
      none.textContent = "(no commits)";
      card.appendChild(none);
    }

    if (s.verifyOutput) {
      const details = document.createElement("details");
      details.className = "session-verify-output";
      const summary = document.createElement("summary");
      const exit = s.verifyOutput.exitCode == null
        ? "unknown exit"
        : `exit ${s.verifyOutput.exitCode}`;
      summary.textContent = `verify failed (${exit}) — show output`;
      details.appendChild(summary);
      const pre = document.createElement("pre");
      pre.className = "session-verify-tail";
      pre.textContent = s.verifyOutput.tail;
      details.appendChild(pre);
      card.appendChild(details);
    }

    if (s.notes.length > 0) {
      const notes = document.createElement("details");
      notes.className = "session-notes";
      const summary = document.createElement("summary");
      summary.textContent = `Notes (${s.notes.length})`;
      notes.appendChild(summary);
      for (const n of s.notes) {
        const p = document.createElement("pre");
        p.className = "session-note";
        p.textContent = n;
        notes.appendChild(p);
      }
      card.appendChild(notes);
    }

    return card;
  }

  private makeHeading(text: string): HTMLElement {
    const h = document.createElement("h3");
    h.className = "section-heading";
    h.textContent = text;
    return h;
  }

  private makeEmpty(text: string): HTMLElement {
    const span = document.createElement("span");
    span.className = "empty";
    span.textContent = text;
    return span;
  }

  private renderDrafts(content: string): void {
    const badge = document.getElementById("drafts-badge")!;
    const lines = content
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0);
    badge.textContent = lines.length > 0 ? String(lines.length) : "";
    this.renderText("drafts-content", content, "No pending drafts.");
  }

  private renderStatus(status: LoopStatus): void {
    this.status = status;

    const phasePill = document.getElementById("phase-pill")!;
    const pausePending =
      status.paused &&
      status.phase !== "paused" &&
      status.phase !== "idle";
    if (pausePending) {
      const label =
        status.pauseMode === "after_iteration"
          ? "pausing after iteration"
          : "pausing";
      phasePill.textContent = label;
      phasePill.className = `phase-pill phase-paused`;
    } else {
      phasePill.textContent = status.paused ? "paused" : status.phase;
      phasePill.className = `phase-pill phase-${status.paused ? "paused" : status.phase}`;
    }

    const pauseMenu = document.getElementById("pause-menu") as HTMLDivElement;
    const resumeBtn = document.getElementById("resume-btn") as HTMLButtonElement;
    const cancelBtn = document.getElementById("cancel-btn") as HTMLButtonElement;
    const approveBtn = document.getElementById("approve-btn") as HTMLButtonElement;
    const approveToggle = document.getElementById(
      "approve-required-toggle"
    ) as HTMLInputElement;

    pauseMenu.hidden = status.paused;
    resumeBtn.hidden = !status.paused;
    cancelBtn.hidden =
      status.phase !== "planning" &&
      status.phase !== "developing" &&
      status.phase !== "awaiting_approval";
    approveBtn.hidden = status.phase !== "awaiting_approval";

    if (approveToggle.checked !== status.approveRequired) {
      approveToggle.checked = status.approveRequired;
    }

    if (status.session > 0) {
      this.updateConn("running", `Session ${status.session} — ${status.phase}`);
    } else {
      this.updateConn("connected", `Idle — ${status.phase}`);
    }
  }

  private setupDraftForm(): void {
    const form = document.getElementById("draft-form") as HTMLFormElement;
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      await this.submitDraft();
    });
  }

  private async submitDraft(): Promise<void> {
    const textarea = document.getElementById(
      "draft-content"
    ) as HTMLTextAreaElement;
    const content = textarea.value.trim();
    if (!content) return;

    try {
      const res = await fetch("/api/drafts", {
        method: "POST",
        headers: this.apiHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({ content }),
      });
      if (res.ok) {
        textarea.value = "";
      }
    } catch (error) {
      console.error("Failed to submit draft:", error);
    }
  }

  private setupVisionForm(): void {
    const form = document.getElementById("vision-form") as HTMLFormElement;
    const textarea = document.getElementById(
      "vision-content"
    ) as HTMLTextAreaElement;
    const revertBtn = document.getElementById(
      "vision-revert-btn"
    ) as HTMLButtonElement;

    textarea.addEventListener("input", () => this.refreshVisionDirtyState());
    revertBtn.addEventListener("click", () => {
      textarea.value = this.compassRemote;
      this.refreshVisionDirtyState();
    });

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      await this.saveVision();
    });
  }

  private isVisionDirty(): boolean {
    const textarea = document.getElementById(
      "vision-content"
    ) as HTMLTextAreaElement | null;
    if (!textarea) return false;
    return textarea.value !== this.compassRemote;
  }

  private refreshVisionDirtyState(): void {
    const saveBtn = document.getElementById(
      "vision-save-btn"
    ) as HTMLButtonElement | null;
    const revertBtn = document.getElementById(
      "vision-revert-btn"
    ) as HTMLButtonElement | null;
    const statusEl = document.getElementById(
      "vision-status"
    ) as HTMLElement | null;
    const dirty = this.isVisionDirty();
    if (saveBtn) saveBtn.disabled = !dirty;
    if (revertBtn) revertBtn.disabled = !dirty;
    if (statusEl && dirty) {
      statusEl.textContent = "Unsaved changes";
      statusEl.className = "vision-status dirty";
    } else if (statusEl && statusEl.classList.contains("dirty")) {
      statusEl.textContent = "";
      statusEl.className = "vision-status";
    }
  }

  private handleCompassUpdate(content: string): void {
    const textarea = document.getElementById(
      "vision-content"
    ) as HTMLTextAreaElement | null;
    const statusEl = document.getElementById(
      "vision-status"
    ) as HTMLElement | null;
    if (!textarea) {
      this.compassRemote = content;
      this.compassRemoteSeen = true;
      return;
    }

    const firstSnapshot = !this.compassRemoteSeen;
    const wasDirty = !firstSnapshot && this.isVisionDirty();
    const previousRemote = this.compassRemote;
    this.compassRemote = content;
    this.compassRemoteSeen = true;

    if (firstSnapshot || !wasDirty) {
      // Safe to overwrite — user has nothing in flight.
      textarea.value = content;
      this.refreshVisionDirtyState();
      return;
    }

    // User has unsaved edits. Don't clobber. Surface the conflict.
    if (statusEl && content !== previousRemote) {
      statusEl.textContent =
        "File changed on disk while you were editing — Save will overwrite, Revert will discard your edits.";
      statusEl.className = "vision-status conflict";
    }
    // Save/Revert button states still reflect dirtiness vs the new remote.
    this.refreshVisionDirtyState();
  }

  private async saveVision(): Promise<void> {
    const textarea = document.getElementById(
      "vision-content"
    ) as HTMLTextAreaElement;
    const statusEl = document.getElementById(
      "vision-status"
    ) as HTMLElement | null;
    const content = textarea.value;
    try {
      const res = await fetch("/api/compass", {
        method: "POST",
        headers: this.apiHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({ content }),
      });
      if (!res.ok) {
        if (statusEl) {
          statusEl.textContent = `Save failed (${res.status})`;
          statusEl.className = "vision-status error";
        }
        return;
      }
      this.compassRemote = content;
      this.refreshVisionDirtyState();
      if (statusEl) {
        const time = new Date().toLocaleTimeString();
        statusEl.textContent = `Saved at ${time}`;
        statusEl.className = "vision-status saved";
      }
    } catch (error) {
      console.error("Failed to save vision:", error);
      if (statusEl) {
        statusEl.textContent = "Save failed (network error)";
        statusEl.className = "vision-status error";
      }
    }
  }

  private connectWebSocket(): void {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws?t=${encodeURIComponent(this.token)}`;

    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      this.reconnectAttempts = 0;
      this.updateConn("connected", "Connected");
    };

    this.ws.onmessage = (event) => {
      try {
        const data: WsMessage = JSON.parse(event.data as string);
        this.handleMessage(data);
      } catch (error) {
        console.error("Failed to parse WebSocket message:", error);
      }
    };

    this.ws.onclose = () => {
      this.updateConn("error", "Disconnected");
      this.scheduleReconnect();
    };

    this.ws.onerror = () => {
      this.updateConn("error", "Connection error");
    };
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.updateConn("error", "Connection failed");
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(1.5, this.reconnectAttempts - 1);

    setTimeout(() => {
      this.updateConn("error", `Reconnecting (${this.reconnectAttempts})...`);
      this.connectWebSocket();
    }, delay);
  }

  private updateConn(
    state: "connected" | "running" | "error",
    text: string
  ): void {
    const indicator = document.getElementById("status-indicator")!;
    const textEl = document.getElementById("status-text")!;

    indicator.className = `indicator ${state}`;
    textEl.textContent = text;
  }

  private handleMessage(msg: WsMessage): void {
    switch (msg.kind) {
      case "output":
        this.handleOutputEvent(msg.event);
        break;
      case "state":
        this.renderState(msg.state);
        break;
      case "drafts":
        this.renderDrafts(msg.content);
        break;
      case "feedback":
        this.renderMarkdownInto(
          "feedback-content",
          msg.content,
          "No pending feedback."
        );
        break;
      case "lessons":
        this.renderMarkdownInto(
          "lessons-content",
          msg.content,
          "No lessons recorded yet."
        );
        break;
      case "compass":
        this.handleCompassUpdate(msg.content);
        break;
      case "status":
        this.renderStatus(msg.status);
        break;
      case "sessions":
        this.renderSessions(msg.sessions, msg.priorRunsCount);
        break;
    }
  }

  private handleOutputEvent(event: OutputEvent): void {
    const logEl = document.getElementById("activity-log")!;
    const entry = document.createElement("div");
    entry.className = `log-entry ${event.type}`;

    switch (event.type) {
      case "session":
        entry.textContent = `Session ${event.data}`;
        break;
      case "phase":
        entry.textContent = `── ${event.data} ──`;
        break;
      case "tool": {
        const agent = event.metadata?.agent || "Agent";
        const summary = event.metadata?.summary as string | undefined;
        const full = event.metadata?.full as Record<string, string> | undefined;

        if (summary) {
          entry.classList.add("tool-collapsible");

          const header = document.createElement("span");
          header.className = "tool-header";
          header.textContent = `[${agent} → ${event.data}] `;

          const summarySpan = document.createElement("span");
          summarySpan.className = "tool-summary";
          summarySpan.textContent = summary;

          entry.appendChild(header);
          entry.appendChild(summarySpan);

          if (full && Object.keys(full).length > 0) {
            const toggle = document.createElement("span");
            toggle.className = "tool-toggle";
            toggle.textContent = " +";
            entry.appendChild(toggle);

            const details = document.createElement("div");
            details.className = "tool-full";
            for (const [key, value] of Object.entries(full)) {
              const row = document.createElement("div");
              row.className = "tool-full-row";
              const keySpan = document.createElement("span");
              keySpan.className = "tool-full-key";
              keySpan.textContent = key + ": ";
              const valSpan = document.createElement("span");
              valSpan.className = "tool-full-value";
              valSpan.textContent = value;
              row.appendChild(keySpan);
              row.appendChild(valSpan);
              details.appendChild(row);
            }
            entry.appendChild(details);

            entry.addEventListener("click", () => {
              const expanded = entry.classList.toggle("expanded");
              toggle.textContent = expanded ? " −" : " +";
            });
          }
        } else {
          entry.textContent = `[${agent} → ${event.data}]`;
        }
        break;
      }
      case "agent_start": {
        const ctx = event.metadata?.context ? `: ${event.metadata.context}` : "";
        entry.textContent = `▶ ${event.data} Agent${ctx}`;
        break;
      }
      case "agent_complete": {
        const status = event.metadata?.status ? ` (${event.metadata.status})` : "";
        entry.textContent = `✓ ${event.data} Agent${status}`;
        break;
      }
      case "commit":
        entry.textContent = `✓ Committed: ${event.data.slice(0, 7)}`;
        break;
      case "error":
        entry.textContent = `✗ ${event.data}`;
        break;
      case "info":
        entry.textContent = event.data;
        break;
      case "log": {
        const block = document.createElement("div");
        block.className = "markdown-block";
        block.appendChild(renderMarkdown(event.data));
        entry.appendChild(block);
        break;
      }
      default:
        entry.textContent = event.data;
    }

    logEl.appendChild(entry);

    if (this.autoScroll && this.currentTab === "activity") {
      const panel = document.getElementById("activity-panel")!;
      panel.scrollTop = panel.scrollHeight;
    }
  }

  private setupAutoScroll(): void {
    const panel = document.getElementById("activity-panel")!;

    panel.addEventListener("scroll", () => {
      const isAtBottom =
        panel.scrollHeight - panel.scrollTop - panel.clientHeight < 50;
      this.autoScroll = isAtBottom;
    });
  }
}

document.addEventListener("DOMContentLoaded", () => {
  new CompassApp();
});
