import { useId, useState } from "react";
import { useWorktreePulls, type Worktree } from "../api/worktrees";
import { PlanManagement } from "../board/PlanManagement";
import { FoldToggle } from "../shell/FoldToggle";
import { DiffModal } from "./DiffModal";
import { ciLabel, shortPath } from "./format";
import { worktreeAnchor } from "./reveal";

interface Props {
  worktree: Worktree;
  open: boolean;
  onToggle: () => void;
}

/** One worktree: its folder, branch and line counts always; its plan, files, diff and pull requests once opened. */
export function WorktreePanel({ worktree: w, open, onToggle }: Props) {
  const title = shortPath(w.path);
  return (
    <section id={worktreeAnchor(w.id)} className="wt-pane" aria-label={title}>
      <div className="wt-head">
        <FoldToggle open={open} title={title} onToggle={onToggle} />
        <div className="wt-names">
          <h2 className="wt-path" title={w.path}>{title}</h2>
          <h2 className="wt-branch">{w.branch || "detached HEAD"}</h2>
          <p className="wt-lines" aria-label={`${w.lines.added} lines added, ${w.lines.removed} removed against main`}>
            <span className="wt-add">+{w.lines.added}</span> <span className="wt-del">{"−"}{w.lines.removed}</span>
          </p>
        </div>
      </div>
      {open && <WorktreeBody worktree={w} />}
    </section>
  );
}

function WorktreeBody({ worktree: w }: { worktree: Worktree }) {
  const [files, setFiles] = useState(false);
  const [diff, setDiff] = useState(false);
  const filesId = useId();
  const pulls = useWorktreePulls(w.id, w.plan !== null);
  const count = w.modified.length;
  return (
    <div className="wt-body">
      {w.plan ? (
        <div className="wt-plan">
          <span className="wt-plan-name">Plan {w.plan.ordinal} · {w.plan.title}</span>
          <span className={`wt-state${w.plan.working ? " is-working" : ""}`}>
            {w.plan.emoji} {w.plan.label} · {w.plan.working ? "agent working" : "idle"}
          </span>
          <PlanManagement ordinal={w.plan.ordinal} lazy className="wt-docs" />
        </div>
      ) : (
        <p className="wt-plan wt-muted">No plan on this branch</p>
      )}
      <div className="wt-actions">
        <button type="button" className="btn" aria-expanded={files} aria-controls={filesId} onClick={() => setFiles(f => !f)}>
          {files ? "Hide Modified Files" : "Show Modified Files"} ({count})
        </button>
        <button type="button" className="btn" onClick={() => setDiff(true)}>Show Diff with Main</button>
      </div>
      <pre id={filesId} className="wt-status" hidden={!files} aria-label="git status">
        {count > 0 ? w.modified.join("\n") : "Nothing modified."}
      </pre>
      {w.plan && (
        <div className="wt-pulls">
          {pulls.isLoading && <p className="wt-muted" aria-busy="true">Reading pull requests…</p>}
          {pulls.error && <p className="wt-muted" role="alert">Could not read the pull requests: {pulls.error.message}</p>}
          {pulls.data && pulls.data.length === 0 && <p className="wt-muted">No pull requests yet</p>}
          {pulls.data && pulls.data.length > 0 && (
            <ul aria-label="Pull requests">
              {pulls.data.map(pr => (
                <li key={pr.url || pr.title}>
                  <span className={`wt-ci is-${pr.ci}`} role="img" aria-label={ciLabel[pr.ci]} title={ciLabel[pr.ci]} />
                  <a href={pr.url} target="_blank" rel="noreferrer">
                    {pr.number !== null && `#${pr.number} `}{pr.title}
                  </a>
                  <span className="wt-muted"> {pr.state}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      {diff && <DiffModal worktree={w} onClose={() => setDiff(false)} />}
    </div>
  );
}
