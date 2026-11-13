import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetSession } from "./client";
import { fetchSettings, saveSettings, SettingsRefusalError, SettingsValidationError, useSaveSettings, useSettings } from "./settings";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const session = () => json({ csrf: "tok", node: {}, repo: "r" });
const doc = { schema: {}, keys: ["jobs"], values: { jobs: 2 }, defaults: {}, etag: "e1", branch: "main" };

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  resetSession();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>
);

describe("fetchSettings", () => {
  it("GETs the document", async () => {
    fetchMock.mockResolvedValue(json(doc));
    expect(await fetchSettings()).toEqual(doc);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/settings");
  });
  it("throws on a failure status", async () => {
    fetchMock.mockResolvedValue(json({}, 500));
    await expect(fetchSettings()).rejects.toMatchObject({ status: 500 });
  });
});

describe("saveSettings", () => {
  it("sends CSRF and If-Match with the values", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ changed: true, commit: "abc", etag: "e2" }));
    expect(await saveSettings({ jobs: 3 }, "e1")).toEqual({ changed: true, commit: "abc", etag: "e2" });
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe("/api/settings");
    expect(init.method).toBe("PUT");
    expect(init.headers).toMatchObject({ "X-CSRF-Token": "tok", "If-Match": "e1" });
    expect(JSON.parse(init.body)).toEqual({ values: { jobs: 3 } });
  });
  it("retries once with a new token after a 403", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({}, 403)).mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ changed: false }));
    expect(await saveSettings({}, "e1")).toEqual({ changed: false });
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });
  it("surfaces a 422 as field errors", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ errors: [{ path: ["merge", "by"], message: "bad" }] }, 422));
    const err = await saveSettings({}, "e1").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(SettingsValidationError);
    expect((err as SettingsValidationError).errors).toEqual([{ path: ["merge", "by"], message: "bad" }]);
  });
  it("tolerates a 422 with no body errors", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(new Response("x", { status: 422 }));
    expect(((await saveSettings({}, "e").catch((e: unknown) => e)) as SettingsValidationError).errors).toEqual([]);
  });
  it("surfaces a 409 as a refusal with its reason", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ refusal: "dirty_config", reason: "edited" }, 409));
    const err = await saveSettings({}, "e1").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(SettingsRefusalError);
    expect(err).toMatchObject({ refusal: "dirty_config", reason: "edited" });
  });
  it("falls back to the kind when a 409 has no reason", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ refusal: "stale_etag" }, 409));
    expect(await saveSettings({}, "e").catch((e: unknown) => e)).toMatchObject({ reason: "stale_etag" });
  });
  it("throws a plain ApiError on anything else", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({}, 500));
    await expect(saveSettings({}, "e")).rejects.toMatchObject({ status: 500 });
  });
});

describe("hooks", () => {
  it("useSettings loads the document", async () => {
    fetchMock.mockResolvedValue(json(doc));
    const { result } = renderHook(() => useSettings(), { wrapper });
    await waitFor(() => expect(result.current.data).toEqual(doc));
  });
  it("useSaveSettings saves", async () => {
    fetchMock.mockResolvedValueOnce(session()).mockResolvedValueOnce(json({ changed: false })).mockResolvedValue(json(doc));
    const { result } = renderHook(() => useSaveSettings(), { wrapper });
    let out: unknown;
    await act(async () => {
      out = await result.current.mutateAsync({ values: {}, etag: "e1" });
    });
    expect(out).toEqual({ changed: false });
  });
});
