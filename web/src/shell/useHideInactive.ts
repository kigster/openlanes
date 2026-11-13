import { useCallback, useState } from "react";

/** Where the choice is kept: per browser, like the lane height, since it is about what one person wants on screen. */
export const HIDE_INACTIVE_KEY = "openlanes-hide-inactive";

function read(): boolean {
  try {
    return localStorage.getItem(HIDE_INACTIVE_KEY) === "on";
  } catch {
    return false; // a private window: every lane shows
  }
}

/** The top bar's Hide Inactive toggle: off shows every lane, on leaves only the ones with an agent running. */
export function useHideInactive(): { hidden: boolean; toggle: () => void } {
  const [hidden, setHidden] = useState(read);
  const toggle = useCallback(() => {
    setHidden(was => {
      try {
        localStorage.setItem(HIDE_INACTIVE_KEY, was ? "off" : "on");
      } catch {
        // storage refused: the choice lasts for this visit only
      }
      return !was;
    });
  }, []);
  return { hidden, toggle };
}
