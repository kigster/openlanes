import { useCallback, useMemo, useState } from "react";
import type { DependencyState } from "../api/types";

export const FILTER_KEY = "openlanes-dependency-states";

function read(): string[] | null {
  try {
    const raw = localStorage.getItem(FILTER_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : null;
    return Array.isArray(parsed) && parsed.every(k => typeof k === "string") ? parsed : null;
  } catch {
    return null; // a private window, or a value someone edited by hand
  }
}

function write(keys: string[]): void {
  try {
    localStorage.setItem(FILTER_KEY, JSON.stringify(keys));
  } catch {
    // a private window: the choice lasts for this visit only
  }
}

/**
 * The checked states. Each project's page is served from its own origin, so localStorage is already per project.
 * Until a choice is made, every state the server does not flag `archived` is checked: the flag comes from
 * Tree::INACTIVE_DIRS, so a new archived state in status.rb is off here without a copy of the list.
 */
export function useStateFilter(states: DependencyState[]) {
  const [chosen, setChosen] = useState<string[] | null>(read);
  const keys = useMemo(() => states.map(s => s.key), [states]);
  const checked = useMemo(
    () => new Set(chosen ?? states.filter(s => !s.archived).map(s => s.key)),
    [chosen, states],
  );
  const toggle = useCallback(
    (key: string) => {
      const next = new Set(checked);
      if (!next.delete(key)) next.add(key);
      const picked = keys.filter(k => next.has(k));
      setChosen(picked);
      write(picked);
    },
    [checked, keys],
  );
  return { checked, toggle };
}
