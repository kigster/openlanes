import { ApiError, fetchBoard, fetchCopilot, getSession, isFixtureMode, loadFixtureBoard, mintCommand, postAppCommand, postCommand, postCopilot, postInterview, resetSession } from "./client";
import type { Command } from "./types";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const session = { csrf: "tok-1", node: {}, repo: "github.com/example-org/example-repo" };
const command: Command = { id: "01J0000000000000000000000", kind: "hold", plan: "001.00", agent: "backend-coder", payload: {} };

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  resetSession();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

describe("isFixtureMode", () => {
  it("is on with ?fixture and off without it", () => {
    expect(isFixtureMode("?fixture")).toBe(true);
    expect(isFixtureMode("?x=1&fixture=1")).toBe(true);
    expect(isFixtureMode("")).toBe(false);
  });

  it("reads the page's own URL by default", () => {
    expect(isFixtureMode()).toBe(false);
  });
});

describe("loadFixtureBoard", () => {
  it("hands out a fresh copy every time", () => {
    const a = loadFixtureBoard();
    a.me.plans.length = 0;
    expect(loadFixtureBoard().me.plans.length).toBeGreaterThan(0);
  });
});

describe("fetchBoard", () => {
  it("returns the board", async () => {
    fetchMock.mockResolvedValue(json(200, { me: 1 }));
    await expect(fetchBoard()).resolves.toEqual({ me: 1 });
    expect(fetchMock).toHaveBeenCalledWith("/api/board", expect.objectContaining({ credentials: "same-origin" }));
  });

  it("throws an ApiError carrying the status", async () => {
    fetchMock.mockResolvedValue(json(503, {}));
    await expect(fetchBoard()).rejects.toMatchObject({ name: "ApiError", status: 503 });
  });
});

describe("getSession", () => {
  it("fetches once and caches", async () => {
    fetchMock.mockResolvedValue(json(200, session));
    await getSession();
    await getSession();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("forgets a failed fetch so the next call tries again", async () => {
    fetchMock.mockResolvedValueOnce(json(500, {})).mockResolvedValueOnce(json(200, session));
    await expect(getSession()).rejects.toBeInstanceOf(ApiError);
    await expect(getSession()).resolves.toEqual(session);
  });
});

describe("mintCommand", () => {
  it("adds a ULID", () => {
    const { id, ...rest } = mintCommand({ kind: "stop_all", plan: null, agent: null, payload: {} });
    expect(id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/);
    expect(rest.kind).toBe("stop_all");
  });
});

describe("postCommand", () => {
  it("sends the token and returns the accepted reply", async () => {
    const reply = { id: command.id, status: "accepted", reason: null, at: "x" };
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(202, reply));
    await expect(postCommand(command)).resolves.toEqual(reply);
    const [path, init] = fetchMock.mock.calls[1];
    expect(path).toBe("/api/commands");
    expect(init.headers["X-CSRF-Token"]).toBe("tok-1");
    expect(JSON.parse(init.body)).toEqual(command);
  });

  it("returns a refusal", async () => {
    const reply = { id: command.id, status: "refused", reason: "no such plan", at: "x" };
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(422, reply));
    await expect(postCommand(command)).resolves.toEqual(reply);
  });

  it("refreshes a stale token once and resends the same command", async () => {
    const reply = { id: command.id, status: "accepted", reason: null, at: "x" };
    fetchMock
      .mockResolvedValueOnce(json(200, session))
      .mockResolvedValueOnce(json(403, {}))
      .mockResolvedValueOnce(json(200, { ...session, csrf: "tok-2" }))
      .mockResolvedValueOnce(json(202, reply));
    await expect(postCommand(command)).resolves.toEqual(reply);
    expect(fetchMock.mock.calls[3][1].headers["X-CSRF-Token"]).toBe("tok-2");
    expect(JSON.parse(fetchMock.mock.calls[3][1].body).id).toBe(command.id);
  });

  it("treats a failed token refresh after a 403 as a definite refusal", async () => {
    fetchMock
      .mockResolvedValueOnce(json(200, session))
      .mockResolvedValueOnce(json(403, {}))
      .mockRejectedValueOnce(new TypeError("Failed to fetch"));
    await expect(postCommand(command)).rejects.toMatchObject({ name: "ApiError", status: 403 });
  });

  it("throws on anything else", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(500, {}));
    await expect(postCommand(command)).rejects.toMatchObject({ status: 500 });
  });
});

