import { useQuery } from "@tanstack/react-query";
import type { DependencyGraph } from "./types";
import { ApiError } from "./client";
import { DEPENDENCIES_KEY } from "./queryClient";

export { DEPENDENCIES_KEY };

/** GET /api/dependencies: the plan graph the Plan dependencies page draws. */
export async function fetchDependencies(): Promise<DependencyGraph> {
  const path = "/api/dependencies";
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as DependencyGraph;
}

/**
 * The graph, under one key. useBoard invalidates it when a board snapshot arrives on the stream, so a plan that moved
 * refetches here while the old graph stays on screen; the snapshot itself leaves out the archive, which this page needs.
 */
export function useDependencies() {
  return useQuery({ queryKey: DEPENDENCIES_KEY, queryFn: fetchDependencies });
}
