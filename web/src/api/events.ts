// The event stream (contract.md, `GET /api/events`) through @microsoft/fetch-event-source, which reconnects after a
// dropped connection instead of giving up the way a bare EventSource does on a non-200.
import { fetchEventSource, type EventSourceMessage } from "@microsoft/fetch-event-source";
import type { ChatEvent, CopilotTurn, Reply, WireBoard } from "./types";

export type ConnectionState = "live" | "reconnecting" | "offline";

export interface StreamHandlers {
  onBoard(board: WireBoard): void;
  onReply(reply: Reply): void;
  /** A turn of the copilot conversation (W17). Carries no id, so it never moves the reply cursor. */
  onCopilot?(turn: CopilotTurn): void;
  /**
   * The stream's boundary in the copilot conversation: every turn after it comes as `onCopilot`, so a read of
   * `GET /api/copilot` started now covers the rest. Sent on every open, so it also stands for a reconnect.
   */
  onCopilotCursor?(): void;
  /** What happened in the chat between machines (plan 006). No id either: the chat keeps no history. */
  onChat?(event: ChatEvent): void;
  /** The stream is relaying this page's chat from here on: a read of `GET /api/chat` started now misses nothing. */
  onChatCursor?(): void;
  onState(state: ConnectionState): void;
  /** Called on every open after the first: whatever happened while the stream was down is fetched once. */
  onReconnect(): void;
}

/** After this many failed attempts in a row the header says offline rather than reconnecting. It still retries. */
export const OFFLINE_AFTER = 4;

/** 1 s, 2 s, 4 s … capped at 30 s. */
export const backoff = (attempt: number): number => Math.min(30_000, 1000 * 2 ** Math.max(0, attempt - 1));

class Retry extends Error {}

/** Opens the stream; the returned function closes it for good. */
export function openStream(handlers: StreamHandlers, url = "/api/events"): () => void {
  const controller = new AbortController();
  let opened = false;
  let failures = 0;

  void fetchEventSource(url, {
    signal: controller.signal,
    openWhenHidden: true,
    headers: { Accept: "text/event-stream" },
    async onopen(res) {
      if (!res.ok || !(res.headers.get("content-type") ?? "").includes("text/event-stream")) {
        throw new Retry(`GET ${url} answered ${res.status}`);
      }
      failures = 0;
      handlers.onState("live");
      if (opened) handlers.onReconnect();
      opened = true;
    },
    onmessage(message: EventSourceMessage) {
      if (!message.data) return;
      // `cursor` opens every stream only so its `id:` becomes the Last-Event-ID a reconnect sends; the library keeps
      // that id itself, so the event needs nothing from here, and like any other name it falls through.
      if (message.event === "board") handlers.onBoard(JSON.parse(message.data) as WireBoard);
      else if (message.event === "reply") handlers.onReply(JSON.parse(message.data) as Reply);
      else if (message.event === "copilot") handlers.onCopilot?.(JSON.parse(message.data) as CopilotTurn);
      else if (message.event === "copilot_cursor") handlers.onCopilotCursor?.();
      else if (message.event === "chat") handlers.onChat?.(JSON.parse(message.data) as ChatEvent);
      else if (message.event === "chat_cursor") handlers.onChatCursor?.();
    },
    onclose() {
      // The server closed a stream that should never end (a restart): treat it like any other drop.
      throw new Retry("stream closed");
    },
    onerror() {
      failures += 1;
      handlers.onState(failures >= OFFLINE_AFTER ? "offline" : "reconnecting");
      return backoff(failures);
    },
  }).catch(() => {
    // Only an abort ends the loop above, since onerror never throws; nothing to report.
  });

  return () => controller.abort();
}
