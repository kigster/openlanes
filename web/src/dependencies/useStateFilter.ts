import { useCallback, useMemo, useState } from "react";

export const FILTER_KEY = "openlanes-dependency-states";
/** Off until asked for: finished work crowds the graph. */
/** States whose plans live in the archive subfolders (Tree::INACTIVE_DIRS): the graph starts on live work. */
export const OFF_BY_DEFAULT = ["approved", "deployed", "deferred", "abandoned", "discarded", "trashed"];

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
 * Until a choice is made, every state but the archived ones is checked.
 */
export function useStateFilter(states: string[]) {
  const [chosen, setChosen] = useState<string[] | null>(read);
  const checked = useMemo(
    () => new Set(chosen ?? states.filter(k => !OFF_BY_DEFAULT.includes(k))),
    [chosen, states],
  );
  const toggle = useCallback(
    (key: string) => {
      const next = new Set(checked);
      if (!next.delete(key)) next.add(key);
      const keys = states.filter(k => next.has(k));
      setChosen(keys);
      write(keys);
    },
    [checked, states],
  );
  return { checked, toggle };
}
