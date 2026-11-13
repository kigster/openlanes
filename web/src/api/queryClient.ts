import { QueryClient } from "@tanstack/react-query";

export const BOARD_KEY = ["board"] as const;
export const COPILOT_KEY = ["copilot"] as const;
/** The apps running on this machine (plan 012), filled only by the event stream. */
export const APPS_KEY = ["apps"] as const;
/** The plan dependency graph (plan 056), refetched when a board snapshot says a plan moved. */
export const DEPENDENCIES_KEY = ["dependencies"] as const;

/**
 * The board is pushed, not polled: the stream replaces it on every snapshot, so nothing here refetches on focus or
 * goes stale on a timer.
 */
export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { staleTime: Infinity, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 2 },
      mutations: { retry: false },
    },
  });
}
