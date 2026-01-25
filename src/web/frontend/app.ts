import { marked } from "marked";

// Configure marked for safe rendering
marked.setOptions({
  gfm: true,
  breaks: true,
});

interface OutputEvent {
  type: string;
  timestamp: number;
  data: string;
  metadata?: Record<string, unknown>;
}

interface Plan {
  id: string;
  content: string;
  status: "pending" | "completed";
  commit: string | null;
}

interface PlansResponse {
  plans: Plan[];
  summary: {
    total: number;
    completed: number;
    pending: number;
  };
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
    // Set up tab switching
    this.setupTabs();

    // Load initial data
    await Promise.all([
      this.loadCompass(),
      this.loadPlans(),
      this.loadNotes(),
    ]);

    // Connect WebSocket
    this.connectWebSocket();

    // Set up auto-scroll detection
    this.setupAutoScroll();

    // Poll for state changes (plans, notes) every 2 seconds
    setInterval(() => {
      this.loadPlans();
      this.loadNotes();
    }, 2000);
  }

  private setupTabs(): void {
    const tabs = document.querySelectorAll(".tab");
    tabs.forEach(tab => {
      tab.addEventListener("click", () => {
        const tabName = (tab as HTMLElement).dataset.tab;
        if (tabName) {
          this.switchTab(tabName);
        }
      });
    });
  }

  private switchTab(tabName: string): void {
    this.currentTab = tabName;

    // Update tab buttons
    document.querySelectorAll(".tab").forEach(tab => {
      tab.classList.toggle("active", (tab as HTMLElement).dataset.tab === tabName);
    });

    // Update panels
    document.querySelectorAll(".panel").forEach(panel => {
      panel.classList.toggle("active", panel.id === `${tabName}-panel`);
    });
  }

  private async loadCompass(): Promise<void> {
    try {
      const res = await fetch("/api/compass");
      const data = await res.json() as { content: string };
      const el = document.getElementById("compass-content")!;
      if (data.content) {
        el.innerHTML = marked.parse(data.content) as string;
        el.classList.add("markdown-body");
      } else {
        el.innerHTML = '<span class="empty">No COMPASS.md content</span>';
        el.classList.remove("markdown-body");
      }
    } catch (error) {
      console.error("Failed to load COMPASS:", error);
    }
  }

  private async loadPlans(): Promise<void> {
    try {
      const res = await fetch("/api/plans");
      const data: PlansResponse = await res.json() as PlansResponse;

      // Update badge
      const badgeEl = document.getElementById("plans-badge")!;
      badgeEl.textContent = data.summary.pending > 0 ? `${data.summary.pending}` : "";

      const listEl = document.getElementById("plans-list")!;

      if (data.plans.length === 0) {
        listEl.innerHTML = '<li class="empty">No plans yet</li>';
        return;
      }

      listEl.innerHTML = data.plans.map(plan => `
        <li>
          <span class="plan-status ${plan.status}">${plan.status === "completed" ? "✓" : "○"}</span>
          <span class="plan-content">${this.escapeHtml(plan.content)}</span>
          ${plan.commit ? `<span class="plan-commit">${plan.commit.slice(0, 7)}</span>` : ""}
        </li>
      `).join("");
    } catch (error) {
      console.error("Failed to load plans:", error);
    }
  }

  private async loadNotes(): Promise<void> {
    try {
      const res = await fetch("/api/notes");
      const data = await res.json() as { content: string };
      const el = document.getElementById("notes-content")!;
      if (data.content) {
        el.innerHTML = marked.parse(data.content) as string;
        el.classList.add("markdown-body");
      } else {
        el.innerHTML = '<span class="empty">No notes yet</span>';
        el.classList.remove("markdown-body");
      }
    } catch (error) {
      console.error("Failed to load notes:", error);
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

  private updateStatus(state: "connected" | "running" | "error", text: string): void {
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
      case "tool":
        const agent = event.metadata?.agent || "Agent";
        entry.textContent = `[${agent} → ${event.data}]`;
        break;
      case "agent_start":
        const ctx = event.metadata?.context ? `: ${event.metadata.context}` : "";
        entry.textContent = `▶ ${event.data} Agent${ctx}`;
        break;
      case "agent_complete":
        const status = event.metadata?.status ? ` (${event.metadata.status})` : "";
        entry.textContent = `✓ ${event.data} Agent${status}`;
        break;
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
      const isAtBottom = panel.scrollHeight - panel.scrollTop - panel.clientHeight < 50;
      this.autoScroll = isAtBottom;
    });
  }

  private escapeHtml(text: string): string {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}

// Initialize app when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  new CompassApp();
});
