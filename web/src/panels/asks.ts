// What a person has done to a request that the snapshot does not know yet: a half-typed answer, "Type something instead",
// a settled note. Needs you, the unblock widget and the drawer read one store, so a draft follows its question from
// one place to another and the choice of words over the options sticks to that question everywhere it shows.
import { createContext, useContext, useEffect, useSyncExternalStore } from "react";
import type { Plan } from "../api/types";

export interface AskState {
  draft: string;
  inWords: boolean;
  /** The sentence that replaces a card once its command was accepted. */
  settled: string | null;
  /** The follow-up the question carried when it was answered: a different one since means the answer was sent back. */
  seen?: string | null;
}

const BLANK: AskState = { draft: "", inWords: false, settled: null };

export class AskStore {
  private states = new Map<string, AskState>();
  private listeners = new Set<() => void>();
  /** Settled requests, in the order they settled, so the rail can sink them below the open ones. */
  private order: string[] = [];

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  get = (id: string): AskState => this.states.get(id) ?? BLANK;

  settledIds = (): string[] => this.order;

  update(id: string, patch: Partial<AskState>): void {
    const next = { ...this.get(id), ...patch };
    this.states.set(id, next);
    if (patch.settled && !this.order.includes(id)) this.order = [...this.order, id];
    for (const l of this.listeners) l();
  }

  /** The question is open again: its answer was not accepted, so the card returns with what the agent said about it. */
  reopen(id: string): void {
    this.states.set(id, { ...this.get(id), settled: null, seen: null });
    this.order = this.order.filter((other) => other !== id);
    for (const l of this.listeners) l();
  }
}

const defaultStore = new AskStore();
export const StoreContext = createContext<AskStore>(defaultStore);

export function useAskStore(): AskStore {
  return useContext(StoreContext);
}

/** One request's local state, and a setter that merges. */
export function useAsk(id: string): [AskState, (patch: Partial<AskState>) => void] {
  const store = useAskStore();
  const state = useSyncExternalStore(store.subscribe, () => store.get(id));
  return [state, (patch) => store.update(id, patch)];
}

/** Every settled request's id and note, oldest first. */
export function useSettled(): Array<{ id: string; note: string }> {
  const store = useAskStore();
  const ids = useSyncExternalStore(store.subscribe, store.settledIds);
  return ids.map((id) => ({ id, note: store.get(id).settled ?? "" }));
}

/**
 * Brings back a question whose answer the agent did not accept.
 *
 * An answered card is hidden for as long as the page lives, and a rejected answer keeps the question's id, so the
 * question a person was asked again never showed: the lane said "Unblock", the rail said nothing waited, and the
 * button had no card to bring forward (plan 045, four answers sent back unseen).
 */
export function useReopened(plans: Plan[]): void {
  const store = useAskStore();
  useEffect(() => {
    for (const plan of plans) {
      for (const question of plan.questions) {
        const state = store.get(question.id);
        if (state.settled && question.follow_up && question.follow_up !== state.seen) store.reopen(question.id);
      }
    }
  }, [plans, store]);
}
