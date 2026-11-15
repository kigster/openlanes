// `GET /api/plans/:ordinal/review` (contract.md §3): the branch diff and the reviewers' findings for one plan.
import { useQuery } from "@tanstack/react-query";
import { ApiError } from "./client";
import type { PlanReview } from "./types";

export const reviewKey = (ordinal: string) => ["review", ordinal] as const;

export async function fetchPlanReview(ordinal: string): Promise<PlanReview> {
  const path = `/api/plans/${encodeURIComponent(ordinal)}/review`;
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as PlanReview;
}

/** Read only once `enabled`: a row's review is fetched when a person opens it, not for every row on every board. */
export const usePlanReview = (ordinal: string, enabled: boolean) =>
  useQuery<PlanReview>({ queryKey: reviewKey(ordinal), queryFn: () => fetchPlanReview(ordinal), enabled });
