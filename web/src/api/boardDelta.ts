// Applies a `board_delta` frame onto the cached board (contract.md §1). The server flattens a board into keyed
// entries; this flattens the cached one the same way, replaces and removes keys, and rebuilds each snapshot's plans.
import type { BoardDelta, Plan, Snapshot, WireBoard } from "./types";

type Flat = Map<string, Record<string, unknown>>;

const nodeKey = (s: Snapshot) => `node/${s.node.id}/${s.node.checkout}`;
const planKey = (s: Snapshot, ordinal: string) => `plan/${s.node.id}/${s.node.checkout}/${ordinal}`;

function flatten(board: WireBoard): Flat {
  const flat: Flat = new Map();
  for (const s of [board.me, ...board.others]) {
    if (!s) continue;
    const { plans, ...rest } = s;
    flat.set(nodeKey(s), { ...rest, plan_order: plans.map(p => p.ordinal) });
    for (const p of plans) flat.set(planKey(s, p.ordinal), p as unknown as Record<string, unknown>);
  }
  return flat;
}

/** True when `delta` applies onto a board at `version`. */
export const appliesTo = (version: number | null, delta: BoardDelta): boolean => version !== null && delta.base === version;

/** The board after `delta`. Does not check `base`: see {@link appliesTo}. */
export function applyDelta(board: WireBoard, delta: BoardDelta): WireBoard {
  const flat = flatten(board);
  for (const key of delta.remove) flat.delete(key);
  for (const { key, value } of delta.upsert) flat.set(key, value);

  const snapshots: Snapshot[] = [];
  for (const [key, value] of flat) {
    if (!key.startsWith("node/")) continue;
    const { plan_order, ...rest } = value as Record<string, unknown> & { plan_order?: string[] };
    const prefix = `plan/${key.slice("node/".length)}/`;
    const plans = (plan_order ?? []).flatMap(o => {
      const p = flat.get(prefix + o);
      return p ? [p as unknown as Plan] : [];
    });
    snapshots.push({ ...rest, plans } as unknown as Snapshot);
  }
  const me = snapshots.find(s => s.node.me) ?? null;
  // Plain comparison, as the server orders `others` (`sort_by { host }`, bytewise): `localeCompare` put
  // "alpha" before "Zeta", so two lanes swapped places on the first delta after a full board.
  const others = snapshots.filter(s => !s.node.me).sort((a, b) => (a.node.host < b.node.host ? -1 : a.node.host > b.node.host ? 1 : 0));
  return { me, others, version: delta.version };
}
