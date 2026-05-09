/**
 * In-memory holder for the most recent feedback string passed to Develop's
 * `complete()` MCP tool. Lives between the end of a Develop run and the start
 * of the next Plan run; cleared when Plan starts so the UI matches the same
 * "consumed once" semantics the old feedback.md file had.
 *
 * The web server subscribes via onChange to broadcast updates over WebSocket.
 */
export interface FeedbackBus {
  /** The feedback string currently held (empty when none). */
  current(): string;
  /** Set the feedback string. Emits a change event. */
  set(feedback: string): void;
  /** Clear the feedback. Emits a change event if the value changes. */
  clear(): void;
  /** Subscribe to changes. Returns an unsubscribe function. */
  onChange(fn: (feedback: string) => void): () => void;
}

class FeedbackBusImpl implements FeedbackBus {
  private value = "";
  private listeners = new Set<(feedback: string) => void>();

  current(): string {
    return this.value;
  }

  set(feedback: string): void {
    this.value = feedback;
    this.emit();
  }

  clear(): void {
    if (this.value === "") return;
    this.value = "";
    this.emit();
  }

  onChange(fn: (feedback: string) => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit(): void {
    for (const fn of this.listeners) fn(this.value);
  }
}

export function createFeedbackBus(): FeedbackBus {
  return new FeedbackBusImpl();
}
