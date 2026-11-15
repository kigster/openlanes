// From the visible graph to React Flow's nodes and edges. No React in here, so the tests need no DOM.
import { MarkerType, type Edge, type Node } from "@xyflow/react";
import type { DependencyPlan, DependencyState } from "../api/types";
import type { BridgeData } from "./BridgeEdge";
import type { PlanNodeData } from "./PlanNode";
import { NODE_HEIGHT, NODE_WIDTH, layout, type Visible } from "./model";

const arrow = { type: MarkerType.ArrowClosed, width: 14, height: 14 };

/** The React Flow nodes for the shown plans, placed by dagre. Fixed width and height, so edges need no measuring. */
export function toNodes(shown: Visible, states: Map<string, DependencyState>): Node<PlanNodeData>[] {
  return layout(shown.plans, [...shown.edges, ...shown.bridges]).map(p => ({
    id: p.plan.ordinal,
    type: "plan",
    position: { x: p.x, y: p.y },
    width: NODE_WIDTH,
    height: NODE_HEIGHT,
    data: { plan: p.plan, state: states.get(p.plan.state) },
  }));
}

/** A real arrow per depends_on: edge, and a dashed bridge per chain of hidden plans. */
export function toEdges(shown: Visible, plans: Map<string, DependencyPlan>): Edge[] {
  const name = (o: string) => `${o} ${plans.get(o)?.title ?? ""}`.trim();
  return [
    ...shown.edges.map(e => ({ id: `${e.from}>${e.to}`, source: e.from, target: e.to, type: "plan", markerEnd: arrow })),
    ...shown.bridges.map(b => ({
      id: `${b.from}>${b.to}`,
      source: b.from,
      target: b.to,
      type: "bridge",
      markerEnd: arrow,
      data: { from: b.from, to: b.to, names: b.via.map(name) } satisfies BridgeData,
    })),
  ];
}
