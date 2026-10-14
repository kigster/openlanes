import type { ReactNode } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { COPILOT_KEY, createQueryClient } from "./queryClient";
import type { CopilotLog } from "./types";
import { reconcile, useBoard } from "./useBoard";
import { replies } from "./replies";
import type { StreamHandlers } from "./events";
import { loadFixtureBoard } from "./client";
import { useCopilot } from "../copilot/useCopilot";

const streams: StreamHandlers[] = [];
const closed = vi.fn();
vi.mock("./events", () => ({
  openStream: (h: StreamHandlers) => {
    streams.push(h);
    return closed;
  },
}));

const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={createQueryClient()}>{children}</QueryClientProvider>;
const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  streams.length = 0;
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.unstubAllGlobals();
  window.history.replaceState(null, "", "/");
});

it("loads the board, follows the stream, and refetches on reconnect", async () => {
  const first = loadFixtureBoard();
  fetchMock.mockResolvedValue(json(first));
  const { result, unmount } = renderHook(() => useBoard(), { wrapper });
  expect(result.current.isLoading).toBe(true);
  expect(result.current.connection).toBe("reconnecting");
  await waitFor(() => expect(result.current.board?.me.seq).toBe(first.me.seq));
  expect(result.current.fixture).toBe(false);

  const stream = streams[0];
  const next = { ...first, me: { ...first.me, seq: 99 } };
  act(() => {
    stream.onState("live");
    stream.onBoard(next);
  });
  expect(result.current.connection).toBe("live");
  expect(result.current.board?.me.seq).toBe(99);

  const deliver = vi.spyOn(replies, "deliver");
  stream.onReply({ id: "x", status: "done", reason: null, at: "t" });
  expect(deliver).toHaveBeenCalled();

  act(() => stream.onReconnect());
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  unmount();
  expect(closed).toHaveBeenCalled();
});

// The GET and the stream run at once. A turn the stream delivers while the GET is in flight, which that GET read too
// early to include, must survive the GET's answer.
it("keeps a copilot turn that arrives while the conversation's GET is in flight", async () => {
  const client = createQueryClient();
  let answer: (r: Response) => void = () => {};
  const older = { id: "01JA", from: "you", kind: "text", text: "earlier", at: "2026-10-13T09:00:00Z", usage: null } as const;
  fetchMock.mockImplementation((path: string) =>
    path === "/api/copilot" ? new Promise<Response>(resolve => (answer = resolve)) : Promise.resolve(json(loadFixtureBoard())),
  );
  const { result } = renderHook(() => (useBoard(), useCopilot()), {
    wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
  });
  await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/copilot", expect.anything()));
  const turn = { id: "01JB.1", from: "copilot", kind: "text", text: "late", at: "2026-10-13T09:00:05Z", usage: { model: "m", up: 9, down: 1 } } as const;
  act(() => streams[0].onCopilot?.(turn));
  await act(async () => answer(json({ turns: [older], usage: { model: null, up: 0, down: 0 } })));
  await waitFor(() => expect(result.current.log.turns.map(t => t.text)).toEqual(["earlier", "late"]));
  expect(result.current.log.usage).toEqual(turn.usage);
  act(() => streams[0].onCopilot?.(turn)); // the same turn again changes nothing
  expect(client.getQueryData<CopilotLog>(COPILOT_KEY)?.turns).toHaveLength(2);
});

// The stream's copilot_cursor is the boundary between what the GET reads and what the stream sends. A read made on
// reconnect, before that boundary is known, could miss a turn written in between; so only the cursor starts one.
it("reads the conversation when the stream names its copilot boundary, and not on a bare reconnect", () => {
  const client = createQueryClient();
  fetchMock.mockResolvedValue(json(loadFixtureBoard()));
  renderHook(() => useBoard(), { wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> });
  const refetch = vi.spyOn(client, "refetchQueries");
  act(() => streams[0].onReconnect());
  expect(refetch).not.toHaveBeenCalledWith({ queryKey: COPILOT_KEY });
  act(() => streams[0].onCopilotCursor?.());
  expect(refetch).toHaveBeenCalledWith({ queryKey: COPILOT_KEY });
});

// A GET sampled before the stream's boundary may miss a turn written between its read and the stream opening. The
// cursor's refetch cancels that GET (refetchQueries' cancelRefetch defaults to true) and reads again, past the boundary.
it("reads again past the copilot boundary when the first GET is still in flight", async () => {
  const client = createQueryClient();
  const answers: ((r: Response) => void)[] = [];
  fetchMock.mockImplementation((path: string) =>
    path === "/api/copilot" ? new Promise<Response>(resolve => answers.push(resolve)) : Promise.resolve(json(loadFixtureBoard())),
  );
  const { result } = renderHook(() => (useBoard(), useCopilot()), {
    wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
  });
  await waitFor(() => expect(answers).toHaveLength(1));
  act(() => streams[0].onCopilotCursor?.());
  await waitFor(() => expect(answers).toHaveLength(2));
  const missed = { id: "01JB", from: "you", kind: "text", text: "in between", at: "2026-10-13T09:00:05Z", usage: null } as const;
  const none = { model: null, up: 0, down: 0 };
  await act(async () => answers[0](json({ turns: [], usage: none })));
  await act(async () => answers[1](json({ turns: [missed], usage: none })));
  await waitFor(() => expect(result.current.log.turns.map(t => t.text)).toEqual(["in between"]));
});

