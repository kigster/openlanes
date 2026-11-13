import * as Tooltip from "@radix-ui/react-tooltip";
import { curve, type Bridge, type Point } from "./model";

/** A dashed arrow over hidden plans; hovering it names them. */
export function BridgeEdge({ bridge, from, to, names }: { bridge: Bridge; from: Point; to: Point; names: string[] }) {
  const d = curve(from, to);
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>
        <g className="dep-bridge" data-from={bridge.from} data-to={bridge.to} tabIndex={0} aria-label={`Bridge ${bridge.from} to ${bridge.to}`}>
          <path d={d} className="dep-hit" />
          <path d={d} className="dep-edge is-dashed" strokeDasharray="6 5" markerEnd="url(#dep-arrow)" />
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
