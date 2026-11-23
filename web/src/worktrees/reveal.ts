// The Worktrees page's channel for the nav menu: a pick opens that worktree's panel (closing any other) and scrolls to it.
import { revealer, scrollWhenThere } from "../shell/reveal";

/** The DOM id of a worktree's panel. */
export const worktreeAnchor = (id: string): string => `wt-${id.replace(/[^A-Za-z0-9_-]+/g, "-")}`;

export const { reveal: revealWorktree, takePending: takePendingWorktree, onReveal: onRevealWorktree } = revealer("worktrees", id =>
  scrollWhenThere(worktreeAnchor(id)),
);
