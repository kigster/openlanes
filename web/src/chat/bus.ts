// Chat events arrive on the board's one stream (useBoard), and the chat's state lives in useChat; this carries them
// across. `opened` is the stream's `chat_cursor`: from then on every event for this page is relayed, so a read of
// `GET /api/chat` begun then misses nothing. It comes on every open, a reconnect included; what was said while the
// stream was down is gone (D2), but who is in the chat and which invites are open is read again.
import type { ChatEvent } from "../api/types";

type Listener = { event(e: ChatEvent): void; opened(): void };

export class ChatBus {
  private listeners = new Set<Listener>();
  private open = false;

  /** Whether the stream has opened at least once: a listener that arrives late reads the chat at once. */
  get isOpen(): boolean {
    return this.open;
  }

  listen(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  deliver(event: ChatEvent): void {
    this.listeners.forEach(l => l.event(event));
  }

  opened(): void {
    this.open = true;
    this.listeners.forEach(l => l.opened());
  }
}

export const chatBus = new ChatBus();
