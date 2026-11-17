import { useEffect, useRef, useState, type ReactNode } from "react";
import type { Snapshot } from "../api/types";
import type { ConnectionState } from "../api/events";
import { useNavHidden } from "./useNavHidden";
import { usePhone } from "./usePhone";
import logo from "../assets/logo.png";

export interface HeaderProps {
  snapshot: Snapshot;
  connection: ConnectionState;
  /** Under `?fixture`: a badge says the numbers are the sample file's. */
  fixture?: boolean;
  /** All machines is on. */
  merged: boolean;
  onToggleMerged: () => void;
  /** Narrow lanes is on: rows at half height, the least important details dropped. */
  narrow?: boolean;
  onToggleNarrow?: () => void;
  /** Hide Inactive is on: only lanes with an agent running are on the board. */
  hideInactive?: boolean;
  onToggleHideInactive?: () => void;
  /** The Actions ▾ menu: ActionMenu from src/panels. */
  actionMenu?: ReactNode;
  /** Restart Control Room and its confirmation: RestartWebDialog from src/panels, shown just before Stop Local Workers. */
  restartWeb?: ReactNode;
  /** Stop Local Workers and its confirmation: StopAllDialog from src/panels, which brings its own button. */
  stopAll?: ReactNode;
  /** Clock override in epoch ms, for tests; the page ticks its own every few seconds. */
  now?: number;
}

/** A snapshot older than this, while the stream says live, means the engine stopped publishing. */
export const STALE_AFTER_SECONDS = 15;

/** Epoch ms, refreshed every 5 s so a stale snapshot is noticed while nothing else re-renders. */
function useNow(override?: number): number {
  const [tick, setTick] = useState(() => Date.now());
  useEffect(() => {
    if (override !== undefined) return;
    const id = setInterval(() => setTick(Date.now()), 5000);
    return () => clearInterval(id);
  }, [override]);
  return override ?? tick;
}

/** A toggle in the nav: a pill with a checkbox drawn in it. Still a pressed-or-not button, which is what it is. */
function Toggle({ on, onClick, title, children }: { on: boolean; onClick: () => void; title: string; children: ReactNode }) {
  return (
    <button className="btn nav-pill nav-toggle" type="button" aria-pressed={on} title={title} onClick={onClick}>
      <span className="nav-check" aria-hidden="true">{on ? "✓" : ""}</span>
      {children}
    </button>
  );
}

/** Clicks inside a menu or dialog a pill opened are not "outside": both render in a portal, away from the nav. */
const PORTALLED = '[role="menu"], [role="dialog"], [role="alertdialog"], [data-radix-popper-content-wrapper]';

/**
 * The run's controls. Wide, they are a row of pills. Under 1180px (shell.css) the row is hidden behind a Menu button
 * and opens as a panel below the bar; the pills are the same elements either way, so nothing is built twice.
 * On a phone the toggles leave that panel for a strip of their own under the bar, again by CSS alone: a second set
 * of them for the strip would be announced twice, and `getByRole` would find two of each.
 */
function Nav({ toggles, children }: { toggles: ReactNode; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const nav = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!open) return;
    const outside = (e: PointerEvent) => {
      const target = e.target as Element | null;
      if (target && (nav.current?.contains(target) || target.closest(PORTALLED))) return;
      setOpen(false);
    };
    const escape = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("pointerdown", outside);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", outside);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);
  return (
    <nav className="nav" aria-label="Run controls" ref={nav} data-open={open || undefined}>
      <button className="btn nav-pill nav-burger" type="button" aria-expanded={open} aria-controls="nav-items" onClick={() => setOpen(was => !was)}>
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
          <path d="M4 7h16M4 12h16M4 17h16" />
        </svg>
        <span className="nav-burger-label">Menu</span>
      </button>
      <div className="nav-items" id="nav-items">
        <div className="nav-toggles">{toggles}</div>
        <div className="nav-actions">{children}</div>
      </div>
    </nav>
  );
}

/**
 * The top bar: the logo and the run-wide controls as pills; the theme and help buttons sit in the page nav above it. The run's numbers are in
 * StatusLine. The outage notices sit outside the row a phone can hide, so hiding the bar never hides an alarm.
 */
