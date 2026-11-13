import { fetchDependencies } from "./dependencies";
import { graph } from "../dependencies/fixture";

afterEach(() => vi.unstubAllGlobals());

it("GETs /api/dependencies", async () => {
  const fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => graph });
  vi.stubGlobal("fetch", fetch);
  expect(await fetchDependencies()).toEqual(graph);
  expect(fetch.mock.calls[0]![0]).toBe("/api/dependencies");
});

it("throws on an error status", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }));
  await expect(fetchDependencies()).rejects.toThrow("500");
});
