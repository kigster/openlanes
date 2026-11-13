import { doc } from "./fixture";
import { getAt, panesOf, prune, sameValues, setAt } from "./model";

it("builds a scalar pane, then a pane per section, with commands split per command", () => {
  const panes = panesOf(doc);
  expect(panes.map(p => p.title)).toEqual(["General", "merge", "commands"]);
  expect(panes[0].fields.map(f => f.path.join("."))).toEqual(["project", "frontend", "jobs", "ratio", "tags"]);
  expect(panes[1].fields.map(f => f.path.join("."))).toEqual(["merge.by", "merge.nested.depth"]);
  expect(panes[2].children.map(c => c.title)).toEqual(["run", "api docs"]);
});

it("skips keys the schema does not describe, and has no General pane when there are no scalars", () => {
  expect(panesOf({ ...doc, keys: ["merge", "ghost"] }).map(p => p.title)).toEqual(["merge"]);
});

it("reads and writes by path without touching the original", () => {
  const before = { a: { b: 1 } };
  const after = setAt(before, ["a", "c", "d"], 2);
  expect(before).toEqual({ a: { b: 1 } });
  expect(getAt(after, ["a", "c", "d"])).toBe(2);
  expect(getAt(after, ["x", "y"])).toBeUndefined();
  expect(setAt({ a: 5 }, ["a", "b"], 1)).toEqual({ a: { b: 1 } });
});

it("treats null and absent as the same, and key order as irrelevant", () => {
  expect(prune({ a: null, b: [{ c: null, d: 1 }] })).toEqual({ b: [{ d: 1 }] });
  expect(sameValues({ a: 1, b: null }, { a: 1 })).toBe(true);
  expect(sameValues({ x: 1, y: [1, { q: 1, p: 2 }] }, { y: [1, { p: 2, q: 1 }], x: 1 })).toBe(true);
  expect(sameValues({ a: 1 }, { a: 2 })).toBe(false);
});
