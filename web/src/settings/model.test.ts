import { doc } from "./fixture";
import { scrollWhenThere } from "../shell/reveal";
import { getAt, paneAnchor, panesHolding, panesOf, prune, sameValues, setAt, titleCase } from "./model";

it("builds a scalar pane, then a pane per section, and leaves the CLI's commands out", () => {
  const panes = panesOf(doc);
  expect(panes.map(p => p.title)).toEqual(["General", "Merge"]);
  expect(panes[0].fields.map(f => f.path.join("."))).toEqual(["project", "frontend", "jobs", "ratio", "tags"]);
  expect(panes[1].fields.map(f => f.path.join("."))).toEqual(["merge.by", "merge.nested.depth"]);
});

it("labels fields in Capital Case, without the pane's own prefix", () => {
  const [general, merge] = panesOf(doc);
  expect(general.fields.map(f => f.label)).toEqual(["Project", "Frontend", "Jobs", "Ratio", "Tags"]);
  expect(merge.fields.map(f => f.label)).toEqual(["By", "Nested Depth"]);
});

it("turns snake_case and dotted keys into words", () => {
  expect(titleCase("pr_review")).toBe("Pr Review");
  expect(titleCase("api docs")).toBe("Api Docs");
  expect(titleCase("a.b_c")).toBe("A B C");
});

it("skips keys the schema does not describe, and has no General pane when there are no scalars", () => {
  expect(panesOf({ ...doc, keys: ["merge", "ghost"] }).map(p => p.title)).toEqual(["Merge"]);
});

it("drops a section with no fields in it", () => {
  const props = { empty: { type: "object", properties: {} } };
  expect(panesOf({ ...doc, schema: { type: "object", properties: props }, keys: ["empty"] })).toEqual([]);
});

it("names every pane, sub-panes included, that holds a refused path", () => {
  const panes = panesOf(doc);
  expect(panesHolding(panes, new Set(["merge.by", "jobs"]))).toEqual(["general", "merge"]);
  expect(panesHolding(panes, new Set(["mystery"]))).toEqual([]);
});

it("makes a DOM-safe anchor per pane, and scrolls to it once it appears", () => {
  expect(paneAnchor("commands.api docs")).toBe("set-pane-commands-api-docs");
  const el = document.createElement("section");
  el.id = paneAnchor("merge");
  el.scrollIntoView = vi.fn();
  const frames: FrameRequestCallback[] = [];
  vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => frames.push(cb));
  scrollWhenThere(paneAnchor("merge"));
  expect(frames).toHaveLength(1);
  document.body.append(el);
  frames[0](0);
  expect(el.scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "start" });
  scrollWhenThere(paneAnchor("ghost"), 0);
  expect(frames).toHaveLength(1);
  el.remove();
  vi.unstubAllGlobals();
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
