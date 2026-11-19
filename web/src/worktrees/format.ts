// Small words the Worktrees page shows, kept out of the components so they test alone.
import type { CiState } from "../api/worktrees";

/** The folder a worktree lives in, home shortened to ~, so a long temp or home path still fits a heading. */
export const shortPath = (path: string): string => path.replace(/^\/(?:Users|home)\/[^/]+/, "~");

/** What the CI square says when hovered or read aloud. */
export const ciLabel: Record<CiState, string> = {
  pass: "CI passed",
  fail: "CI failed",
  pending: "CI running",
  none: "No CI checks",
  unknown: "CI status unknown",
};

