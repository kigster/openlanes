import type { ReactNode } from "react";
import type { Snapshot } from "../api/types";
import type { ConnectionState } from "../api/events";
import { dollars, fmt, secondsBetween, who } from "../board/format";
import { useTheme } from "./useTheme";
import onLight from "../assets/logo-on-light.png";
import onDark from "../assets/logo-on-dark.png";

export interface HeaderProps {
  snapshot: Snapshot;
  connection: ConnectionState;
  /** Under `?fixture`: a badge says the numbers are the sample file's. */
  fixture?: boolean;
  /** All machines is on. */
  merged: boolean;
  onToggleMerged: () => void;
  /** The Action ▾ menu: ActionMenu from src/panels. */
  actionMenu?: ReactNode;
  /** Stop All Local and its confirmation: StopAllDialog from src/panels, which brings its own button. */
  stopAll?: ReactNode;
  /** The round ? pill and its dialog: HelpDialog from src/panels. */
  help?: ReactNode;
}

const SUN = (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
  </svg>
);
const MOON = (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round">
    <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" />
  </svg>
);

/** The top bar: the project, this machine, the run's totals as plain text, and the run-wide controls. */
export function Header({ snapshot, connection, fixture = false, merged, onToggleMerged, actionMenu, stopAll, help }: HeaderProps) {
  const { theme, toggle } = useTheme();
  const { node, run } = snapshot;
  const minutes = Math.floor(secondsBetween(run.started_at, snapshot.at) / 60);
  // The project is openlanes itself when the tool works on its own repository, and the logo already says so (W18).
  const titled = snapshot.project.toLowerCase() !== "openlanes";
  const themeLabel = theme === "dark" ? "Switch to light theme" : "Switch to dark theme";
  return (
    <header className="topbar">
      <span className="logo" title="openlanes: the self-running software factory">
        <img className="on-light" src={onLight} alt="openlanes" height={30} />
        <img className="on-dark" src={onDark} alt="openlanes" height={30} />
      </span>
      <div className="project">
        {titled ? <h1 className="project-title">{snapshot.project}</h1> : <h1 className="sr-only">OpenLanes control room</h1>}
        <p className="project-meta">
          {snapshot.description && <span>{snapshot.description}</span>}
          <span className="project-path">{node.checkout}</span>
          <span
            className="node"
            title={`Node ${node.id}, the first 96 bits of SHA-256("${who(node)}").${node.ip ? ` IP ${node.ip}.` : ""} Repository ${snapshot.repo}`}
          >
            On <strong>{who(node)}</strong>
          </span>
        </p>
      </div>
      <span className="topbar-stat">
        Run <strong>{minutes} min</strong>
      </span>
      <span className="topbar-stat">
        <strong>{run.agents_working}</strong> agents working
      </span>
      <span className="topbar-stat" title="Tokens in and out, all plans">
        ↑ <strong>{fmt(run.up)}</strong> &nbsp; ↓ <strong>{fmt(run.down)}</strong>
      </span>
      <span className="topbar-stat">
        <strong>{dollars(run.cost)}</strong> so far
      </span>
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
      <span className="topbar-spacer" />
      <button
        className="btn btn-quiet"
        type="button"
        aria-pressed={merged}
        title="Show every machine's plans on one board: ours first, theirs below and faded"
        onClick={onToggleMerged}
      >
        All machines
      </button>
      {actionMenu}
      <button className="btn btn-quiet btn-icon" type="button" aria-label={themeLabel} title={themeLabel} onClick={toggle}>
        {theme === "dark" ? SUN : MOON}
      </button>
      {stopAll}
      {help}
    </header>
  );
}
