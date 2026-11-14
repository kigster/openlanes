import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetSession } from "./client";
import { confirmCommand, confirmInterview, fetchInterview, interviewPath, mergeTurns, openQuestion, pendingDecision, sendInterview, settle, withTurn } from "./interview";
import type { InterviewTurn } from "./types";

const turn = (id: string, over: Partial<InterviewTurn> = {}): InterviewTurn => ({ id, from: "unblocker", kind: "text", text: id, at: `2026-11-13T00:00:0${id.length}Z`, ...over });

afterEach(() => vi.restoreAllMocks());

it("addresses one question's interview", () => {
  expect(interviewPath("068.00", 2)).toBe("/api/plans/068.00/questions/2/interview");
});

it("adds a turn once, in order", () => {
  const a = turn("a");
  const b = turn("bb", { from: "you" });
  const both = withTurn([a], b);
  expect(both.map(t => t.id)).toEqual(["a", "bb"]);
  expect(withTurn(both, b)).toBe(both);
});

it("lays a fetch over the held turns without losing a streamed one", () => {
  const a = turn("a");
  const streamed = turn("bb");
  expect(mergeTurns([a, streamed], [a]).map(t => t.id)).toEqual(["a", "bb"]);
  expect(mergeTurns(undefined, [a])).toEqual([a]);
});

it("knows what the unblocker is waiting on", () => {
  const q = turn("q", { kind: "question", options: [{ label: "yes", recommended: true }, { label: "no", recommended: false }] });
  const d = turn("dd", { kind: "decision", answer: "a) yes" });
  expect(openQuestion([q])).toBe(q);
  expect(pendingDecision([q])).toBeNull();
  expect(pendingDecision([q, d])).toBe(d);
  expect(openQuestion([q, turn("you", { from: "you" })])).toBeNull();
});

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const session = { csrf: "tok-1", node: {}, repo: "github.com/example-org/example-repo" };

describe("the wire calls", () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    resetSession();
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("reads the conversation so far", async () => {
    const a = turn("a");
    fetchMock.mockResolvedValueOnce(json(200, { turns: [a] }));
    await expect(fetchInterview("068.00", 2)).resolves.toEqual([a]);
    expect(fetchMock).toHaveBeenCalledWith("/api/plans/068.00/questions/2/interview", expect.objectContaining({ credentials: "same-origin" }));
  });

  it("reads an answer with no turns as an empty conversation", async () => {
    fetchMock.mockResolvedValueOnce(json(200, {}));
    await expect(fetchInterview("068.00", 2)).resolves.toEqual([]);
  });

  it("rejects when the conversation cannot be read", async () => {
    fetchMock.mockResolvedValueOnce(json(404, {}));
    await expect(fetchInterview("068.00", 2)).rejects.toMatchObject({ name: "ApiError", status: 404 });
  });

  it("sends a reply with the session's token and returns the stored turn", async () => {
    const stored = turn("u1", { from: "you", text: "skip it" });
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(202, { turn: stored }));
    await expect(sendInterview("068.00", 2, "skip it")).resolves.toEqual(stored);
    const [path, init] = fetchMock.mock.calls[1];
    expect(path).toBe("/api/plans/068.00/questions/2/interview");
    expect(init.headers["X-CSRF-Token"]).toBe("tok-1");
    expect(JSON.parse(init.body)).toMatchObject({ text: "skip it", id: expect.any(String) });
  });

  it.each([422, 409])("rejects with the server's reason on a %i", async status => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(status, { error: "the unblocker is still answering" }));
    await expect(sendInterview("068.00", 2, "hi")).rejects.toMatchObject({ message: "the unblocker is still answering", status });
  });

  it("rejects with the status when the server gives no reason", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(500, {}));
    await expect(sendInterview("068.00", 2, "hi")).rejects.toMatchObject({ message: "POST /api/plans/068.00/questions/2/interview answered 500", status: 500 });
  });

  it("confirms a decision through the command gate", async () => {
    expect(confirmCommand("068.00", 2, "t3")).toEqual({ kind: "confirm_interview", plan: "068.00", agent: null, payload: { question: "2", turn: "t3" } });
    const reply = { id: "x", status: "done", reason: null, at: "t" };
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(202, reply));
    await expect(confirmInterview("068.00", 2, "t3")).resolves.toEqual(reply);
    const [path, init] = fetchMock.mock.calls[1];
    expect(path).toBe("/api/commands");
    expect(JSON.parse(init.body)).toMatchObject({ kind: "confirm_interview", plan: "068.00", payload: { question: "2", turn: "t3" } });
  });
});

it("orders turns by time, then by id, whatever order they arrive in", () => {
  const at = "2026-11-13T00:00:05Z";
  const turns = [turn("c", { at }), turn("a", { at }), turn("z", { at: "2026-11-13T00:00:01Z" }), turn("a", { at, text: "again" })];
  expect(settle(turns).map(t => t.id)).toEqual(["z", "a", "c"]);
});
