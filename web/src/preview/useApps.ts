import { useQuery } from "@tanstack/react-query";
import { APPS_KEY } from "../api/queryClient";
import type { AppStatus } from "../api/types";
import { runningApps, type RunningApp } from "./model";

const NONE: AppStatus[] = [];

/**
 * The apps running on this machine, one per Preview tab. Filled by useBoard's event stream only: there is nothing to
 * fetch, so the query never runs and starts empty.
 */
export function useApps(): RunningApp[] {
  const { data } = useQuery<AppStatus[]>({ queryKey: APPS_KEY, queryFn: () => NONE, enabled: false, initialData: NONE });
  return runningApps(data);
}
