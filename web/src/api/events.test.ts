import type { FetchEventSourceInit } from "@microsoft/fetch-event-source";
import { OFFLINE_AFTER, backoff, openStream } from "./events";

const calls: FetchEventSourceInit[] = [];
let settle: { reject: (e: unknown) => void } | null = null;
vi.mock("@microsoft/fetch-event-source", () => ({
  fetchEventSource: (_url: string, init: FetchEventSourceInit) => {
    calls.push(init);
    return new Promise((_resolve, reject) => {
      settle = { reject };
    });
  },
}));

const handlers = () => ({ onBoard: vi.fn(), onReply: vi.fn(), onState: vi.fn(), onReconnect: vi.fn() });
const ok = () => new Response("", { status: 200, headers: { "content-type": "text/event-stream" } });

beforeEach(() => {
  calls.length = 0;
});

it("backs off 1 s, 2 s, 4 s, capped at 30 s", () => {
  expect([0, 1, 2, 3].map(backoff)).toEqual([1000, 1000, 2000, 4000]);
  expect(backoff(20)).toBe(30_000);
});

it("routes board and reply events", () => {
  const h = handlers();
  openStream(h);
  const init = calls[0];
  init.onmessage?.({ id: "", event: "board", data: '{"me":1}', retry: undefined });
  init.onmessage?.({ id: "", event: "reply", data: '{"id":"a"}', retry: undefined });
  init.onmessage?.({ id: "", event: "other", data: "{}", retry: undefined });
  init.onmessage?.({ id: "", event: "board", data: "", retry: undefined });
  expect(h.onBoard).toHaveBeenCalledWith({ me: 1 });
  expect(h.onReply).toHaveBeenCalledWith({ id: "a" });
  expect(h.onBoard).toHaveBeenCalledTimes(1);
});

it("routes copilot turns to their handler, and passes them over when there is none", () => {
  const h = { ...handlers(), onCopilot: vi.fn() };
  openStream(h);
  calls[0].onmessage?.({ id: "", event: "copilot", data: '{"id":"01J.1"}', retry: undefined });
  expect(h.onCopilot).toHaveBeenCalledWith({ id: "01J.1" });
  openStream(handlers());
  expect(() => calls[1].onmessage?.({ id: "", event: "copilot", data: "{}", retry: undefined })).not.toThrow();
});

it("passes over the opening cursor event, whose id the library keeps for Last-Event-ID", () => {
  const h = handlers();
  openStream(h);
  calls[0].onmessage?.({ id: "0-0", event: "cursor", data: '{"id":"0-0"}', retry: undefined });
  expect([h.onBoard, h.onReply, h.onState, h.onReconnect].map(f => f.mock.calls.length)).toEqual([0, 0, 0, 0]);
});

it("goes live on open and refetches on every reopen", async () => {
  const h = handlers();
  openStream(h);
  const init = calls[0];
  await init.onopen?.(ok());
  expect(h.onState).toHaveBeenLastCalledWith("live");
  expect(h.onReconnect).not.toHaveBeenCalled();
  expect(init.onerror?.(new Error("drop"))).toBe(1000);
  expect(h.onState).toHaveBeenLastCalledWith("reconnecting");
  await init.onopen?.(ok());
  expect(h.onReconnect).toHaveBeenCalledTimes(1);
});

it("refuses a non-stream answer, and says offline after repeated failures", async () => {
  const h = handlers();
  openStream(h);
  const init = calls[0];
  await expect(init.onopen?.(new Response("", { status: 502 }))).rejects.toThrow("answered 502");
  await expect(init.onopen?.(new Response("", { status: 200 }))).rejects.toThrow();
  for (let i = 0; i < OFFLINE_AFTER; i++) init.onerror?.(new Error("down"));
  expect(h.onState).toHaveBeenLastCalledWith("offline");
});

it("treats a closed stream as a drop, and closes for good when asked", () => {
  const h = handlers();
  const close = openStream(h);
  const init = calls[0];
  expect(() => init.onclose?.()).toThrow("stream closed");
  close();
  expect(init.signal?.aborted).toBe(true);
  settle?.reject(new Error("aborted"));
});
