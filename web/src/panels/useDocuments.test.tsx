import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useDocuments } from "./useDocuments";

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

function wrapper() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("useDocuments", () => {
  it("makes no request while disabled", () => {
    const { result } = renderHook(() => useDocuments("070.00", false), { wrapper: wrapper() });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.current).toEqual({ documents: [], loading: false, error: null });
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
});