it("reports a failed first load", async () => {
  fetchMock.mockResolvedValue(new Response("{}", { status: 500 }));
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false } });
  const { result } = renderHook(() => useBoard(), {
    wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
  });
  await waitFor(() => expect(result.current.error).toBeTruthy());
});

it("serves the fixture under ?fixture without a stream or a fetch", async () => {
  window.history.replaceState(null, "", "/?fixture");
  const { result } = renderHook(() => useBoard(), { wrapper });
  await waitFor(() => expect(result.current.board).toBeDefined());
  expect(result.current.fixture).toBe(true);
  expect(result.current.connection).toBe("live");
  expect(streams).toHaveLength(0);
  expect(fetchMock).not.toHaveBeenCalled();
});

describe("reconcile", () => {
  const at = (seq: number, others: number[] = []) => {
    const b = loadFixtureBoard();
    b.me.seq = seq;
    b.others = others.map((s, i) => ({ ...structuredClone(b.others[0]), seq: s, node: { ...b.others[0].node, id: `node-${i}` } }));
    return b;
  };

  it("never lets a lower seq replace a node's snapshot", () => {
    const old = at(10, [5, 7]);
    const next = at(9, [6, 3]);
    const merged = reconcile(old, next);
    expect(merged.me?.seq).toBe(10);
    expect(merged.others.map(s => s.seq)).toEqual([6, 7]);
  });

  it("keeps the old board when nothing is newer, drops nodes that left, and takes a different machine's board", () => {
    const old = at(10, [5]);
    expect(reconcile(old, at(10, [5]))).toBe(old);
    expect(reconcile(old, at(10, [])).others).toEqual([]);
    expect(reconcile(undefined, old)).toBe(old);
    const elsewhere = at(1);
    elsewhere.me.node.id = "another";
    expect(reconcile(old, elsewhere).me?.seq).toBe(1);
  });

  it("takes this machine's first snapshot over an empty board, and an empty one when the engine leaves", () => {
    const empty = { me: null, others: [] };
    const first = at(3);
    expect(reconcile(empty, first).me).toBe(first.me);
    expect(reconcile(first, empty).me).toBeNull();
  });
});

it("waits, with no board, until the engine publishes its first snapshot", async () => {
  fetchMock.mockResolvedValue(json({ me: null, others: [] }));
  const { result } = renderHook(() => useBoard(), { wrapper });
  await waitFor(() => expect(result.current.waiting).toBe(true));
  expect(result.current.board).toBeUndefined();
  act(() => streams[0].onBoard(loadFixtureBoard()));
  await waitFor(() => expect(result.current.board?.me.node.id).toBe(loadFixtureBoard().me.node.id));
  expect(result.current.waiting).toBe(false);
});

it("does not roll the board back when a reconnect GET lands after a newer streamed board", async () => {
  const first = loadFixtureBoard();
  first.me.seq = 40;
  let release: (r: Response) => void = () => {};
  fetchMock.mockResolvedValueOnce(json(first)).mockImplementationOnce(() => new Promise<Response>(r => (release = r)));
  const { result } = renderHook(() => useBoard(), { wrapper });
  await waitFor(() => expect(result.current.board?.me.seq).toBe(40));
  const stream = streams[0];
  act(() => stream.onReconnect()); // the GET leaves now, carrying seq 41
  act(() => stream.onBoard({ ...first, me: { ...first.me, seq: 42 } }));
  await act(async () => release(json({ ...first, me: { ...first.me, seq: 41 } })));
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  expect(result.current.board?.me.seq).toBe(42);
});

it("keeps a finished run finished when an older GET, still holding its last snapshot, lands after `me: null`", async () => {
  const first = loadFixtureBoard();
  let release: (r: Response) => void = () => {};
  fetchMock.mockResolvedValueOnce(json(first)).mockImplementationOnce(() => new Promise<Response>(r => (release = r)));
  const { result } = renderHook(() => useBoard(), { wrapper });
  await waitFor(() => expect(result.current.board?.me.seq).toBe(first.me.seq));
  const stream = streams[0];
  act(() => stream.onReconnect()); // the GET leaves now, and the server still has the run's last snapshot
  act(() => stream.onBoard({ me: null, others: first.others }));
  await act(async () => release(json(first)));
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  expect(result.current.waiting).toBe(true);
  expect(result.current.board).toBeUndefined();
});

it("ignores a GET whose fetch outlives its cancellation, answering from what the stream applied", async () => {
  const first = loadFixtureBoard();
  let release: (r: Response) => void = () => {};
  fetchMock.mockImplementationOnce(() => new Promise<Response>(r => (release = r)));
  const client = createQueryClient();
  const { result } = renderHook(() => useBoard(), {
    wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
  });
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
  const cancel = vi.spyOn(client, "cancelQueries");
  act(() => streams[0].onBoard({ me: null, others: [] }));
  expect(cancel).toHaveBeenCalledWith({ queryKey: ["board"] });
  await act(async () => release(json(first)));
  await waitFor(() => expect(result.current.waiting).toBe(true));
  expect(result.current.board).toBeUndefined();
});
