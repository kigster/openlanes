import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetSession } from "./client";
import { confirmCommand, confirmInterview, fetchInterview, interviewPath, mergeTurns, openQuestion, pendingDecision, sendInterview, settle, withTurn } from "./interview";
import type { InterviewTurn } from "./types";

const turn = (id: string, over: Partial<InterviewTurn> = {}): InterviewTurn => ({ id, from: "unblocker", kind: "text", text: id, at: `2026-11-13T00:00:0${id.length}Z`, seq: `${id.length}-0`, ...over });

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
    await expect(fetchInterview("068.00", 2)).rejects.toMatchObject({ name: "ApiError", status: 404, message: "GET /api/plans/068.00/questions/2/interview answered 404" });
  });

  it("rejects with the server's reason when the question is no longer open", async () => {
    fetchMock.mockResolvedValueOnce(json(409, { error: "plan 068.00 has no open question 2 to talk through" }));
    await expect(fetchInterview("068.00", 2)).rejects.toMatchObject({ status: 409, message: "plan 068.00 has no open question 2 to talk through" });
  });

  it("rejects with the status when a refusal carries no JSON", async () => {
    fetchMock.mockResolvedValueOnce(new Response("<html>", { status: 409 }));
    await expect(fetchInterview("068.00", 2)).rejects.toMatchObject({ status: 409, message: "GET /api/plans/068.00/questions/2/interview answered 409" });
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

// Issue 252. The server's stream id is the only order there is: `at` is whole seconds and ids are random.
describe("the order turns are drawn in", () => {
  const at = "2026-11-13T00:00:05Z";

  it("is the server's, whatever order they arrive in and whatever their times and ids say", () => {
    const turns = [
      turn("c", { at, seq: "1794700000002-0" }),
      turn("z", { at: "2026-11-13T00:00:09Z", seq: "1794700000001-0" }),
      turn("a", { at, seq: "1794700000002-1" }),
      turn("a", { at, seq: "1794700000002-1", text: "again" }),
    ];
    expect(settle(turns).map(t => t.id)).toEqual(["z", "c", "a"]);
  });

  it("keeps a reply's words before its decision when both carry one second, so Confirm is drawn", () => {
    // The decision's id sorts first, as a random id does half the time; by time and id the words came out last.
    const words = turn("uZZZZZZZZZZZZ", { at, seq: "1794700000000-0" });
    const decision = turn("uAAAAAAAAAAAA", { at, kind: "decision", answer: "Rebase onto main", seq: "1794700000000-1" });
    for (const arrival of [[words, decision], [decision, words]]) {
      const drawn = settle(arrival);
      expect(drawn.map(t => t.kind)).toEqual(["text", "decision"]);
      expect(pendingDecision(drawn)).toBe(decision);
    }
    expect(pendingDecision(withTurn([decision], words))).toBe(decision);
    expect(pendingDecision(mergeTurns([decision], [words]))).toBe(decision);
  });

  it("keeps a reply's words before its question, for any ids", () => {
    const options = [{ label: "yes", recommended: true }, { label: "no", recommended: false }];
    for (let i = 0; i < 200; i++) {
      const id = () => `u${Math.random().toString(36).slice(2, 14)}`;
      const words = turn(id(), { at, seq: "1794700000000-0" });
      const question = turn(id(), { at, kind: "question", options, seq: "1794700000000-1" });
      expect(openQuestion(settle([question, words]))).toBe(question);
    }
  });

  it("reads the place as numbers, not as text", () => {
    const turns = [turn("late", { seq: "10-0" }), turn("early", { seq: "9-0" }), turn("mid", { seq: "9-10" }), turn("first", { seq: "9-2" })];
    expect(settle(turns).map(t => t.id)).toEqual(["early", "first", "mid", "late"]);
  });

  it("puts a turn with no place first, in the order it arrived, without throwing", () => {
    const bare = { ...turn("bare"), seq: undefined } as unknown as InterviewTurn;
    const odd = turn("odd", { seq: "soon" });
    expect(settle([turn("a", { seq: "5-0" }), bare, odd]).map(t => t.id)).toEqual(["bare", "odd", "a"]);
  });
});
