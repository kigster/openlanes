import { useCallback, useEffect, useRef, useState } from "react";
import type { Plan } from "../api/types";
import { isFinished, isMerged, keepsRow } from "./model";

/** A merged row the engine did not mark finished (another machine's older engine) stays this long before it fades. */
export const ROW_STAYS_MS = 10_000;
/** …and fades and folds away over this long. */
export const FADE_MS = 1_000;
/** A purple pill leaves an overflowing bar only after this long (the mockup's 30 s stands in for five minutes). */
export const MERGED_STAYS_MS = 5 * 60_000;

export interface GonePlan {
  plan: Plan;
  /** Date.now() when its row left the board. */
  at: number;
}

export interface Lifecycle {
  /** Rows fading out right now. */
  retiring: ReadonlySet<string>;
  /** Merged plans whose rows have left the board, still shown as purple pills. */
  gone: ReadonlyMap<string, GonePlan>;
  /** The order plans finished in, for the right-hand end of the status bar. */
  finishOrder: ReadonlyMap<string, number>;
  /** Purple pills taken off an overflowing bar; their plans stay gone from the board. */
  offBar: ReadonlySet<string>;
  /** Takes a purple pill off the bar for good. */
  dropFromBar(ordinal: string): void;
}

const without = <T,>(set: ReadonlySet<T>, item: T): Set<T> => {
  const next = new Set(set);
  next.delete(item);
  return next;
};

const withoutKey = <K, V>(map: ReadonlyMap<K, V>, key: K): Map<K, V> => {
  const next = new Map(map);
  next.delete(key);
  return next;
};

/**
 * The page's memory of what the snapshot no longer says: when each merged row should fade, which merged plans have
 * already left the board, and the order plans finished in. Timers live here, not in the board, so switching tabs
 * never restarts a merged row's ten seconds. A plan the engine marks `finished` has no ten seconds: its row stays,
 * half height, for as long as the snapshot sends it.
 *
 * Keyed by ordinal. For other machines, App passes their plans with the ordinal replaced by nodePlanKey, so one hook
 * tracks every machine without two machines' 010.00 colliding.
 */
export function useLifecycle(plans: Plan[], reduced = false): Lifecycle {
  const [retiring, setRetiring] = useState<ReadonlySet<string>>(new Set());
  const [gone, setGone] = useState<ReadonlyMap<string, GonePlan>>(new Map());
  const [finishOrder, setFinishOrder] = useState<ReadonlyMap<string, number>>(new Map());
  const [offBar, setOffBar] = useState<ReadonlySet<string>>(new Set());
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  const merged = useRef(new Map<string, Plan>());

  const leave = useCallback((plan: Plan) => {
    const k = plan.ordinal;
    setRetiring(prev => (prev.has(k) ? without(prev, k) : prev));
    setGone(prev => (prev.has(k) ? prev : new Map(prev).set(k, { plan, at: Date.now() })));
  }, []);

  useEffect(() => {
    const k = (p: Plan) => p.ordinal;
    const live = new Set(plans.map(k));
    // A merged plan the engine already dropped has left the board, whatever its timer says.
    for (const [ordinal, plan] of merged.current) {
      if (live.has(ordinal)) continue;
      clearTimeout(timers.current.get(ordinal));
      merged.current.delete(ordinal);
      leave(plan);
    }
    for (const plan of plans) {
      const id = k(plan);
      if (keepsRow(plan)) {
        // Finished this run: the row stays for the run, so a timer started before the engine said so is called off,
        // and a row that already left comes back. It is still remembered when merged, so that if the snapshot drops
        // it after all, its pill turns purple and leaves the bar as any other gone plan's does.
        clearTimeout(timers.current.get(id));
        timers.current.delete(id);
        setRetiring(prev => (prev.has(id) ? without(prev, id) : prev));
        setGone(prev => (prev.has(id) ? withoutKey(prev, id) : prev));
        if (isMerged(plan)) merged.current.set(id, plan);
        else merged.current.delete(id);
        continue;
      }
      if (!isMerged(plan) || merged.current.has(id)) continue;
      merged.current.set(id, plan);
      timers.current.set(id, setTimeout(() => {
        setRetiring(prev => new Set(prev).add(id));
        timers.current.set(id, setTimeout(() => leave(plan), reduced ? 0 : FADE_MS));
      }, ROW_STAYS_MS));
    }
    setFinishOrder(prev => {
      // Plans that arrive finished together (a page opened mid-run) take the order the engine says they finished in.
      const when = (p: Plan) => p.finished?.at ?? "";
      const fresh = plans
        .filter(p => isFinished(p) && !prev.has(k(p)))
        .sort((a, b) => when(a).localeCompare(when(b)) || k(a).localeCompare(k(b)))
        .map(k);
      if (!fresh.length) return prev;
      const next = new Map(prev);
      for (const id of fresh) next.set(id, next.size + 1);
      return next;
    });
  }, [plans, leave, reduced]);

  useEffect(() => {
    const pending = timers.current;
    const seen = merged.current;
    return () => {
      // Forget them too, so a remount (StrictMode does one) schedules the timers again rather than never.
      for (const t of pending.values()) clearTimeout(t);
      pending.clear();
      seen.clear();
    };
  }, []);

  const dropFromBar = useCallback((ordinal: string) => {
    setOffBar(prev => (prev.has(ordinal) ? prev : new Set(prev).add(ordinal)));
  }, []);

  return { retiring, gone, finishOrder, offBar, dropFromBar };
}
