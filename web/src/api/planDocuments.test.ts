import { describe, expect, it } from "vitest";
import { loadFixtureBoard } from "./client";
import { plansWithNewDocuments } from "./planDocuments";
import type { Car, Plan, PullRequest, Question, WireBoard } from "./types";

const board = (): WireBoard => loadFixtureBoard();
/** The board with its first plan changed by `change`. */
const withPlan = (change: (plan: Plan) => Partial<Plan>): { old: WireBoard; next: WireBoard; ordinal: string } => {
  const old = board();
  const [first, ...rest] = old.me!.plans;
  return { old, next: { ...old, me: { ...old.me!, plans: [{ ...first, ...change(first) }, ...rest] } }, ordinal: first.ordinal };
};

describe("plansWithNewDocuments", () => {
  it("names no plan for a first board, or while this machine has no snapshot", () => {
    expect(plansWithNewDocuments(undefined, board())).toEqual([]);
    expect(plansWithNewDocuments({ me: null, others: [] }, board())).toEqual([]);
    expect(plansWithNewDocuments(board(), { me: null, others: [] })).toEqual([]);
  });

  it("names no plan when only counters moved", () => {
    const { old, next } = withPlan(p => ({ cost: p.cost + 1, up: p.up + 500, elapsed: p.elapsed + 3 }));
    expect(plansWithNewDocuments(old, next)).toEqual([]);
  });

  it.each<[string, (plan: Plan) => Partial<Plan>]>([
    ["its status", p => ({ status: { ...p.status, key: `${p.status.key}-next` } })],
    ["its station", p => ({ station: `${p.station}-next` })],
    ["a question", p => ({ questions: [...p.questions, {} as Question] })],
    ["its pull request", p => ({ pr: p.pr ? null : ({ number: 7, state: "open" } as PullRequest) })],
    ["its pull request's state", p => ({ pr: { ...(p.pr ?? ({ number: 7 } as PullRequest)), state: "merged" } })],
    ["its agents", p => ({ cars: p.cars.length ? [] : [{ key: `${p.ordinal}/planner` } as Car] })],
  ])("names the plan that changed %s", (_what, change) => {
    const { old, next, ordinal } = withPlan(change);
    expect(plansWithNewDocuments(old, next)).toEqual([ordinal]);
  });

  it("names a plan the board did not have before", () => {
    const next = board();
    const old = { ...next, me: { ...next.me!, plans: next.me!.plans.slice(1) } };
    expect(plansWithNewDocuments(old, next)).toEqual([next.me!.plans[0].ordinal]);
  });

  it("ignores other machines' plans", () => {
    const old = board();
    const other = { ...old.me!, node: { ...old.me!.node, id: "other", me: false } };
    const moved = { ...other, plans: other.plans.map(p => ({ ...p, station: "elsewhere" })) };
    expect(plansWithNewDocuments({ ...old, others: [other] }, { ...old, others: [moved] })).toEqual([]);
  });
});
