import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useDocuments } from "./useDocuments";

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

// The page's own defaults but for the retries: a list is never stale on a timer and never refetched on focus.
const newClient = () => new QueryClient({ defaultOptions: { queries: { staleTime: Infinity, refetchOnWindowFocus: false, retry: false } } });
const listing = (...files: string[]) => new Response(JSON.stringify({ files }), { status: 200 });

function wrapper(client = newClient()) {
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("useDocuments", () => {
  it("makes no request while disabled", () => {
    const { result } = renderHook(() => useDocuments("070.00", false), { wrapper: wrapper() });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.current).toMatchObject({ documents: [], loading: false, error: null });
    act(() => result.current.refetch());
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("maps the listed names to labels", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ files: ["spec.md", "plan.md"] }), { status: 200 }));
    const { result } = renderHook(() => useDocuments("070.00", true), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.documents.length).toBe(2));
    expect(result.current.documents.map((d) => d.label)).toEqual(["Specification", "Plan"]);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/plans/070.00/files");
  });

  it("reports an error", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error: "no such plan" }), { status: 404 }));
    const { result } = renderHook(() => useDocuments("999.00", true), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.error).not.toBeNull());
    expect(result.current.documents).toEqual([]);
  });

  it("reads the list again on refetch, however fresh it is", async () => {
    fetchMock.mockImplementation(async () => listing("spec.md"));
    const { result } = renderHook(() => useDocuments("070.00", true), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.documents.map((d) => d.name)).toEqual(["spec.md"]));
    fetchMock.mockImplementation(async () => listing("spec.md", "plan.md", "pull-requests.md"));
    act(() => result.current.refetch());
    await waitFor(() => expect(result.current.documents.map((d) => d.name)).toEqual(["spec.md", "plan.md", "pull-requests.md"]));
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("reads the list again when its key is invalidated, as the board stream does, and drops a file that is gone", async () => {
    fetchMock.mockImplementation(async () => listing("spec.md", "blocked.md"));
    const client = newClient();
    const { result } = renderHook(() => useDocuments("070.00", true), { wrapper: wrapper(client) });
    await waitFor(() => expect(result.current.documents.length).toBe(2));
    fetchMock.mockImplementation(async () => listing("spec.md", "plan.md"));
    await act(() => client.invalidateQueries({ queryKey: ["plan-files", "070.00"] }));
    await waitFor(() => expect(result.current.documents.map((d) => d.name)).toEqual(["spec.md", "plan.md"]));
  });

  it("recovers from a failed read on refetch", async () => {
    fetchMock.mockImplementation(async () => new Response("boom", { status: 500 }));
    const { result } = renderHook(() => useDocuments("070.00", true), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.error).not.toBeNull());
    expect(result.current.loading).toBe(false);
    fetchMock.mockImplementation(async () => listing("spec.md"));
    act(() => result.current.refetch());
    await waitFor(() => expect(result.current.documents.length).toBe(1));
    expect(result.current.error).toBeNull();
  });
});
