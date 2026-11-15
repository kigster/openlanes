import { useEffect, useState } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { Handle, Position, useUpdateNodeInternals, type NodeProps, type Node } from "@xyflow/react";
import type { DependencyPlan, DependencyState } from "../api/types";
import { LaneDocuments } from "../board/LaneDocuments";
import type { Flow } from "./layouts";

export const NO_SUMMARY = "No summary has been written for this plan yet.";

export interface PlanNodeData extends Record<string, unknown> {
  plan: DependencyPlan;
  state: DependencyState | undefined;
  /** Which sides arrows meet the box on. Left out, they come in on the left and leave on the right. */
  flow?: Flow;
}

/** One plan, as a React Flow node: number, title and state, with its summary on hover, kept open by a click. */
export function PlanNode({ id, data: { plan, state, flow } }: NodeProps<Node<PlanNodeData>>) {
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  const down = flow === "down";
  // React Flow measures where a box's handles are once; told nothing, arrows keep leaving from the old sides.
  const remeasure = useUpdateNodeInternals();
  useEffect(() => remeasure(id), [down, id, remeasure]);
  return (
    <div className="dep-node-wrap">
      <Tooltip.Root open={hover || pinned} onOpenChange={setHover}>
        <Handle type="target" position={down ? Position.Top : Position.Left} className="dep-handle" />
        <Tooltip.Trigger asChild>
          <button
            type="button"
            className="dep-node"
            data-plan={plan.ordinal}
            data-state={plan.state}
            data-archived={plan.archived || undefined}
            aria-pressed={pinned}
            onClick={() => setPinned(p => !p)}
            // Radix opens only on a pointermove it believes came from a mouse, which a canvas that pans under the
            // pointer does not always deliver. Entering and leaving the box are said outright (F1).
            onPointerEnter={() => setHover(true)}
            onPointerLeave={() => setHover(false)}
          >
            <span className="dep-node-id">{plan.ordinal}</span>
            <span className="dep-node-title">{plan.title}</span>
            <span className="dep-node-state">
              {state?.emoji} {state?.name ?? plan.state}
            </span>
          </button>
        </Tooltip.Trigger>
        <Handle type="source" position={down ? Position.Bottom : Position.Right} className="dep-handle" />
        <Tooltip.Portal>
          <Tooltip.Content className="dep-tip" side="bottom" sideOffset={6}>
            {plan.summary?.trim() || NO_SUMMARY}
          </Tooltip.Content>
        </Tooltip.Portal>
      </Tooltip.Root>
      {/* nodrag and nopan: a press on the menu is a press on the menu, not the start of a drag or a pan. */}
      <LaneDocuments ordinal={plan.ordinal} lazy className="dep-node-docs nodrag nopan" />
    </div>
  );
}
