import { useState } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { Handle, Position, type NodeProps, type Node } from "@xyflow/react";
import type { DependencyPlan, DependencyState } from "../api/types";

export const NO_SUMMARY = "No summary has been written for this plan yet.";

export interface PlanNodeData extends Record<string, unknown> {
  plan: DependencyPlan;
  state: DependencyState | undefined;
}

/** One plan, as a React Flow node: number, title and state, with its summary on hover, kept open by a click. */
export function PlanNode({ data: { plan, state } }: NodeProps<Node<PlanNodeData>>) {
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  return (
    <Tooltip.Root open={hover || pinned} onOpenChange={setHover}>
      <Handle type="target" position={Position.Left} className="dep-handle" />
      <Tooltip.Trigger asChild>
        <button
          type="button"
          className="dep-node"
          data-plan={plan.ordinal}
          data-state={plan.state}
          data-archived={plan.archived || undefined}
          aria-pressed={pinned}
          onClick={() => setPinned(p => !p)}
        >
          <span className="dep-node-id">{plan.ordinal}</span>
          <span className="dep-node-title">{plan.title}</span>
          <span className="dep-node-state">
            {state?.emoji} {state?.name ?? plan.state}
          </span>
        </button>
      </Tooltip.Trigger>
      <Handle type="source" position={Position.Right} className="dep-handle" />
      <Tooltip.Portal>
        <Tooltip.Content className="dep-tip" side="bottom" sideOffset={6}>
          {plan.summary?.trim() || NO_SUMMARY}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}
