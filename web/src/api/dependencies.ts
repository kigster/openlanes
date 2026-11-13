import { useQuery } from "@tanstack/react-query";
import type { DependencyGraph } from "./types";
import { ApiError } from "./client";

export const DEPENDENCIES_KEY = ["dependencies"] as const;

/** GET /api/dependencies: the plan graph the Plan dependencies page draws. */
export async function fetchDependencies(): Promise<DependencyGraph> {
  const path = "/api/dependencies";
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as DependencyGraph;
}

/**
 * The graph, refetched whenever `stamp` changes. The page passes a signature of the board's plans, so a plan that
 * moved on the SSE stream refetches here; the snapshot itself leaves out the archive, which this page needs.
 */
export function useDependencies(stamp: string) {
  return useQuery({ queryKey: [...DEPENDENCIES_KEY, stamp], queryFn: fetchDependencies, staleTime: 0 });
}
