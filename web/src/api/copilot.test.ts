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

// GET /api/copilot holds only the newest 100 turns. After a long session the page holds older ones too; a reconnect's
// fetch must not move those after the newest, nor let their old usage replace the current totals.
it("keeps a long conversation in order, and its newest usage, when a fetch holds only the newest turns", () => {
  const turn = (n: number, usage: CopilotTurn["usage"] = null): CopilotTurn => ({
    id: `01J${String(n).padStart(4, "0")}`, from: usage ? "copilot" : "you", kind: "text", text: `t${n}`,
    at: `2026-10-13T09:${String(Math.floor(n / 60)).padStart(2, "0")}:${String(n % 60).padStart(2, "0")}Z`, usage,
  } as CopilotTurn);
  const all = Array.from({ length: 150 }, (_, n) => turn(n, n % 2 ? { model: "m", up: n * 10, down: n } : null));
  const held: CopilotLog = { turns: all, usage: { model: "m", up: 1490, down: 149 } };
  const fetched: CopilotLog = { turns: all.slice(50), usage: { model: "m", up: 1490, down: 149 } };
  const merged = mergeLogs(held, fetched);
  expect(merged.turns.map(t => t.text)).toEqual(all.map(t => t.text));
  expect(merged.usage).toEqual({ model: "m", up: 1490, down: 149 });
  // A stream turn delivered after the fetch left lands in its place, and its usage becomes the header's.
  const late = turn(150, { model: "m", up: 9999, down: 999 });
  const withLate = mergeLogs({ turns: [...all, late], usage: late.usage! }, fetched);
  expect(withLate.turns.at(-1)).toBe(late);
  expect(withLate.usage).toEqual(late.usage);
  // An old turn arriving late goes before the newer ones and does not regress the usage.
  const old = turn(0, null);
  expect(withTurn({ turns: all.slice(1), usage: held.usage }, old).turns[0]).toBe(old);
  expect(withTurn(merged, turn(1, { model: "m", up: 1, down: 1 })).usage).toEqual(held.usage); // same id: kept as was
  expect(withTurn(merged, { ...turn(1, { model: "m", up: 1, down: 1 }), id: "01J0001b" } as CopilotTurn).usage).toEqual(held.usage);
});

it("falls back to the server's usage when no turn it has carries one", () => {
  expect(mergeLogs(EMPTY_LOG, { turns: [you], usage: { model: "m", up: 7, down: 1 } }).usage).toEqual({ model: "m", up: 7, down: 1 });
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
