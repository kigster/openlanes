import { LAYOUTS, NODE_HEIGHT, NODE_WIDTH, around, arrange, exit, flowOf, isLayout, straight, type LayoutKey } from "./layouts";
import { graph } from "./fixture";
import { groups } from "./model";
import type { DependencyPlan } from "../api/types";

const plans = graph.plans;
const place = (kind: LayoutKey, some: DependencyPlan[] = plans, links = graph.edges) => arrange(kind, some, links, groups(some, links));
const many = (count: number): DependencyPlan[] =>
  Array.from({ length: count }, (_, i) => ({ ordinal: `${String(i + 1).padStart(3, "0")}.00`, title: `P${i}`, state: "x", summary: null, archived: false }));

/** No two boxes share any ground. */
const apart = (corners: Map<string, { x: number; y: number }>) => {
  const all = [...corners.values()];
  return all.every((a, i) => all.slice(i + 1).every(b => Math.abs(a.x - b.x) >= NODE_WIDTH || Math.abs(a.y - b.y) >= NODE_HEIGHT));
};

it.each(LAYOUTS.map(l => l.key))("%s places every plan, with no two boxes overlapping", kind => {
  expect([...place(kind).keys()].sort()).toEqual(plans.map(p => p.ordinal));
  expect(apart(place(kind))).toBe(true);
  expect(apart(place(kind, many(23), []))).toBe(true);
  expect(place(kind, [], []).size).toBe(0);
});

it("runs a chain left to right, or top to bottom when asked", () => {
  const right = place("right");
  expect(right.get("001.00")!.x).toBeLessThan(right.get("002.00")!.x);
  expect(right.get("001.00")!.y).toBe(right.get("003.00")!.y);
  const down = place("down");
  expect(down.get("001.00")!.y).toBeLessThan(down.get("002.00")!.y);
  expect(down.get("002.00")!.y).toBeLessThan(down.get("003.00")!.y);
});

it("adaptive keeps the chain in a row and packs unlinked plans in rows beneath it", () => {
  const at = place("adaptive");
  const chain = ["001.00", "002.00", "003.00"].map(o => at.get(o)!);
  expect(chain.map(c => c.x)).toEqual([...chain.map(c => c.x)].sort((a, b) => a - b));
  expect(at.get("004.00")!.y).toBeGreaterThanOrEqual(Math.max(...chain.map(c => c.y)) + NODE_HEIGHT);
  expect(at.get("004.00")!.y).toBe(at.get("005.00")!.y);
});

it("adaptive folds a long chain onto rows, in order, with nothing overlapping", () => {
  const some = many(14);
  const links = some.slice(1).map((p, i) => ({ from: some[i]!.ordinal, to: p.ordinal }));
  const at = place("adaptive", some, links);
  const rows = [...new Set([...at.values()].map(c => c.y))];
  expect(rows.length).toBeGreaterThan(1);
  expect(apart(at)).toBe(true);
  // Read like text: sorted by row and then by column, the plans come out in chain order.
  const read = [...at].sort(([, a], [, b]) => a.y - b.y || a.x - b.x).map(([o]) => o);
  expect(read).toEqual(some.map(p => p.ordinal));
  expect(new Set([...place("right", some, links).values()].map(c => c.y)).size).toBe(1);
});

it("adaptive with no arrows at all is rows, not one tall column", () => {
  const at = [...place("adaptive", many(12), []).values()];
  expect(new Set(at.map(c => c.x)).size).toBeGreaterThan(1);
  expect(new Set(at.map(c => c.y)).size).toBeGreaterThan(1);
});

it("circular puts every plan the same distance from the middle, a chain's plans next to each other", () => {
  const some = many(8);
  const links = [{ from: "001.00", to: "008.00" }];
  const at = place("circular", some, links);
  const all = [...at.values()];
  const mid = { x: all.reduce((s, c) => s + c.x, 0) / 8, y: all.reduce((s, c) => s + c.y, 0) / 8 };
  const far = all.map(c => Math.round(Math.hypot(c.x - mid.x, c.y - mid.y)));
  expect(new Set(far).size).toBe(1);
  expect([...at.keys()].slice(0, 2)).toEqual(["001.00", "008.00"]);
  expect(place("circular", some.slice(0, 1), []).get("001.00")).toEqual({ x: 0, y: 0 });
});

it("grid fills rows in plan number order", () => {
  const at = place("grid", many(9), []);
  const [first, second, last] = [at.get("001.00")!, at.get("002.00")!, at.get("009.00")!];
  expect([first, second.y, second.x > first.x, last.y > first.y]).toEqual([{ x: 0, y: 0 }, 0, true, true]);
});

it("says which sides arrows meet a box on, and knows its own keys", () => {
  expect(LAYOUTS.map(l => flowOf(l.key))).toEqual(["right", "right", "down", "free", "free"]);
  expect([isLayout("circular"), isLayout("spiral"), isLayout(null)]).toEqual([true, false, false]);
});

describe("a straight arrow", () => {
  const box = (x: number, y: number) => ({ x, y, width: 200, height: 100 });

  it("leaves through a side wall towards a box beside it, the top or bottom towards one above or below", () => {
    expect(exit(box(0, 0), box(400, 0))).toEqual({ x: 200, y: 50 });
    expect(exit(box(0, 0), box(-400, 0))).toEqual({ x: 0, y: 50 });
    expect(exit(box(0, 0), box(0, 300))).toEqual({ x: 100, y: 100 });
    expect(exit(box(0, 0), box(0, -300))).toEqual({ x: 100, y: 0 });
  });

  it("leaves through the corner along the box's own diagonal, and stays put when the boxes coincide", () => {
    expect(exit(box(0, 0), box(400, 200))).toEqual({ x: 200, y: 100 });
    expect(exit(box(0, 0), box(0, 0))).toEqual({ x: 100, y: 50 });
  });

  it("is drawn edge to edge", () => {
    expect(straight(box(0, 0), box(400, 0))).toBe("M 200,50 L 400,50");
  });
});

it("draws the rectangle around a set of boxes", () => {
  expect(around([{ x: 10, y: 20 }, { x: 300, y: -40 }])).toEqual({ x: 10, y: -40, width: 290 + NODE_WIDTH, height: 60 + NODE_HEIGHT });
});
