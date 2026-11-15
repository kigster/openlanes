// A coding CLI the engine stopped starting agents on (plan 065): after an authentication failure it waits for the CLI's
// probe to pass, and no agent on that CLI spends a round meanwhile. Agents on every other CLI carry on, so the band names
// the CLI and its own words for why, instead of leaving a quiet board to look like a hang.
import { useId } from "react";
import type { PausedCli } from "../api/types";

export interface PausedCliBannerProps {
  /** `snapshot.paused_clis` of this machine; empty, or absent on an older engine, draws nothing. */
  paused: PausedCli[];
}

const when = (iso: string): string =>
  new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function PausedCliBanner({ paused }: PausedCliBannerProps) {
  const id = useId();
  if (paused.length === 0) return null;
  return (
    <section className="paused-clis" aria-labelledby={`${id}-title`} role="region">
      <h2 id={`${id}-title`} className="paused-clis-title">
        <span aria-hidden="true">⏸ </span>
        {paused.length === 1 ? `${paused[0].adapter} paused` : `${paused.length} CLIs paused`}
      </h2>
      <ul>
        {paused.map((p) => (
          <li key={p.adapter} className="paused-cli" data-adapter={p.adapter}>
            <strong>{p.adapter}</strong>
            <span>{p.reason}</span>
            <time className="paused-cli-since" dateTime={p.since}>since {when(p.since)}</time>
          </li>
        ))}
      </ul>
      <p className="paused-clis-note">
        No agent starts on a paused CLI, and no round is spent, until its probe passes. Agents on other CLIs keep running.
      </p>
    </section>
  );
}
