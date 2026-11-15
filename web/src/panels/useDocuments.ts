// A plan's documents for the lane dropdown. Disabled (narrow lanes, other machines' rows) it asks the server nothing.
//
// The list is read when the lane mounts, again whenever the board stream shows the plan moved (useBoard invalidates
// this key), and again each time the menu opens (`refetch`). It used to be read once: a control room left open never
// showed a document written later, and a lane whose first read failed had no way to try again.
import { useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { listPlanFiles } from "../api/planFiles";
import { planFilesKey } from "../api/queryClient";
import { documentsOf, type Document } from "./documents";

export interface Documents {
  documents: Document[];
  /** A read is in flight: the first, a retry after a failure, or a refresh behind a list already shown. */
  loading: boolean;
  /** The last read failed. `documents` still holds the last list that was read, if any. */
  error: Error | null;
  /** Reads the list again now, whatever its age. Does nothing while disabled. */
  refetch: () => void;
}

export function useDocuments(ordinal: string, enabled: boolean): Documents {
  const query = useQuery({
    queryKey: planFilesKey(ordinal),
    queryFn: () => listPlanFiles(ordinal),
    staleTime: 30_000,
    enabled,
  });
  const { refetch: read } = query;
  const refetch = useCallback(() => { if (enabled) void read(); }, [enabled, read]);
  return {
    documents: query.data ? documentsOf(query.data) : [],
    loading: enabled && query.isFetching,
    error: query.error ?? null,
    refetch,
  };
}
