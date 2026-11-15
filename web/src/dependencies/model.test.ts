import { bridges, groups, layout, visible } from "./model";
import { graph } from "./fixture";
import type { DependencyGraph } from "../api/types";

const all = new Set(["building", "planned", "approved"]);

describe("visible", () => {
  it("shows every plan of a checked state with its real edges", () => {
    const v = visible(graph, all);
    expect(v.plans).toHaveLength(5);
    expect(v.edges).toHaveLength(2);
    expect(v.bridges).toEqual([]);
  });

  it("drops plans of an unchecked state", () => {
    expect(visible(graph, new Set(["building", "planned"])).plans.map(p => p.ordinal)).not.toContain("005.00");
  });

  it("bridges A→B→C with B hidden: one dashed A→C naming B", () => {
    const v = visible(graph, new Set(["building", "approved"]));
    expect(v.edges).toEqual([]);
    expect(v.bridges).toEqual([{ from: "001.00", to: "003.00", via: ["002.00"] }]);
  });
});

describe("bridges", () => {
  const chain: DependencyGraph = {
    ...graph,
    plans: ["A", "B", "C", "D"].map((n, i) => ({ ordinal: `00${i + 1}.00`, title: n, state: "x", summary: null, archived: false })),
    edges: [
      { from: "001.00", to: "002.00" },
      { from: "002.00", to: "003.00" },
      { from: "003.00", to: "004.00" },
    ],
  };

  it("passes through a chain of two hidden plans", () => {
    expect(bridges(chain, new Set(["002.00", "003.00"]))).toEqual([{ from: "001.00", to: "004.00", via: ["002.00", "003.00"] }]);
  });

  it("leaves nothing for a hidden plan at the end of a chain", () => {
    expect(bridges(chain, new Set(["004.00"]))).toEqual([]);
  });

  it("adds none where a real arrow already joins the pair", () => {
    const g = { ...chain, edges: [...chain.edges, { from: "001.00", to: "003.00" }] };
    expect(bridges(g, new Set(["002.00"]))).toEqual([]);
  });

  it("survives a cycle", () => {
    const g = { ...chain, edges: [{ from: "002.00", to: "003.00" }, { from: "003.00", to: "002.00" }, { from: "001.00", to: "002.00" }] };
    expect(bridges(g, new Set(["002.00", "003.00"]))).toEqual([]);
  });
});

describe("layout", () => {
  it("lays a chain left to right and names one group per component", () => {
    const v = visible(graph, all);
    const placed = layout(v.plans, v.edges);
    const x = (o: string) => placed.find(p => p.plan.ordinal === o)!.x;
    expect(x("001.00")).toBeLessThan(x("002.00"));
    expect(x("002.00")).toBeLessThan(x("003.00"));
    const g = Object.fromEntries(placed.map(p => [p.plan.ordinal, p.group]));
    expect(g["003.00"]).toBe("001.00");
    expect(g["004.00"]).toBe("004.00");
  });

  it("ignores edges to plans not laid out", () => {
    expect(layout(graph.plans.slice(0, 1), graph.edges)).toHaveLength(1);
  });
});

it("groups joins components through links", () => {
  const g = groups(graph.plans, [{ from: "004.00", to: "002.00" }, { from: "x", to: "y" }]);
  expect(g.get("004.00")).toBe("002.00");
});
