import { EMPTY_LOG, answers, asLog, mergeLogs, withTurn } from "./copilot";
import fixture from "./fixtures/copilot.json";
import type { CopilotLog, CopilotTurn } from "./types";

const log = fixture as CopilotLog;
const you: CopilotTurn = { id: "01JA", from: "you", kind: "text", text: "hi", at: "t", usage: null };
const said: CopilotTurn = { id: "01JA.1", from: "copilot", kind: "text", text: "hello", at: "t", usage: { model: "m", up: 5, down: 1 } };

it("has a fixture with one turn of every kind", () => {
  expect(new Set(log.turns.map(t => t.kind))).toEqual(new Set(["text", "confirm", "draft"]));
});

it("adds a turn once, taking a reply's usage as the log's", () => {
  const once = withTurn(withTurn(EMPTY_LOG, you), said);
  expect(once.turns.map(t => t.id)).toEqual(["01JA", "01JA.1"]);
  expect(once.usage).toEqual({ model: "m", up: 5, down: 1 });
  expect(withTurn(once, you)).toBe(once);
  expect(withTurn(once, { ...you, id: "01JB" }).usage).toEqual(once.usage); // the person's turn carries none
});

it("lays a fetched log over the held one without losing what the stream added", () => {
  const held = withTurn(withTurn(EMPTY_LOG, you), said);
  expect(mergeLogs(undefined, log)).toBe(log);
  const merged = mergeLogs(held, { turns: [you], usage: EMPTY_LOG.usage });
  expect(merged.turns.map(t => t.id)).toEqual(["01JA", "01JA.1"]);
});

it("knows which turns answer a message", () => {
  expect(answers(said, "01JA")).toBe(true);
  expect(answers(you, "01JA")).toBe(false);
  expect(answers(said, "01JAB")).toBe(false);
});

it("treats anything but a log as an empty one", () => {
  expect(asLog({ me: null, others: [] })).toBe(EMPTY_LOG);
  expect(asLog(null)).toBe(EMPTY_LOG);
  expect(asLog({ turns: [you] })).toEqual({ turns: [you], usage: EMPTY_LOG.usage });
  expect(asLog(log)).toEqual(log);
});
