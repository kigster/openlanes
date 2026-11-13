import type { Plan, Station } from "../api/types";
import { isApproved, isMerged, pillState } from "../board/model";
import type { GonePlan } from "../board/useLifecycle";

export interface PlanCounts {
  merged: number;
  ready: number;
  blocked: number;
}

/** How this machine's plans stand. Merged plans whose rows have left the board still count as merged. */
export function planCounts(plans: Plan[], stations: Station[], gone: ReadonlyMap<string, GonePlan>): PlanCounts {
  const live = plans.filter(p => !gone.has(p.ordinal));
  const ours = [...live, ...[...gone.values()].map(g => g.plan)];
  return {
    merged: ours.filter(isMerged).length,
    ready: ours.filter(isApproved).length,
    blocked: live.filter(p => pillState(p, stations).blocked).length,
  };
}
