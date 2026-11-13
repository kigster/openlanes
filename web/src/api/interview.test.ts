import { afterEach, expect, it, vi } from "vitest";
import { interviewPath, mergeTurns, openQuestion, pendingDecision, withTurn } from "./interview";
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
