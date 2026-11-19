import { useEffect, useState } from "react";
import { useWorktrees } from "../api/worktrees";
import { WorktreePanel } from "./WorktreePanel";
import { onRevealWorktree, takePendingWorktree } from "./reveal";
import "./worktrees.css";

/** Every checkout of the repository but the main one, a panel each; at most one panel open at a time. */
export function WorktreesPage() {
  const { data, error, isLoading } = useWorktrees();
  // A worktree picked from the nav menu opens, closing any other: one picked before this page mounted, then each pick.
  const [openId, setOpenId] = useState<string | null>(() => takePendingWorktree());
  useEffect(() => onRevealWorktree(setOpenId), []);
  if (error) return <main className="wt-page" role="alert">Could not list the worktrees: {error.message}</main>;
  if (isLoading || !data) return <main className="wt-page" aria-busy="true">Loading worktrees…</main>;
  return (
    <main className="wt-page">
      <h1>Worktrees</h1>
      {data.length === 0 && <p className="wt-muted">No worktrees besides the main checkout.</p>}
      {data.map(w => (
        <WorktreePanel key={w.id} worktree={w} open={openId === w.id} onToggle={() => setOpenId(id => (id === w.id ? null : w.id))} />
      ))}
    </main>
  );
}
