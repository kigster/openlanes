// The second machine's page in the chat spec (plan 006, I1), held open from Cypress's Node process. A server counts a
// page as present only while its `GET /api/events?page=` stream is open (Live::Chat answers `absent` otherwise), and
// cy.request cannot hold a stream open, so these tasks do: open it, read the `chat` events it relays, close it.
import http from "node:http";

/** One `event: chat` the second machine's server relayed to its page. */
export type PeerEvent = { kind: string; [field: string]: unknown };

interface Stream {
  request: http.ClientRequest;
  events: PeerEvent[];
}

const streams = new Map<string, Stream>();

/** Splits server-sent events out of a growing buffer, keeping `chat` ones, and returns what is left unparsed. */
const parse = (buffer: string, into: PeerEvent[]): string => {
  const frames = buffer.split("\n\n");
  const rest = frames.pop() ?? "";
  for (const frame of frames) {
    const lines = frame.split("\n");
    const event = lines.find((l) => l.startsWith("event: "))?.slice(7);
    const data = lines.find((l) => l.startsWith("data: "))?.slice(6);
    if (event === "chat" && data) into.push(JSON.parse(data) as PeerEvent);
  }
  return rest;
};

export const peerTasks = {
  /** Opens the page's event stream on the second server; resolves once its `chat_cursor` says relaying has begun. */
  peerOpen({ url, page }: { url: string; page: string }): Promise<null> {
    return new Promise((resolve, reject) => {
      const events: PeerEvent[] = [];
      let buffer = "";
      let heard = "";
      let ready = false;
      const request = http.get(`${url}/api/events?page=${encodeURIComponent(page)}`, { headers: { Accept: "text/event-stream" } }, (response) => {
        response.setEncoding("utf8");
        response.on("data", (chunk: string) => {
          buffer = parse(buffer + chunk, events);
          if (!ready) heard += chunk;
          if (!ready && heard.includes("event: chat_cursor")) {
            ready = true;
            resolve(null);
          }
        });
      });
      request.on("error", (error) => (ready ? undefined : reject(error)));
      streams.set(page, { request, events });
    });
  },

  /** The `chat` events relayed to the page so far. */
  peerEvents(page: string): PeerEvent[] {
    return streams.get(page)?.events ?? [];
  },

  /** Closes the page's stream, as a closed tab would. */
  peerClose(page: string): null {
    streams.get(page)?.request.destroy();
    streams.delete(page);
    return null;
  },
};

/** Closes every stream still open, so no request outlives the run. */
export const closePeers = (): void => {
  for (const page of [...streams.keys()]) peerTasks.peerClose(page);
};
