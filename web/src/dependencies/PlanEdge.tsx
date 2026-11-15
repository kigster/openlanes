import type { EdgeProps } from "@xyflow/react";
import { useEdgePath } from "./useEdgePath";

/** A real depends_on: arrow between two shown plans. */
export function PlanEdge(props: EdgeProps) {
  const d = useEdgePath(props);
  return <path className="react-flow__edge-path dep-edge" data-from={props.source} data-to={props.target} d={d} markerEnd={props.markerEnd} />;
}
