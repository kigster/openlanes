import { useEffect, useMemo, useRef } from "react";
import { Background, Controls, ReactFlow, useEdgesState, useNodesState, getViewportForBounds, useReactFlow, useStore, type Edge, type Node } from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import type { DependencyGraph } from "../api/types";
import { BridgeEdge } from "./BridgeEdge";
import { toEdges, toNodes } from "./flow";
import { around, type LayoutKey } from "./layouts";
import { PlanEdge } from "./PlanEdge";
import { PlanNode, type PlanNodeData } from "./PlanNode";
import type { Visible } from "./model";

const nodeTypes = { plan: PlanNode };
const edgeTypes = { plan: PlanEdge, bridge: BridgeEdge };

const MIN_ZOOM = 0.2;
/** As close as a fit ever comes: two boxes alone are drawn a little over life size, not blown up to fill the canvas. */
const FIT_ZOOM = 1.25;

/**
 * Brings the whole graph into view on the first draw and again whenever the arrangement changes: a ring is far
 * larger than a chain. The view is worked out from the corners themselves, not asked of the canvas, which has not
 * drawn the boxes yet when this runs and so fits whatever it held before.
 */
function Refit({ layout, placed }: { layout: LayoutKey; placed: Node[] }) {
  const { setViewport } = useReactFlow();
  const width = useStore(s => s.width);
  const height = useStore(s => s.height);
  const fitted = useRef<LayoutKey | null>(null);
  useEffect(() => {
    if (fitted.current === layout || placed.length === 0 || width === 0 || height === 0) return;
    const view = getViewportForBounds(around(placed.map(n => n.position)), width, height, MIN_ZOOM, FIT_ZOOM, 0.08);
    void setViewport(view, { duration: fitted.current ? 300 : 0 });
    fitted.current = layout;
  }, [layout, placed, width, height, setViewport]);
  return null;
}

/**
 * The graph on a React Flow canvas: boxes drag, the wheel zooms, the background pans. Positions are worked out
 * again each time the filter or the layout changes, so the boxes close up around the plans that are gone; a drag
 * moves a box until then.
 */
export function DependencyFlow({ graph, shown, layout = "adaptive" }: { graph: DependencyGraph; shown: Visible; layout?: LayoutKey }) {
  const states = useMemo(() => new Map(graph.states.map(s => [s.key, s])), [graph]);
  const plans = useMemo(() => new Map(graph.plans.map(p => [p.ordinal, p])), [graph]);
  const [nodes, setNodes, onNodesChange] = useNodesState<Node<PlanNodeData>>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const placed = useMemo(() => toNodes(shown, states, layout), [shown, states, layout]);
  useEffect(() => {
    setNodes(placed);
    setEdges(toEdges(shown, plans, layout));
  }, [placed, shown, plans, layout, setNodes, setEdges]);

  return (
    <div className="dep-canvas" data-testid="dep-canvas" data-layout={layout}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        nodesConnectable={false}
        elementsSelectable={false}
        minZoom={MIN_ZOOM}
        proOptions={{ hideAttribution: true }}
        aria-label="Dependencies"
      >
        <Background />
        <Refit layout={layout} placed={placed} />
        <Controls showInteractive={false} />
      </ReactFlow>
    </div>
  );
}
