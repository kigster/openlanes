// The "Plan Management" menu's actions (GET and POST /api/plans/:ordinal/actions). The server says which actions a plan
// offers, so the menu never offers one the state machine would refuse.
import { useQuery } from "@tanstack/react-query";
import { ApiError, postJson } from "./client";
import { sendCommand } from "./useSendCommand";

export type PlanActionKey = "clear_dependencies" | "discard" | "defer";

export interface PlanOffer {
  ordinal: string;
  status: string;
  /** Its build has begun, or an agent is on it: discarding it aborts work rather than skipping it. */
  started: boolean;
  /** An agent works it now; the page stops it before acting. */
  running: boolean;
  depends_on: string[];
  actions: PlanActionKey[];
}

/** "Abort & Discard" once work has begun, "Don't Start and Discard" before. */
export function actionLabel(key: PlanActionKey, offer: PlanOffer): string {
  if (key === "clear_dependencies") return "Clear Dependencies";
  if (key === "defer") return "Defer";
  return offer.started ? "Abort & Discard" : "Don't Start and Discard";
}

export const PLAN_ACTIONS_KEY = ["plan-actions"] as const;
export const planActionsKey = (ordinal: string) => [...PLAN_ACTIONS_KEY, ordinal] as const;

const path = (ordinal: string) => `/api/plans/${encodeURIComponent(ordinal)}/actions`;

async function reasonOf(res: Response, fallback: string): Promise<string> {
  return res
    .json()
    .then((body: { error?: unknown }) => (typeof body.error === "string" ? body.error : fallback))
    .catch(() => fallback);
}

export async function getPlanOffer(ordinal: string): Promise<PlanOffer> {
  const res = await fetch(path(ordinal), { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(await reasonOf(res, `GET ${path(ordinal)} answered ${res.status}`), res.status);
  return (await res.json()) as PlanOffer;
}

/** Read whenever the menu mounts it: a plan moves while the page is open, so nothing is kept fresh for long. */
export function usePlanOffer(ordinal: string, enabled: boolean) {
  return useQuery({ queryKey: planActionsKey(ordinal), queryFn: () => getPlanOffer(ordinal), staleTime: 0, retry: false, enabled });
}

export async function postPlanAction(ordinal: string, action: PlanActionKey, reason = ""): Promise<PlanOffer> {
  const res = await postJson(path(ordinal), { action, reason });
  if (!res.ok) throw new ApiError(await reasonOf(res, `POST ${path(ordinal)} answered ${res.status}`), res.status);
  return (await res.json()) as PlanOffer;
}

/** How long Abort waits for the plan's agents to let go after the engine stopped them. */
export const ABORT_WAIT_MS = 20_000;
const ABORT_POLL_MS = 1_000;

/**
 * Runs an action, stopping the plan's agents first when one is on it. The engine answers `stop_plan` once it has
 * signalled them, but an agent takes a moment to exit, so a 409 (still working) is asked again until it lets go.
 */
/**
 * The agents were stopped, and then the plan did not move: say both, so
 * nobody is left guessing whether the abort half-happened.
 */
function stoppedOnly(ordinal: string, error: unknown): ApiError {
  const why = error instanceof Error ? error.message : String(error);
  const status = error instanceof ApiError ? error.status : 0;
  return new ApiError(`The agents on ${ordinal} were stopped, but the plan was not moved: ${why}`, status);
}

export async function runPlanAction(
  offer: PlanOffer,
  action: PlanActionKey,
  reason: string,
  { waitMs = ABORT_WAIT_MS, pollMs = ABORT_POLL_MS, sleep = (ms: number) => new Promise(r => setTimeout(r, ms)) } = {},
): Promise<PlanOffer> {
  if (offer.running) {
    const reply = await sendCommand({ kind: "stop_plan", plan: offer.ordinal, agent: null, payload: {} });
    if (reply.status === "refused") throw new ApiError(reply.reason ?? `the engine would not stop ${offer.ordinal}`, 409);
  }
  const until = Date.now() + waitMs;
  for (;;) {
    try {
      return await postPlanAction(offer.ordinal, action, reason);
    } catch (error) {
      const busy = error instanceof ApiError && error.status === 409;
      if (!offer.running) throw error;
      if (!busy || Date.now() >= until) throw stoppedOnly(offer.ordinal, error);
      await sleep(pollMs);
    }
  }
}
