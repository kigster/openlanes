import { useState } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import type { DependencyPlan, DependencyState } from "../api/types";
import { NODE_HEIGHT, NODE_WIDTH } from "./model";

export const NO_SUMMARY = "No summary has been written for this plan yet.";

/** One plan: number, title and state, with its summary on hover, kept open by a click. */
export function PlanNode({ plan, state, x, y }: { plan: DependencyPlan; state: DependencyState | undefined; x: number; y: number }) {
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  return (
    <Tooltip.Root open={hover || pinned} onOpenChange={setHover}>
      <Tooltip.Trigger asChild>
        <button
          type="button"
          className="dep-node"
          data-plan={plan.ordinal}
          data-state={plan.state}
          data-archived={plan.archived || undefined}
          aria-pressed={pinned}
          style={{ left: x, top: y, width: NODE_WIDTH, height: NODE_HEIGHT }}
          onClick={() => setPinned(p => !p)}
        >
          <span className="dep-node-id">{plan.ordinal}</span>
          <span className="dep-node-title">{plan.title}</span>
          <span className="dep-node-state">
            {state?.emoji} {state?.name ?? plan.state}
          </span>
        </button>
      </Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className="dep-tip" side="bottom" sideOffset={6}>
          {plan.summary?.trim() || NO_SUMMARY}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}