export function Header({ snapshot, connection, fixture = false, merged, onToggleMerged, narrow = false, onToggleNarrow, hideInactive = false, onToggleHideInactive, actionMenu, restartWeb, stopAll, now }: HeaderProps) {
  const { run } = snapshot;
  const clock = useNow(now);
  // The engine cannot publish while Redis is gone, so a silent snapshot is the only live signal (plan 022).
  const silent = Math.floor((clock - Date.parse(snapshot.at)) / 1000);
  const stale = connection === "live" && silent > STALE_AFTER_SECONDS;
  const { outage } = run;
  // The project is openlanes itself when the tool works on its own repository, and the logo already says so (W18).
  const titled = snapshot.project.toLowerCase() !== "openlanes";
  // Only a phone pins the bar to the top of the screen, so only there is it worth hiding: a choice stored on a phone
  // does nothing on a wide page, where the bar scrolls away by itself and nothing would bring it back.
  const phone = usePhone();
  const bar = useNavHidden();
  const hidden = phone && bar.hidden;
  const hide = useRef<HTMLButtonElement>(null);
  const restore = useRef<HTMLButtonElement>(null);
  // A press swaps one button for the other, and focus goes with it: left on a button that just vanished, the next
  // Tab started again from the top of the page. Only a press moves it, never the first render.
  const pressed = useRef(false);
  useEffect(() => {
    if (!pressed.current) return;
    pressed.current = false;
    (hidden ? restore : hide).current?.focus();
  }, [hidden]);
  const toggleBar = () => {
    pressed.current = true;
    bar.toggle();
  };
  return (
    <header className="topbar">
      {/* The row stays mounted while hidden, so an open menu, the theme and the toggles are as they were on return. */}
      <div className="topbar-row" id="topbar-row" hidden={hidden}>
        <span className="logo" title="openlanes: the self-running software factory">
          <img src={logo} alt="openlanes" height={30} />
        </span>
        {titled ? <h1 className="project-title">{snapshot.project}</h1> : <h1 className="sr-only">OpenLanes control room</h1>}
        <Nav
          toggles={
            <>
              <Toggle on={merged} onClick={onToggleMerged} title="Show every machine's plans on one board: ours first, theirs below and faded">
                All Machines
              </Toggle>
              {onToggleNarrow && (
                <Toggle on={narrow} onClick={onToggleNarrow} title="Narrow lanes: half-height rows with the plan number, status, title and agents; tokens, lane and activity lines left to the drawer">
                  Narrow Lanes
                </Toggle>
              )}
              {onToggleHideInactive && (
                <Toggle on={hideInactive} onClick={onToggleHideInactive} title="Show only the lanes with an agent running right now. Lanes that are waiting, blocked or finished come back when you turn this off">
                  Hide Inactive
                </Toggle>
              )}
            </>
          }
        >
          {actionMenu}
          {restartWeb}
          {stopAll}
        </Nav>
        <span className="topbar-spacer" />
        {fixture && (
          <span className="sample" title="Served from web/src/api/fixtures/board.json because the URL has ?fixture">
            Fixture data
          </span>
        )}
        {connection !== "live" && (
          <span className={`conn is-${connection}`} role="status">
            {connection === "offline" ? "Offline, retrying" : "Reconnecting…"}
          </span>
        )}
        {phone && (
          <button className="btn btn-quiet btn-icon nav-hide" type="button" ref={hide} aria-expanded="true" aria-controls="topbar-row" aria-label="Hide navigation" title="Hide this bar. A Nav button at the top of the screen brings it back" onClick={toggleBar}>
            <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 15l6-6 6 6" />
            </svg>
          </button>
        )}
      </div>
      {hidden && (
        <button className="btn nav-restore" type="button" ref={restore} aria-expanded="false" aria-controls="topbar-row" title="Show the navigation bar" onClick={toggleBar}>
          Nav
          <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 9l6 6 6-6" />
          </svg>
        </button>
      )}
      {stale && (
        <p className="outage-notice is-stale" role="alert">
          Engine not publishing for {silent} s, Redis may be down
        </p>
      )}
      {outage && (
        <p className="outage-notice is-recovered" role="status" data-testid="outage-recovered">
          Redis was down {outage.seconds} s (by {outage.measured_by}), run state from {outage.reconciled_from ?? "nowhere"}
        </p>
      )}
    </header>
  );
}