describe("the copilot", () => {
  const message = { id: "01JMSG", text: "Why has 001 not moved?" };
  const turn = { ...message, from: "you", kind: "text", at: "x", usage: null };

  it("reads the conversation", async () => {
    fetchMock.mockResolvedValue(json(200, { turns: [], usage: null }));
    await expect(fetchCopilot()).resolves.toEqual({ turns: [], usage: null });
    expect(fetchMock).toHaveBeenCalledWith("/api/copilot", expect.anything());
  });

  it("posts a message with the token and returns the stored turn", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(202, turn));
    await expect(postCopilot(message)).resolves.toEqual(turn);
    const [path, init] = fetchMock.mock.calls[1];
    expect([path, init.headers["X-CSRF-Token"], JSON.parse(init.body)]).toEqual(["/api/copilot", "tok-1", message]);
  });

  it("refreshes a stale token once, like a command", async () => {
    fetchMock
      .mockResolvedValueOnce(json(200, session))
      .mockResolvedValueOnce(json(403, {}))
      .mockResolvedValueOnce(json(200, { ...session, csrf: "tok-2" }))
      .mockResolvedValueOnce(json(202, turn));
    await expect(postCopilot(message)).resolves.toEqual(turn);
    expect(fetchMock.mock.calls[3][1].headers["X-CSRF-Token"]).toBe("tok-2");
  });

  it("rejects with the server's reason on 422, and with the status otherwise", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(422, { error: "a message needs text" }));
    await expect(postCopilot(message)).rejects.toThrow("a message needs text");
    fetchMock.mockResolvedValueOnce(json(422, {}));
    await expect(postCopilot(message)).rejects.toThrow("POST /api/copilot answered 422");
    fetchMock.mockResolvedValueOnce(json(500, {}));
    await expect(postCopilot(message)).rejects.toMatchObject({ status: 500 });
  });

  it("names the path when a 403 cannot be recovered from", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(403, {})).mockResolvedValueOnce(json(500, {}));
    await expect(postCopilot(message)).rejects.toThrow("POST /api/copilot answered 403 and no new session could be fetched");
    expect(ApiError).toBeDefined();
  });
});

describe("the Preview tab's commands", () => {
  const command = { plan: "012.00", action: "restart" as const, target: "backend" };

  it("posts one with the token and returns what the server queued", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(202, command));
    await expect(postAppCommand(command)).resolves.toEqual(command);
    const [path, init] = fetchMock.mock.calls[1];
    expect([path, init.headers["X-CSRF-Token"], JSON.parse(init.body)]).toEqual(["/api/apps/commands", "tok-1", command]);
  });

  it("rejects with the server's reason on 422, and with the status otherwise", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(422, { error: "action must be one of restart, stop" }));
    await expect(postAppCommand(command)).rejects.toThrow("action must be one of restart, stop");
    fetchMock.mockResolvedValueOnce(json(500, {}));
    await expect(postAppCommand(command)).rejects.toThrow("POST /api/apps/commands answered 500");
  });
});

describe("the interview (M6)", () => {
  const questions = [{ context: "Who signs in?", options: ["Anyone", "Staff only"], recommended: 1 }];

  it("posts the idea with the token and returns the questions", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(200, { questions }));
    await expect(postInterview("A staff rota")).resolves.toEqual({ questions });
    const [path, init] = fetchMock.mock.calls[1];
    expect([path, init.headers["X-CSRF-Token"], JSON.parse(init.body)]).toEqual(["/api/interview", "tok-1", { idea: "A staff rota" }]);
  });

  it("passes on the server's reason when there is no interviewer", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(200, { questions: [], reason: "no OPENROUTER_API_KEY" }));
    await expect(postInterview("A staff rota")).resolves.toEqual({ questions: [], reason: "no OPENROUTER_API_KEY" });
  });

  it("answers no questions, naming the status, when the server refuses or fails", async () => {
    fetchMock.mockResolvedValueOnce(json(200, session)).mockResolvedValueOnce(json(422, { error: "idea is blank" }));
    await expect(postInterview(" ")).resolves.toEqual({ questions: [], reason: "POST /api/interview answered 422" });
    fetchMock.mockResolvedValueOnce(json(500, {}));
    await expect(postInterview("A staff rota")).resolves.toEqual({ questions: [], reason: "POST /api/interview answered 500" });
  });
});
