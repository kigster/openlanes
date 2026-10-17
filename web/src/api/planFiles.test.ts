import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listPlanFiles, PlanFileError, readPlanFile, savePlanFile } from "./planFiles";
import { resetSession } from "./client";

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } });

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  resetSession();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

describe("listPlanFiles", () => {
  it("GETs the listing and returns the names", async () => {
    fetchMock.mockResolvedValue(json({ files: ["spec.md", "plan.md"] }));
    expect(await listPlanFiles("017.00")).toEqual(["spec.md", "plan.md"]);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/plans/017.00/files");
  });

  it("returns an empty array for a plan with no files", async () => {
    fetchMock.mockResolvedValue(json({ files: [] }));
    expect(await listPlanFiles("017.00")).toEqual([]);
  });

  it("maps 404 to a PlanFileError", async () => {
    fetchMock.mockResolvedValue(json({ error: "no such plan" }, 404));
    await expect(listPlanFiles("999.00")).rejects.toMatchObject({ status: 404, reason: "no such plan" });
  });
});

describe("readPlanFile", () => {
  it("returns the body and the ETag", async () => {
    fetchMock.mockResolvedValue(new Response("# Hi\n", { status: 200, headers: { ETag: '"abc"' } }));
    expect(await readPlanFile("017.00", "spec.md")).toEqual({ body: "# Hi\n", etag: '"abc"' });
    expect(fetchMock.mock.calls[0][0]).toBe("/api/plans/017.00/files/spec.md");
  });

  it("falls back to an empty ETag and a generic message", async () => {
    fetchMock.mockResolvedValueOnce(new Response("x", { status: 200 }));
    expect((await readPlanFile("017.00", "spec.md")).etag).toBe("");
    fetchMock.mockResolvedValueOnce(new Response("nope", { status: 500 }));
    await expect(readPlanFile("017.00", "spec.md")).rejects.toThrow("GET /api/plans/017.00/files/spec.md answered 500");
  });
});

describe("savePlanFile", () => {
  const session = () => json({ csrf: "tok", node: {}, repo: "r" });

  it("PUTs the whole file with If-Match and the CSRF token", async () => {
    fetchMock.mockResolvedValue(json({}, 200, { ETag: '"new"' }));
    const out = await savePlanFile("017.00", "spec.md", "text", '"old"', "tok");
    expect(out).toEqual({ etag: '"new"' });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/plans/017.00/files/spec.md");
    expect(init.method).toBe("PUT");
    expect(init.body).toBe("text");
    expect(init.headers).toMatchObject({ "If-Match": '"old"', "X-CSRF-Token": "tok", "Content-Type": "text/markdown" });
  });

  it.each([
    [412, "file changed"],
    [409, "a car is working"],
    [422, "frontmatter changed"],
    [428, "If-Match required"],
    [404, "no such file"],
  ])("maps %i to a PlanFileError carrying the reason", async (status, error) => {
    fetchMock.mockResolvedValue(json({ error }, status));
    const err = await savePlanFile("017.00", "spec.md", "t", '"e"', "tok").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(PlanFileError);
    expect(err).toMatchObject({ status, reason: error });
    expect((err as PlanFileError).conflict).toBe(status === 412 || status === 409);
  });

  it("does not retry a 403 that names a read-only file", async () => {
    fetchMock.mockResolvedValue(json({ error: "blocked.md is read only" }, 403));
    await expect(savePlanFile("017.00", "blocked.md", "t", '"e"', "tok")).rejects.toMatchObject({ status: 403 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("fetches a fresh token and retries once after a bare 403", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("", { status: 403 }))
      .mockResolvedValueOnce(session())
      .mockResolvedValueOnce(json({}, 200, { ETag: '"n"' }));
    expect(await savePlanFile("017.00", "spec.md", "t", '"e"', "stale")).toEqual({ etag: '"n"' });
    expect(fetchMock.mock.calls[2][1].headers["X-CSRF-Token"]).toBe("tok");
  });

  it("falls back to the ETag in the JSON body, then to empty", async () => {
    fetchMock.mockResolvedValueOnce(json({ etag: '"b"' }));
    expect(await savePlanFile("017.00", "spec.md", "t", '"e"', "tok")).toEqual({ etag: '"b"' });
    fetchMock.mockResolvedValueOnce(new Response("", { status: 200 }));
    expect(await savePlanFile("017.00", "spec.md", "t", '"e"', "tok")).toEqual({ etag: "" });
  });
});
