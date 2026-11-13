import { getBezierPath, type EdgeProps } from "@xyflow/react";

/** A real depends_on: arrow between two shown plans. */
export function PlanEdge({ source, target, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, markerEnd }: EdgeProps) {
  const [d] = getBezierPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition });
  return <path className="react-flow__edge-path dep-edge" data-from={source} data-to={target} d={d} markerEnd={markerEnd} />;
}
