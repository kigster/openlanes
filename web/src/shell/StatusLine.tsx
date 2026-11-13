// The run's status in words, beside the tabs: what the project is, where it runs, what the run has cost so far, how
// the plans stand, and which Redis holds the run. One line on a wide screen; it wraps between its items as the page
// narrows, and under 1100px it takes a row of its own above the tabs (shell.css).
import type { Snapshot } from "../api/types";
import { dollars, fmt, redactUrl, secondsBetween, who } from "../board/format";
import type { PlanCounts } from "./planCounts";

export function StatusLine({ snapshot, counts }: { snapshot: Snapshot; counts: PlanCounts }) {
  const { node, run } = snapshot;
  const minutes = Math.floor(secondsBetween(run.started_at, snapshot.at) / 60);
  // Each item is followed by a real space, so the line breaks between items and never inside a number.
  return (
    <p className="statusline" data-testid="statusline">
      {snapshot.description && <><span className="status-item status-about">{snapshot.description}</span>{" "}</>}
      <span className="status-item project-path">{node.checkout}</span>{" "}
      <span
        className="status-item node"
        title={`${node.checkout}. Node ${node.id}, the first 96 bits of SHA-256("${who(node)}").${node.ip ? ` IP ${node.ip}.` : ""} Repository ${snapshot.repo}`}
      >
        On <strong>{who(node)}</strong>
      </span>{" "}
      <span className="status-item topbar-stat">
        Run <strong>{minutes} min</strong>
      </span>{" "}
      <span className="status-item topbar-stat">
        <strong>{run.agents_working}</strong> of <strong>{run.jobs}</strong> agents
      </span>{" "}
      <span className="status-item topbar-stat" title="Tokens in and out, all plans">
        ↑ <strong>{fmt(run.up)}</strong> &nbsp; ↓ <strong>{fmt(run.down)}</strong>
      </span>{" "}
      <span className="status-item topbar-stat">
        <strong>{dollars(run.cost)}</strong> so far
      </span>{" "}
      <span className="status-item status-plans">
        {counts.merged} merged, {counts.ready} ready to merge, {counts.blocked} blocked
      </span>
      {snapshot.redis_url && (
        <>
          {" "}
          <span className="status-item status-redis" title="The Redis this machine's engine keeps plan claims, locks and run state in">
            Redis <code>{redactUrl(snapshot.redis_url)}</code>
          </span>
        </>
      )}
    </p>
  );
}
