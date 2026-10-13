// A pop-up that floats above the board, docked in a bottom corner, and minimises to a tab fixed to that side's edge.
// The copilot (W17) docks bottom right in blue; the chat between machines (plan 006, D1 and D11) will dock bottom left
// in orange. Everything they share lives here and in useFloatingPanel; what differs is a prop: the dock side, the
// colours (as CSS custom properties), the title and the tab's label.
import { useEffect, useRef, type CSSProperties, type ReactNode, type Ref, type RefObject } from "react";
import { useFloatingPanel, type Dock, type FloatingPanelOptions } from "./useFloatingPanel";
import "./floating.css";

/** A panel's colours. Each is any CSS colour, a custom property included; what is left out keeps floating.css's default. */
export interface PanelColors {
  head: string;
  headInk: string;
  body: string;
  bodyInk: string;
  foot: string;
  footInk: string;
  tab: string;
  tabInk: string;
}

const VARS: Record<keyof PanelColors, string> = {
  head: "--fp-head",
  headInk: "--fp-head-ink",
  body: "--fp-body",
  bodyInk: "--fp-body-ink",
  foot: "--fp-foot",
  footInk: "--fp-foot-ink",
  tab: "--fp-tab",
  tabInk: "--fp-tab-ink",
};

export interface FloatingPanelProps extends FloatingPanelOptions {
  /** Prefixes the ids of the panel, its title and its tab. Unique per page. */
  id: string;
  dock: Dock;
  /** The heading in the panel's header. */
  title: ReactNode;
  /** One line under the title. */
  subtitle?: ReactNode;
  /** What the minimised tab reads, vertically. */
  tabLabel: string;
  /** What the grip says it moves: "the copilot". */
  moves: string;
  open: boolean;
  onOpenChange(open: boolean): void;
  /** Shows a dot on the tab: something was said while the panel was minimised. */
  unread?: boolean;
  colors?: Partial<PanelColors>;
  width?: number;
  height?: number;
  /** What the panel holds; it scrolls. */
  children: ReactNode;
  /** Sits below the body on the footer colour: a composer, usually. */
  footer?: ReactNode;
  /** Announces what is added to the body to screen readers: a conversation is a log. */
  live?: boolean;
  /** The body's accessible name; it scrolls, so it takes focus for keyboard scrolling. */
  bodyLabel: string;
  bodyRef?: Ref<HTMLDivElement>;
  /** What takes focus when a person opens the panel; its heading otherwise. */
  initialFocus?: RefObject<HTMLElement | null>;
  className?: string;
}

export function FloatingPanel({
  id,
  dock,
  title,
  subtitle,
  tabLabel,
  moves,
  open,
  onOpenChange,
  unread = false,
  colors = {},
  width = 440,
  height = 560,
  children,
  footer,
  live = false,
  bodyLabel,
  bodyRef,
  initialFocus,
  className,
  restore,
  bottomInset,
}: FloatingPanelProps) {
  const { panelRef, position, dragging, minimised, headHandlers, onGripKeyDown } = useFloatingPanel({ restore, bottomInset });
  const tabRef = useRef<HTMLButtonElement>(null);
  const titleRef = useRef<HTMLHeadingElement>(null);
  // Focus follows a person's own open or minimise, never the first render: a page load must not steal focus.
  const moved = useRef(false);

  useEffect(() => {
    if (!moved.current) return;
    moved.current = false;
    if (open) (initialFocus?.current ?? titleRef.current)?.focus();
    else tabRef.current?.focus();
  }, [open, initialFocus]);

  const setOpen = (next: boolean) => {
    moved.current = true;
    if (!next) minimised();
    onOpenChange(next);
  };

  const style = {
    "--fp-w": `${width}px`,
    "--fp-h": `${height}px`,
    ...Object.fromEntries(Object.entries(colors).map(([k, v]) => [VARS[k as keyof PanelColors], v])),
    ...(position ? { left: `${position.x}px`, top: `${position.y}px` } : {}),
  } as CSSProperties;
  const tabStyle = Object.fromEntries(
    (["tab", "tabInk"] as const).filter(k => colors[k]).map(k => [VARS[k], colors[k]]),
  ) as CSSProperties;

  return (
    <>
      <button
        ref={tabRef}
        id={`${id}-tab`}
        type="button"
        className="fp-tab"
        data-dock={dock}
        style={tabStyle}
        aria-controls={id}
        aria-expanded={open}
        hidden={open}
        onClick={() => setOpen(true)}
      >
        {unread && <span className="fp-dot" aria-hidden="true" />}
        <span className="fp-tab-label">{tabLabel}</span>
        {unread && <span className="sr-only">, new reply</span>}
      </button>
      <section
        ref={panelRef}
        id={id}
        className={["fp", position ? "is-placed" : "", dragging ? "is-dragging" : "", className ?? ""].filter(Boolean).join(" ")}
        data-dock={dock}
        style={style}
        role="dialog"
        aria-modal="false"
        aria-labelledby={`${id}-title`}
        hidden={!open}
        onKeyDown={e => {
          if (e.key !== "Escape") return;
          // Minimising is all Esc does here: it must not also close whatever else on the page listens for it.
          e.preventDefault();
          e.stopPropagation();
          setOpen(false);
        }}
      >
        <div className="fp-head" title="Drag to move. Double-click to put it back in the corner." {...headHandlers}>
          <button
            type="button"
            className="fp-grip"
            data-grip
            aria-label={`Move ${moves}. Arrow keys move it, Shift moves it further, Home puts it back in the corner.`}
            onKeyDown={onGripKeyDown}
          >
            <span aria-hidden="true">⋮⋮</span>
          </button>
          <div className="fp-titles">
            <h2 id={`${id}-title`} ref={titleRef} tabIndex={-1}>
              {title}
            </h2>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <button type="button" className="btn btn-quiet fp-minimise" onClick={() => setOpen(false)} onDoubleClick={e => e.stopPropagation()}>
            Minimise
          </button>
        </div>
        <div className="fp-body" ref={bodyRef} role={live ? "log" : "group"} aria-label={bodyLabel} tabIndex={0}>
          {children}
        </div>
        {footer && <div className="fp-foot">{footer}</div>}
      </section>
    </>
  );
}
