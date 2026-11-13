import * as Tooltip from "@radix-ui/react-tooltip";
import { getBezierPath, type Edge, type EdgeProps } from "@xyflow/react";

export interface BridgeData extends Record<string, unknown> {
  from: string;
  to: string;
  /** "NNN.MM Title" for each hidden plan the bridge passes over, in walking order. */
  names: string[];
}

/** A dashed arrow over hidden plans; hovering it names them. */
export function BridgeEdge({ data, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, markerEnd }: EdgeProps<Edge<BridgeData>>) {
  const [d] = getBezierPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition });
  const names = data?.names ?? [];
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>
        <g className="dep-bridge" data-from={data?.from} data-to={data?.to} tabIndex={0} aria-label={`Bridge ${data?.from} to ${data?.to}`}>
          <path d={d} className="dep-hit" />
          <path d={d} className="react-flow__edge-path dep-edge is-dashed" strokeDasharray="6 5" markerEnd={markerEnd} />
        </g>
      </Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className="dep-tip" sideOffset={6}>
          Passes through hidden {names.length === 1 ? "plan" : "plans"}: {names.join(", ")}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}
