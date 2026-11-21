import { useWorktrees } from "../api/worktrees";
import { shortPath } from "./format";

/** The nav's drop-down under "Worktrees": one entry per worktree, by its folder and branch. Mounted only while open. */
export function WorktreesMenu({ onPick }: { onPick: (id: string) => void }) {
  const { data, error } = useWorktrees();
  if (error) return <p className="page-menu-note">Worktrees unavailable</p>;
  if (!data) return <p className="page-menu-note">Loading…</p>;
  if (data.length === 0) return <p className="page-menu-note">No worktrees</p>;
  return (
    <ul>
      {data.map(w => (
        <li key={w.id}>
          <button type="button" onClick={() => onPick(w.id)}>
            {shortPath(w.path)} <span className="wt-menu-branch">{w.branch || "detached"}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
