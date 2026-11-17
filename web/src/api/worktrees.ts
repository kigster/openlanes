// The Worktrees page's reads: the list, then one worktree's diff and pull requests, each fetched when its panel opens.
import { useQuery } from "@tanstack/react-query";
import { ApiError } from "./client";

export interface WorktreePlan {
  ordinal: string;
  title: string;
  /** The status key, e.g. "building". */
  status: string;
  /** The status as a person reads it, e.g. "Building". */
  label: string;
  emoji: string;
  /** An agent works the plan right now. */
  working: boolean;
}

export interface Worktree {
  /** Opaque: the server maps it back to a checkout, so no path travels in a URL. */
  id: string;
  path: string;
  /** Empty for a detached HEAD. */
  branch: string;
  plan: WorktreePlan | null;
  /** `git status --short`, one line per file. */
  modified: string[];
  /** Lines added and removed against the default branch, from the files on disk. */
  lines: { added: number; removed: number };
}

export interface WorktreeDiff {
  stat: string;
  patch: string;
  truncated: boolean;
  base: string;
  /** GitHub's compare page for the branch; null off GitHub. */
  compare_url: string | null;
}

/** pass, fail, pending, none (no checks), unknown (`gh` could not say). */
export type CiState = "pass" | "fail" | "pending" | "none" | "unknown";

export interface WorktreePull {
  number: number | null;
  title: string;
  url: string;
  state: string;
  ci: CiState;
}

async function get<T>(path: string): Promise<T> {
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as T;
}

export const WORKTREES_KEY = ["worktrees"] as const;

export const useWorktrees = () =>
  useQuery({ queryKey: WORKTREES_KEY, queryFn: async () => (await get<{ worktrees: Worktree[] }>("/api/worktrees")).worktrees });

export const useWorktreeDiff = (id: string, enabled: boolean) =>
  useQuery({ queryKey: ["worktrees", id, "diff"], queryFn: () => get<WorktreeDiff>(`/api/worktrees/${encodeURIComponent(id)}/diff`), enabled });

/** Each pull request's CI is a `gh` call on the server, so this is asked only for the one open panel. */
export const useWorktreePulls = (id: string, enabled: boolean) =>
  useQuery({
    queryKey: ["worktrees", id, "pulls"],
    queryFn: async () => (await get<{ pulls: WorktreePull[] }>(`/api/worktrees/${encodeURIComponent(id)}/pulls`)).pulls,
    enabled,
  });
