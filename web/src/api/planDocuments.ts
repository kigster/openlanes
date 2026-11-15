// Which plans' document lists the board says to read again. The list comes from the plan's folder, which no snapshot
// carries, so nothing on the stream names a file. What it does carry is when a plan moved, and a plan's documents
// appear and go with its moves: plan.md at Planned, blocked.md with a question, pull-requests.md with a pull request.
import type { Plan, WireBoard } from "./types";

/**
 * What of a plan changes when its folder may have. Deliberately not the whole plan: its counters (tokens, cost,
 * elapsed) tick many times a minute, and each list request scans `.plans`. A file an agent writes with none of these
 * moving is caught when the menu opens, which always reads the list again.
 */
const signature = (plan: Plan): string =>
  JSON.stringify([plan.status, plan.station, plan.questions.length, plan.pr?.number ?? null, plan.pr?.state ?? null, plan.cars.map(c => c.key)]);

/**
 * The ordinals, on this machine, whose documents may differ between two boards. Other machines' plans are left out:
 * their lanes list no documents. A first board (`old` undefined) names none, since no list has been read yet.
 */
export function plansWithNewDocuments(old: WireBoard | undefined, next: WireBoard): string[] {
  if (!old?.me || !next.me) return [];
  const was = new Map(old.me.plans.map(p => [p.ordinal, signature(p)]));
  return next.me.plans.filter(p => was.get(p.ordinal) !== signature(p)).map(p => p.ordinal);
}
