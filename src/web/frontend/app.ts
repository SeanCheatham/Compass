interface OutputEvent {
  type: string;
  timestamp: number;
  data: string;
  metadata?: Record<string, unknown>;
}

interface PlanNext {
  plan: string;
  verify: string;
}

interface PlanState {
  completed: string[];
  next: PlanNext | null;
  followUp: string;
}

class CompassApp {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelay = 1000;
  private autoScroll = true;
  private currentTab = "activity";

  constructor() {
    this.init();
  }

  private async init(): Promise<void> {
    this.setupTabs();

    await Promise.all([
      this.loadState(),
      this.loadDrafts(),
      this.loadFeedback(),
    ]);

    this.setupDraftForm();
    this.connectWebSocket();
    this.setupAutoScroll();

    setInterval(() => {
      this.loadState();
      this.loadDrafts();
      this.loadFeedback();
    }, 2000);
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
        li.textContent = c;
        ul.appendChild(li);
      }
      el.appendChild(ul);
    }

    el.appendChild(this.makeHeading("Next"));
    if (state.next) {
      const pre = document.createElement("pre");
      pre.className = "text-block";
      pre.textContent = state.next.plan;
      el.appendChild(pre);

      const verifyRow = document.createElement("div");
      verifyRow.className = "verify-row";
      const verifyLabel = document.createElement("span");
      verifyLabel.className = "verify-label";
      verifyLabel.textContent = "verify";
      const verifyCmd = document.createElement("code");
      verifyCmd.className = "verify-cmd";
      verifyCmd.textContent = state.next.verify;
      verifyRow.appendChild(verifyLabel);
      verifyRow.appendChild(verifyCmd);
      el.appendChild(verifyRow);
    } else {
      el.appendChild(this.makeEmpty("No next plan. Add a draft to get started."));
    }

    el.appendChild(this.makeHeading("Follow-up"));
    if (state.followUp.trim()) {
      const pre = document.createElement("pre");
      pre.className = "text-block";
      pre.textContent = state.followUp;
      el.appendChild(pre);
    } else {
      el.appendChild(this.makeEmpty("No follow-up sketched."));
    }
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

  private async loadState(): Promise<void> {
    try {
      const res = await fetch("/api/state");
      const data = (await res.json()) as PlanState;
      this.renderState(data);
    } catch (error) {
      console.error("Failed to load state:", error);
    }
  }

  private async loadDrafts(): Promise<void> {
    try {
      const res = await fetch("/api/drafts");
      const data = (await res.json()) as { content: string };
      const badge = document.getElementById("drafts-badge")!;

      const lines = data.content
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l.length > 0);

      badge.textContent = lines.length > 0 ? String(lines.length) : "";

      this.renderText("drafts-content", data.content, "No pending drafts.");
    } catch (error) {
      console.error("Failed to load drafts:", error);
    }
  }

  private async loadFeedback(): Promise<void> {
    try {
      const res = await fetch("/api/feedback");
      const data = (await res.json()) as { content: string };
      this.renderText(
        "feedback-content",
        data.content,
        "No pending feedback."
      );
    } catch (error) {
      console.error("Failed to load feedback:", error);
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
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
      });

      if (res.ok) {
        textarea.value = "";
        await this.loadDrafts();
      }
    } catch (error) {
      console.error("Failed to submit draft:", error);
    }
  }

  private connectWebSocket(): void {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws`;

    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      this.reconnectAttempts = 0;
      this.updateStatus("connected", "Connected");
    };

    this.ws.onmessage = (event) => {
      try {
        const data: OutputEvent = JSON.parse(event.data as string);
        this.handleEvent(data);
      } catch (error) {
        console.error("Failed to parse WebSocket message:", error);
      }
    };

    this.ws.onclose = () => {
      this.updateStatus("error", "Disconnected");
      this.scheduleReconnect();
    };

    this.ws.onerror = () => {
      this.updateStatus("error", "Connection error");
    };
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.updateStatus("error", "Connection failed");
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(1.5, this.reconnectAttempts - 1);

    setTimeout(() => {
      this.updateStatus("error", `Reconnecting (${this.reconnectAttempts})...`);
      this.connectWebSocket();
    }, delay);
  }

  private updateStatus(
    state: "connected" | "running" | "error",
    text: string
  ): void {
    const indicator = document.getElementById("status-indicator")!;
    const textEl = document.getElementById("status-text")!;

    indicator.className = `indicator ${state}`;
    textEl.textContent = text;
  }

  private handleEvent(event: OutputEvent): void {
    const logEl = document.getElementById("activity-log")!;
    const entry = document.createElement("div");
    entry.className = `log-entry ${event.type}`;

    switch (event.type) {
      case "session":
        entry.textContent = `Session ${event.data}`;
        this.updateStatus("running", `Session ${event.data}`);
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
      case "log":
        entry.textContent = event.data;
        break;
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
