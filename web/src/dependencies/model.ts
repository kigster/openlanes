// The Plan dependencies page's logic, pure: which plans show, which dashed bridges stand in for the hidden ones,
// and where each box sits. No React in here, so the tests need no DOM.
import dagre from "@dagrejs/dagre";
import type { DependencyEdge, DependencyGraph, DependencyPlan } from "../api/types";

/** A dashed arrow standing in for a chain of hidden plans; `via` names them, in walking order. */
export interface Bridge {
  from: string;
  to: string;
  via: string[];
}

export interface Visible {
  plans: DependencyPlan[];
  edges: DependencyEdge[];
  bridges: Bridge[];
}

export interface Placed {
  plan: DependencyPlan;
  x: number;
  y: number;
  /** The connected component the plan belongs to: its lowest ordinal. The follow-up plan draws an outline per group. */
  group: string;
}

export const NODE_WIDTH = 220;
export const NODE_HEIGHT = 72;

const edgeKey = (e: { from: string; to: string }) => `${e.from}>${e.to}`;

/**
 * Bridges: from each shown plan, walk forward through hidden plans only; every shown plan reached is joined to the
 * start by a dashed edge naming the hidden plans on the way. A chain that ends in a hidden plan reaches nothing shown,
 * so it leaves no bridge. A pair that already has a real arrow gets none.
 */
export function bridges(graph: DependencyGraph, hidden: Set<string>): Bridge[] {
  const next = new Map<string, string[]>();
  for (const e of graph.edges) next.set(e.from, [...(next.get(e.from) ?? []), e.to]);
  const direct = new Set(graph.edges.map(edgeKey));
  const found = new Map<string, Bridge>();

  const walk = (start: string, at: string, via: string[], seen: Set<string>) => {
    for (const to of next.get(at) ?? []) {
      if (seen.has(to)) continue;
      if (hidden.has(to)) {
        walk(start, to, [...via, to], new Set(seen).add(to));
      } else if (via.length > 0 && !direct.has(edgeKey({ from: start, to }))) {
        const key = edgeKey({ from: start, to });
        const known = found.get(key);
        found.set(key, { from: start, to, via: known ? [...new Set([...known.via, ...via])] : via });
      }
    }
  };
  for (const p of graph.plans) if (!hidden.has(p.ordinal)) walk(p.ordinal, p.ordinal, [], new Set([p.ordinal]));
  return [...found.values()];
}

/** The plans whose state is checked, the real edges between them, and the bridges over the rest. */
export function visible(graph: DependencyGraph, checked: Set<string>): Visible {
  const shown = graph.plans.filter(p => checked.has(p.state));
  const ids = new Set(shown.map(p => p.ordinal));
  const hidden = new Set(graph.plans.filter(p => !ids.has(p.ordinal)).map(p => p.ordinal));
  return {
    plans: shown,
    edges: graph.edges.filter(e => ids.has(e.from) && ids.has(e.to)),
    bridges: bridges(graph, hidden),
  };
}

/** Each plan's connected component (edges and bridges both join), named by its lowest ordinal. */
export function groups(plans: DependencyPlan[], links: Array<{ from: string; to: string }>): Map<string, string> {
  const parent = new Map(plans.map(p => [p.ordinal, p.ordinal]));
  const find = (x: string): string => {
    let root = x;
    while (parent.get(root) !== root) root = parent.get(root)!;
    return root;
  };
  for (const l of links) {
    if (!parent.has(l.from) || !parent.has(l.to)) continue;
    const [a, b] = [find(l.from), find(l.to)].sort();
    if (a !== b) parent.set(b!, a!);
  }
  return new Map(plans.map(p => [p.ordinal, find(p.ordinal)]));
}

/** Left-to-right layout through dagre; run again on every filter change so the boxes close up. */
export function layout(plans: DependencyPlan[], links: Array<{ from: string; to: string }>): Placed[] {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", nodesep: 28, ranksep: 90 });
  g.setDefaultEdgeLabel(() => ({}));
  for (const p of plans) g.setNode(p.ordinal, { width: NODE_WIDTH, height: NODE_HEIGHT });
  for (const l of links) if (g.hasNode(l.from) && g.hasNode(l.to)) g.setEdge(l.from, l.to);
  dagre.layout(g);
  const group = groups(plans, links);
  return plans.map(plan => {
    const n = g.node(plan.ordinal);
    return { plan, x: n.x - NODE_WIDTH / 2, y: n.y - NODE_HEIGHT / 2, group: group.get(plan.ordinal)! };
  });
}

export interface Point {
  x: number;
  y: number;
}

/** A curve from one box's right edge to the next one's left, shared by real and bridged arrows. */
export const curve = (a: Point, b: Point): string => {
  const mid = (a.x + b.x) / 2;
  return `M${a.x},${a.y} C${mid},${a.y} ${mid},${b.y} ${b.x},${b.y}`;
};
