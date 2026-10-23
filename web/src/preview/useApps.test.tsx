import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import fixture from "../api/fixtures/apps.json";
import { APPS_KEY } from "../api/queryClient";
import type { AppStatus } from "../api/types";
import { useApps } from "./useApps";

function setup() {
  const client = new QueryClient();
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return { client, ...renderHook(() => useApps(), { wrapper }) };
}

it("starts with no apps, so no Preview tab", () => {
  expect(setup().result.current).toEqual([]);
});

it("follows the cache the event stream fills", async () => {
  const { client, result } = setup();
  act(() => client.setQueryData<AppStatus[]>(APPS_KEY, fixture.apps as AppStatus[]));
  await waitFor(() => expect(result.current).toHaveLength(1));
  expect(result.current[0].plan).toBe("012.00");
});
