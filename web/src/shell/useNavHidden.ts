import { useCallback, useState } from "react";

/** Where the choice is kept: per browser, like the lane height, since it is about how much of one screen the bar may take. */
export const NAV_HIDDEN_KEY = "openlanes-nav-hidden";

function read(): boolean {
  try {
    return localStorage.getItem(NAV_HIDDEN_KEY) === "on";
  } catch {
    return false; // a private window: the bar shows
  }
}

/** The phone's hide-the-bar toggle: off shows the top bar and its strip, on leaves only the Nav button that brings them back. */
export function useNavHidden(): { hidden: boolean; toggle: () => void } {
  const [hidden, setHidden] = useState(read);
  const toggle = useCallback(() => {
    setHidden(was => {
      try {
        localStorage.setItem(NAV_HIDDEN_KEY, was ? "off" : "on");
      } catch {
        // storage refused: the choice lasts for this visit only
      }
      return !was;
    });
  }, []);
  return { hidden, toggle };
}
