// The handle between the board and the right-hand column. It is a child of `main.layout`, not of the drawer, so it
// does not scroll away with the drawer. A pointer drag, the arrow keys, Home and a double-click all move it.
import { useRef, type KeyboardEvent, type PointerEvent, type RefObject } from "react";
import { SIDE_STEP } from "../floating/useSideWidth";

export interface ColumnDividerProps {
  width: number;
  min: number;
  max: number;
  onResize(px: number): void;
  onNudge(deltaPx: number): void;
  onReset(): void;
  layoutRef: RefObject<HTMLElement | null>;
}

export function ColumnDivider({ width, min, max, onResize, onNudge, onReset, layoutRef }: ColumnDividerProps) {
  // Pointer offset from the column's left edge at pointerdown, so the column does not jump under the pointer.
  const grab = useRef<number | null>(null);

  // The column's right edge: the layout's right edge less its right padding.
  const columnRight = (): number | null => {
    const el = layoutRef.current;
    if (!el) return null;
    const pad = Number.parseFloat(getComputedStyle(el).paddingRight) || 0;
    return el.getBoundingClientRect().right - pad;
  };

  const onPointerDown = (e: PointerEvent<HTMLElement>) => {
    if (e.button !== 0) return;
    const right = columnRight();
    if (right === null) return;
    grab.current = e.clientX - (right - width);
    try {
      e.currentTarget.setPointerCapture?.(e.pointerId);
    } catch {
      // a synthetic pointer id the browser does not know: the drag still works while the pointer stays over the handle
    }
  };
  const onPointerMove = (e: PointerEvent<HTMLElement>) => {
    const right = columnRight();
    if (grab.current === null || right === null) return;
    onResize(right - (e.clientX - grab.current));
  };
  const end = (e: PointerEvent<HTMLElement>) => {
    if (grab.current === null) return;
    grab.current = null;
    e.currentTarget.releasePointerCapture?.(e.pointerId);
  };

  const onKeyDown = (e: KeyboardEvent<HTMLElement>) => {
    // The column is on the right, so moving the boundary left widens it.
    const delta = ({ ArrowLeft: SIDE_STEP, ArrowRight: -SIDE_STEP } as Record<string, number>)[e.key];
    if (e.key === "Home") {
      e.preventDefault();
      onReset();
    } else if (delta) {
      e.preventDefault();
      onNudge(delta);
    }
  };

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize side panel"
      aria-valuenow={width}
      aria-valuemin={min}
      aria-valuemax={max}
      tabIndex={0}
      className="col-divider"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={end}
      onPointerCancel={end}
      onKeyDown={onKeyDown}
      onDoubleClick={onReset}
    />
  );
}
