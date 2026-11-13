import { toEdges, toNodes } from "./flow";
import { graph } from "./fixture";
import { visible } from "./model";

const states = new Map(graph.states.map(s => [s.key, s]));
const plans = new Map(graph.plans.map(p => [p.ordinal, p]));

it("makes a fixed-size plan node per shown plan, placed left to right along the chain", () => {
  const nodes = toNodes(visible(graph, new Set(["building", "planned"])), states);
  expect(nodes.map(n => n.id)).toEqual(["001.00", "002.00", "003.00", "004.00"]);
  expect(nodes.every(n => n.type === "plan" && n.width === 220 && n.height === 72)).toBe(true);
  const x = Object.fromEntries(nodes.map(n => [n.id, n.position.x]));
  expect(x["001.00"]!).toBeLessThan(x["002.00"]!);
  expect(x["002.00"]!).toBeLessThan(x["003.00"]!);
  expect(nodes[0]!.data.state?.name).toBe("Building");
});

it("makes a plan edge per real arrow and a bridge edge naming the hidden plans", () => {
  expect(toEdges(visible(graph, new Set(["building", "planned"])), plans).map(e => [e.type, e.source, e.target])).toEqual([
    ["plan", "001.00", "002.00"],
    ["plan", "002.00", "003.00"],
  ]);
  const [bridge] = toEdges(visible(graph, new Set(["building"])), plans);
  expect(bridge).toMatchObject({ type: "bridge", source: "001.00", target: "003.00", data: { names: ["002.00 Second"] } });
});
