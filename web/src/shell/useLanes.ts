import { useCallback, useState } from "react";

export type Lanes = "wide" | "narrow";

/** Where the choice is kept: per browser, since how tall a row should be is about the screen, not the run. */
export const LANES_KEY = "openlanes-lanes";

/** The stored choice, wide when there is none or storage cannot be read (a private window, blocked site data). */
export function readLanes(): Lanes {
  try {
    return localStorage.getItem(LANES_KEY) === "narrow" ? "narrow" : "wide";
  } catch {
    return "wide";
  }
}

function writeLanes(lanes: Lanes): void {
  try {
    localStorage.setItem(LANES_KEY, lanes);
  } catch {
    // storage refused: the choice lasts for this visit only
  }
}

/** The top bar's lane-height toggle: wide (every detail, the default) or narrow (half the height). */
export function useLanes(): { lanes: Lanes; toggle: () => void } {
  const [lanes, setLanes] = useState<Lanes>(readLanes);
  const toggle = useCallback(() => {
    setLanes(was => {
      const next: Lanes = was === "narrow" ? "wide" : "narrow";
      writeLanes(next);
      return next;
    });
  }, []);
  return { lanes, toggle };
}
