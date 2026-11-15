// Whether the page is at phone size. One number says so for all of the script, and shell.css repeats it in its
// `(max-width: 600px)` blocks, which is the only other place it may appear: CSS cannot read a constant from here.
import { useSyncExternalStore } from "react";

/** The widest viewport, in px, that is laid out as a phone. */
export const PHONE_MAX_WIDTH = 600;
export const PHONE_QUERY = `(max-width: ${PHONE_MAX_WIDTH}px)`;

/** The query's list, or null where there is no matchMedia (an old browser, a bare jsdom): never a phone there. */
const list = (): MediaQueryList | null => (typeof window.matchMedia === "function" ? window.matchMedia(PHONE_QUERY) : null);

function subscribe(onChange: () => void): () => void {
  const mql = list();
  mql?.addEventListener?.("change", onChange);
  return () => mql?.removeEventListener?.("change", onChange);
}

const isPhone = (): boolean => list()?.matches ?? false;

/** True while the viewport is at phone size, following a rotation or a resize across the line. */
export function usePhone(): boolean {
  return useSyncExternalStore(subscribe, isPhone, () => false);
}
