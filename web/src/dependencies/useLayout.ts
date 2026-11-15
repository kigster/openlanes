import { useCallback, useState } from "react";
import { LAYOUTS, isLayout, type LayoutKey } from "./layouts";

export const LAYOUT_KEY = "openlanes-dependency-layout";

function read(): LayoutKey {
  try {
    const kept = localStorage.getItem(LAYOUT_KEY);
    return isLayout(kept) ? kept : LAYOUTS[0].key;
  } catch {
    return LAYOUTS[0].key; // a private window
  }
}

/** The arrangement picked, kept per browser like the state filter: it is about how one person likes to read the graph. */
export function useLayout(): { layout: LayoutKey; pick: (kind: LayoutKey) => void } {
  const [layout, setLayout] = useState<LayoutKey>(read);
  const pick = useCallback((kind: LayoutKey) => {
    setLayout(kind);
    try {
      localStorage.setItem(LAYOUT_KEY, kind);
    } catch {
      // storage refused: the choice lasts for this visit only
    }
  }, []);
  return { layout, pick };
}
