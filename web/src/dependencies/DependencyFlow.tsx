import { useEffect, useMemo } from "react";
import { Background, Controls, ReactFlow, useEdgesState, useNodesState, type Edge, type Node } from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import type { DependencyGraph } from "../api/types";
import { BridgeEdge } from "./BridgeEdge";
import { toEdges, toNodes } from "./flow";
import { PlanEdge } from "./PlanEdge";
import { PlanNode, type PlanNodeData } from "./PlanNode";
import type { Visible } from "./model";

const nodeTypes = { plan: PlanNode };
const edgeTypes = { plan: PlanEdge, bridge: BridgeEdge };
/**
 * The graph on a React Flow canvas: boxes drag, the wheel zooms, the background pans. Positions come from dagre
 * each time the filter changes, so the boxes close up around the plans that are gone; a drag moves a box until then.
 */
export function DependencyFlow({ graph, shown }: { graph: DependencyGraph; shown: Visible }) {
  const states = useMemo(() => new Map(graph.states.map(s => [s.key, s])), [graph]);
  const plans = useMemo(() => new Map(graph.plans.map(p => [p.ordinal, p])), [graph]);
  const [nodes, setNodes, onNodesChange] = useNodesState<Node<PlanNodeData>>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  useEffect(() => {
    setNodes(toNodes(shown, states));
    setEdges(toEdges(shown, plans));
  }, [shown, states, plans, setNodes, setEdges]);

  return (
    <div className="dep-canvas" data-testid="dep-canvas">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        nodesConnectable={false}
        elementsSelectable={false}
        fitView
        minZoom={0.2}
        proOptions={{ hideAttribution: true }}
        aria-label="Dependencies"
      >
        <Background />
        <Controls showInteractive={false} />
      </ReactFlow>
    </div>
  );
}
