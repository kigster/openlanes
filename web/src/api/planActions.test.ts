import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ApiError } from "./client";
import { runPlanAction, type PlanOffer } from "./planActions";

const sendCommand = vi.fn();
vi.mock("./useSendCommand", () => ({ sendCommand: (...args: unknown[]) => sendCommand(...args) }));
const postJson = vi.fn();
vi.mock("./client", async (real) => ({ ...(await real<typeof import("./client")>()), postJson: (...args: unknown[]) => postJson(...args) }));

const offer = (over: Partial<PlanOffer> = {}): PlanOffer => ({
  ordinal: "070.00", status: "building", started: true, running: false, depends_on: [], actions: ["discard", "defer"], ...over,
});
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
const sleep = vi.fn(async () => {});

beforeEach(() => { sendCommand.mockReset(); postJson.mockReset(); sleep.mockClear(); });
afterEach(() => vi.useRealTimers());

it("acts at once on a plan nobody is working", async () => {
  postJson.mockResolvedValue(json(offer({ status: "deferred" })));
  expect((await runPlanAction(offer(), "defer", "until Q3", { sleep })).status).toBe("deferred");
  expect(sendCommand).not.toHaveBeenCalled();
  expect(postJson).toHaveBeenCalledWith("/api/plans/070.00/actions", { action: "defer", reason: "until Q3" });
});

it("stops a running plan's agents first, then asks again while they let go", async () => {
  sendCommand.mockResolvedValue({ status: "done" });
  postJson
    .mockResolvedValueOnce(json({ error: "an agent is working on 070.00; stop it first" }, 409))
    .mockResolvedValueOnce(json(offer({ status: "discarded" })));
  expect((await runPlanAction(offer({ running: true }), "discard", "superseded", { sleep })).status).toBe("discarded");
  expect(sendCommand).toHaveBeenCalledWith({ kind: "stop_plan", plan: "070.00", agent: null, payload: {} });
  expect(sleep).toHaveBeenCalledTimes(1);
});

it("gives up when the engine refuses to stop the plan", async () => {
  sendCommand.mockResolvedValue({ status: "refused", reason: "no engine" });
  await expect(runPlanAction(offer({ running: true }), "discard", "x", { sleep })).rejects.toThrow("no engine");
  expect(postJson).not.toHaveBeenCalled();
});

it("does not retry a 409 for a plan it did not stop, or a refusal of another kind", async () => {
  postJson.mockResolvedValue(json({ error: "busy" }, 409));
  await expect(runPlanAction(offer(), "defer", "x", { sleep })).rejects.toBeInstanceOf(ApiError);
  sendCommand.mockResolvedValue({ status: "done" });
  postJson.mockResolvedValue(json({ error: "say why it is discarded" }, 422));
  await expect(runPlanAction(offer({ running: true }), "discard", "", { sleep }))
    .rejects.toThrow("The agents on 070.00 were stopped, but the plan was not moved: say why it is discarded");
  expect(sleep).not.toHaveBeenCalled();
});

it("stops asking once the wait is over", async () => {
  sendCommand.mockResolvedValue({ status: "done" });
  postJson.mockImplementation(async () => json({ error: "still working" }, 409));
  await expect(runPlanAction(offer({ running: true }), "discard", "x", { waitMs: 0, sleep }))
    .rejects.toThrow("The agents on 070.00 were stopped, but the plan was not moved: still working");
});

it("says the agents were stopped when the request itself fails", async () => {
  sendCommand.mockResolvedValue({ status: "done" });
  postJson.mockRejectedValue(new TypeError("Failed to fetch"));
  await expect(runPlanAction(offer({ running: true }), "defer", "x", { sleep }))
    .rejects.toMatchObject({ status: 0, message: "The agents on 070.00 were stopped, but the plan was not moved: Failed to fetch" });
});

it("reads a refusal whose body is not JSON as the fallback", async () => {
  postJson.mockResolvedValue(new Response("<html>bad gateway</html>", { status: 502 }));
  await expect(runPlanAction(offer(), "defer", "x", { sleep })).rejects.toMatchObject({ status: 502 });
});

it("waits on a real timer when no sleep is given", async () => {
  vi.useFakeTimers();
  sendCommand.mockResolvedValue({ status: "done" });
  postJson
    .mockResolvedValueOnce(json({ error: "busy" }, 409))
    .mockResolvedValueOnce(json(offer({ status: "deferred" })));
  const run = runPlanAction(offer({ running: true }), "defer", "x", { pollMs: 50 });
  await vi.advanceTimersByTimeAsync(50);
  expect((await run).status).toBe("deferred");
});
