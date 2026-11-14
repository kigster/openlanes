// A plan's documents for the lane dropdown. Disabled (narrow lanes, other machines' rows) it asks the server nothing.
import { useQuery } from "@tanstack/react-query";
import { listPlanFiles } from "../api/planFiles";
import { documentsOf, type Document } from "./documents";

export function useDocuments(ordinal: string, enabled: boolean): { documents: Document[]; loading: boolean; error: Error | null } {
  const query = useQuery({
    queryKey: ["plan-files", ordinal],
    queryFn: () => listPlanFiles(ordinal),
    staleTime: 30_000,
    enabled,
  });
  return {
    documents: query.data ? documentsOf(query.data) : [],
    loading: enabled && query.isPending,
    error: query.error ?? null,
  };
}
