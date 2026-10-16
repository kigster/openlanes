// Number and time formats, exactly as the mockup prints them, so counters read the same everywhere.
import type { Node, Snapshot } from "../api/types";

/** 1.24M, 86.0k, 412. */
export const fmt = (n: number): string =>
  n >= 1e6 ? (n / 1e6).toFixed(2) + "M" : n >= 1e3 ? (n / 1e3).toFixed(1) + "k" : String(n);

/** 42s, 3m 07s. A car's elapsed time. */
export const clock = (s: number): string => {
  const secs = Math.max(0, Math.floor(s));
  return secs < 60 ? `${secs}s` : `${Math.floor(secs / 60)}m ${String(secs % 60).padStart(2, "0")}s`;
};

/** clock() under an hour, then 2h 14m. A plan's time on its pill. */
export const span = (s: number): string => {
  const secs = Math.max(0, Math.floor(s));
  return secs < 3600 ? clock(secs) : `${Math.floor(secs / 3600)}h ${String(Math.floor(secs / 60) % 60).padStart(2, "0")}m`;
};

export const dollars = (n: number): string => "$" + n.toFixed(2);

/** Plan numbers are plain NNN (W21) when the ordinal is a whole plan, 001.00; a sub-plan keeps its suffix. */
export const planId = (ordinal: string): string => (ordinal.endsWith(".00") ? ordinal.slice(0, -3) : ordinal);

/**
 * A Redis URL with any userinfo, user name included, replaced by ":***": redis://:***@host:6379/0. The engine already
 * redacts what it sends; this is the page refusing to be the place a password leaks if an older engine did not.
 */
export const redactUrl = (url: string): string => url.replace(/^([a-z][a-z0-9+.-]*:\/\/)[^@/]*@/i, "$1:***@");

export const who = (node: Pick<Node, "user" | "host">): string => `${node.user}@${node.host}`;

/** Whole seconds from `from` to `to`, never negative; 0 when either is missing or unreadable. */
export const secondsBetween = (from: string | null | undefined, to: string | null | undefined): number => {
  if (!from || !to) return 0;
  const d = (Date.parse(to) - Date.parse(from)) / 1000;
  return Number.isFinite(d) && d > 0 ? Math.floor(d) : 0;
};

/** HH:MM:SS in the viewer's time zone, for log lines. */
export const stamp = (iso: string): string => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return [d.getHours(), d.getMinutes(), d.getSeconds()].map(n => String(n).padStart(2, "0")).join(":");
};

/** Seconds since a machine's last heartbeat, measured against our own snapshot's clock rather than the browser's. */
export const lastSeen = (their: Snapshot, me: Snapshot): number => secondsBetween(their.node.heartbeat_at, me.at);
