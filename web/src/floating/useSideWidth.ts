// How wide the right-hand column is, and whether the page is wide enough to let a person change it. The width is a
// whole number of pixels kept in localStorage, so a reload keeps where the divider was dragged to. It is re-clamped on
// load and on window resize, because a width saved on a large screen may be more than 60% of a small one.
import { useCallback, useEffect, useState, type RefObject } from "react";

export const SIDE_WIDTH_KEY = "openlanes-side-width";
/** The column's narrowest width, in px. */
export const MIN_SIDE = 360;
/** The widest the column starts out: the default is `clamp(360px, 30vw, 432px)`, what the layout was before the divider. */
export const DEFAULT_SIDE_MAX = 432;
const DEFAULT_SIDE_RATIO = 0.3;

/** The width with nothing stored, matching the CSS clamp the layout had before the divider, so nobody's board shifts. */
const defaultWidth = (): number => Math.min(DEFAULT_SIDE_MAX, Math.max(MIN_SIDE, Math.round(window.innerWidth * DEFAULT_SIDE_RATIO)));
/** The widest the column may grow, as a share of the layout's width, so the board always keeps the larger part. */
export const MAX_SIDE_RATIO = 0.6;
/** One arrow key press on the divider. */
export const SIDE_STEP = 24;

/** The divider is absent from the DOM at 960px and below, where the layout is a single column. */
const WIDE = "(min-width: 961px)";

function read(): number | null {
  try {
    const n = Number.parseInt(localStorage.getItem(SIDE_WIDTH_KEY) ?? "", 10);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null; // a private window: the default
  }
}

function write(px: number | null): void {
  try {
    if (px === null) localStorage.removeItem(SIDE_WIDTH_KEY);
    else localStorage.setItem(SIDE_WIDTH_KEY, String(px));
  } catch {
    // a private window: the width lasts for this visit only
  }
}

const matches = (): boolean => window.matchMedia?.(WIDE).matches ?? false;

export interface SideWidth {
  width: number;
  min: number;
  max: number;
  /** True while the window is wider than 960px, the only time the divider exists. */
  wide: boolean;
  setWidth(px: number): void;
  nudge(deltaPx: number): void;
  reset(): void;
}

/**
 * @param layoutRef the element whose width the column's share is measured against
 * @return the column's width, its bounds, and the ways to change it
 */
export function useSideWidth(layoutRef: RefObject<HTMLElement | null>): SideWidth {
  const [stored, setStored] = useState(read);
  const [wide, setWide] = useState(matches);
  // Bumped on window resize so the maximum, which depends on the layout's width, is measured again.
  const [, measure] = useState(0);

  useEffect(() => {
    const mql = window.matchMedia?.(WIDE);
    const onChange = () => setWide(matches());
    const onResize = () => measure(n => n + 1);
    mql?.addEventListener?.("change", onChange);
    window.addEventListener("resize", onResize);
    return () => {
      mql?.removeEventListener?.("change", onChange);
      window.removeEventListener("resize", onResize);
    };
  }, []);

  const layoutWidth = layoutRef.current?.clientWidth || window.innerWidth;
  const min = MIN_SIDE;
  const max = Math.max(min, Math.floor(layoutWidth * MAX_SIDE_RATIO));
  const width = Math.min(max, Math.max(min, stored ?? defaultWidth()));

  const setWidth = useCallback(
    (px: number) => {
      const w = layoutRef.current?.clientWidth || window.innerWidth;
      const next = Math.round(Math.min(Math.max(MIN_SIDE, Math.floor(w * MAX_SIDE_RATIO)), Math.max(MIN_SIDE, px)));
      setStored(next);
      write(next);
    },
    [layoutRef],
  );
  const nudge = useCallback((delta: number) => setWidth(width + delta), [setWidth, width]);
  const reset = useCallback(() => {
    setStored(null);
    write(null);
  }, []);

  return { width, min, max, wide, setWidth, nudge, reset };
}
