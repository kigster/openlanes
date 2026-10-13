// Where a floating panel sits, and how a person moves it: dragged by its header, nudged by the arrow keys on its grip
// (Shift for bigger steps), put back in its corner by a double-click on the header or Home on the grip. Written once
// for every floating panel on the page (the copilot, W17; the chat between machines, plan 006 D1 and D11), so the two
// cannot drift apart in how they move. Each panel calls it for itself and so holds its own position.
import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type PointerEvent, type RefObject } from "react";

/** The corner a panel docks in, and the edge its minimised tab is fixed to. */
export type Dock = "left" | "right";

/** Top-left corner in viewport pixels, or null while the panel sits docked in its corner. */
export type Position = { x: number; y: number } | null;

/** Pixels kept between a panel and the window's edges, and above whatever `bottomInset` measures. */
export const MARGIN = 8;
/** One arrow key press on the grip; Shift multiplies it. */
export const STEP = 20;
export const BIG_STEP = 80;

/**
 * The status bar's height, read from the page, so a panel never slides under it. Measured rather than read from
 * `--statusbar-h`, so a bar that wraps to a second line is still kept clear.
 */
export const statusBarHeight = (): number => document.querySelector<HTMLElement>(".statusbar")?.offsetHeight ?? 0;

/** The window less its scrollbars, which a panel must not sit under; the whole window where nothing is laid out. */
const viewport = () => ({
  width: document.documentElement.clientWidth || window.innerWidth,
  height: document.documentElement.clientHeight || window.innerHeight,
});

/**
 * Keeps a panel of the given size inside the window and above the bottom inset. When the window is smaller than the
 * panel, its top-left corner wins: the header, which carries the grip and Minimise, stays reachable.
 */
export function clamp(pos: { x: number; y: number }, size: { width: number; height: number }, inset: number): { x: number; y: number } {
  const { width, height } = viewport();
  const x = Math.max(MARGIN, Math.min(pos.x, width - size.width - MARGIN));
  const y = Math.max(MARGIN, Math.min(pos.y, height - inset - size.height - MARGIN));
  return { x, y };
}

/** Controls a pointer may press inside the header without starting a drag. The grip is the one exception. */
const INTERACTIVE = "button:not([data-grip]), a, input, textarea, select, [role=menu]";

export interface FloatingPanelOptions {
  /**
   * What reopening the panel does to a place it was dragged to: `kept` (the copilot) leaves it there for the rest of
   * the visit; `dock` (the chat) sends it back to its corner. A page load always starts docked.
   */
  restore?: "kept" | "dock";
  /** Pixels at the bottom of the window the panel must stay above. */
  bottomInset?: () => number;
}

export interface FloatingPanel {
  panelRef: RefObject<HTMLElement | null>;
  position: Position;
  dragging: boolean;
  /** Back to the docked corner. */
  reset(): void;
  /** Called when the panel is minimised, so `restore: "dock"` can forget where it was. */
  minimised(): void;
  headHandlers: {
    onPointerDown(e: PointerEvent<HTMLElement>): void;
    onPointerMove(e: PointerEvent<HTMLElement>): void;
    onPointerUp(e: PointerEvent<HTMLElement>): void;
    onPointerCancel(e: PointerEvent<HTMLElement>): void;
    onDoubleClick(e: { target: EventTarget }): void;
  };
  onGripKeyDown(e: KeyboardEvent<HTMLElement>): void;
}

export function useFloatingPanel({ restore = "kept", bottomInset = statusBarHeight }: FloatingPanelOptions = {}): FloatingPanel {
  const panelRef = useRef<HTMLElement | null>(null);
  const [position, setPosition] = useState<Position>(null);
  const [dragging, setDragging] = useState(false);
  // The pointer's offset from the panel's corner when the drag began, so the panel does not jump under it.
  const grab = useRef<{ dx: number; dy: number } | null>(null);

  const place = useCallback(
    (pos: { x: number; y: number }) => {
      const rect = panelRef.current?.getBoundingClientRect();
      if (!rect) return;
      setPosition(clamp(pos, rect, bottomInset()));
    },
    [bottomInset],
  );
  const reset = useCallback(() => setPosition(null), []);
  const minimised = useCallback(() => {
    if (restore === "dock") setPosition(null);
  }, [restore]);

  // A window made smaller must not strand a dragged panel off screen.
  useEffect(() => {
    if (!position) return;
    const onResize = () => place(position);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [position, place]);

  const end = (e: PointerEvent<HTMLElement>, drop: boolean) => {
    if (!grab.current) return;
    if (drop) place({ x: e.clientX - grab.current.dx, y: e.clientY - grab.current.dy });
    grab.current = null;
    setDragging(false);
    e.currentTarget.releasePointerCapture?.(e.pointerId);
  };

  const headHandlers: FloatingPanel["headHandlers"] = {
    onPointerDown(e) {
      if (e.button !== 0 || (e.target as Element).closest(INTERACTIVE)) return;
      const rect = panelRef.current?.getBoundingClientRect();
      if (!rect) return;
      grab.current = { dx: e.clientX - rect.left, dy: e.clientY - rect.top };
      setDragging(true);
      e.currentTarget.setPointerCapture?.(e.pointerId);
    },
    onPointerMove(e) {
      if (grab.current) place({ x: e.clientX - grab.current.dx, y: e.clientY - grab.current.dy });
    },
    onPointerUp: e => end(e, true),
    onPointerCancel: e => end(e, false),
    onDoubleClick(e) {
      if (!(e.target as Element).closest(INTERACTIVE)) reset();
    },
  };

  const onGripKeyDown = (e: KeyboardEvent<HTMLElement>) => {
    if (e.key === "Home") {
      e.preventDefault();
      reset();
      return;
    }
    const step = e.shiftKey ? BIG_STEP : STEP;
    const delta = ({ ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] } as Record<string, number[]>)[e.key];
    const rect = panelRef.current?.getBoundingClientRect();
    if (!delta || !rect) return;
    e.preventDefault();
    place({ x: rect.left + delta[0], y: rect.top + delta[1] });
  };

  return { panelRef, position, dragging, reset, minimised, headHandlers, onGripKeyDown };
}
