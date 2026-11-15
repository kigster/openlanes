import { Position, getBezierPath, useInternalNode, type EdgeProps, type InternalNode } from "@xyflow/react";
import { NODE_HEIGHT, NODE_WIDTH, straight, type Box } from "./layouts";

const box = (node: InternalNode): Box => ({
  ...node.internals.positionAbsolute,
  width: node.measured.width ?? NODE_WIDTH,
  height: node.measured.height ?? NODE_HEIGHT,
});

/**
 * The line an arrow follows. A layered arrangement curves it between the handles React Flow hands over; a ring or
 * a grid, marked `floating`, draws it straight between the two boxes wherever they are, so it follows a drag. So does
 * an arrow that has to run backwards, to a folded row's start or a box dragged behind its dependency: a curve between
 * handles that face away from each other loops out past both boxes.
 */
export function useEdgePath({ source, target, data, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition }: EdgeProps): string {
  const from = useInternalNode(source);
  const to = useInternalNode(target);
  const backwards = sourcePosition === Position.Right ? targetX < sourceX : sourcePosition === Position.Bottom && targetY < sourceY;
  if ((data?.floating || backwards) && from && to) return straight(box(from), box(to));
  return getBezierPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition })[0];
}
