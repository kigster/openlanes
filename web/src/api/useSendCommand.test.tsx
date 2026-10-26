import type { ReactNode } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { createQueryClient } from "./queryClient";
import { sendCommand, useSendCommand } from "./useSendCommand";
import { replies } from "./replies";
import { resetSession } from "./client";
import type { Command } from "./types";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
const input: Omit<Command, "id"> = { kind: "hold", plan: "001.00", agent: "backend-coder", payload: {} };

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  resetSession();
  replies.clear();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.unstubAllGlobals();
  window.history.replaceState(null, "", "/");
});

// The POST answers 202 and, as the engine would, a final reply follows on the stream.
const accepting = () =>
  fetchMock.mockImplementation(async (path: string, init?: RequestInit) => {
    if (path === "/api/session") return json(200, { csrf: "t" });
    const { id } = JSON.parse(String(init?.body)) as Command;
    setTimeout(() => replies.deliver({ id, status: "done", reason: null, at: "t" }), 0);
    return json(202, { id, status: "accepted", reason: null, at: "t" });
  });

it("resolves with the final reply from the stream", async () => {
  accepting();
  const reply = await sendCommand(input);
  expect(reply.status).toBe("done");
});

it("returns a refusal at once", async () => {
  fetchMock.mockImplementation(async (path: string) =>
    path === "/api/session" ? json(200, { csrf: "t" }) : json(422, { id: "x", status: "refused", reason: "bad", at: "t" }));
  await expect(sendCommand(input)).resolves.toMatchObject({ status: "refused", reason: "bad" });
});

it("rejects when the POST fails", async () => {
  fetchMock.mockImplementation(async (path: string) => (path === "/api/session" ? json(200, { csrf: "t" }) : json(500, {})));
  await expect(sendCommand(input)).rejects.toThrow("500");
});

it("keeps waiting by the same id when the POST fails ambiguously after sending", async () => {
  let sent = "";
  fetchMock.mockImplementation(async (path: string, init?: RequestInit) => {
    if (path === "/api/session") return json(200, { csrf: "t" });
    sent = (JSON.parse(String(init?.body)) as Command).id;
    setTimeout(() => replies.deliver({ id: sent, status: "done", reason: null, at: "t" }), 0);
    throw new TypeError("Failed to fetch"); // the connection dropped after the body went out
  });
  await expect(sendCommand(input)).resolves.toMatchObject({ status: "done" });
  expect(fetchMock.mock.calls.filter(([p]) => p === "/api/commands")).toHaveLength(1);
});

it("gives up after the timeout when an ambiguous failure never gets a reply", async () => {
  fetchMock.mockImplementation(async (path: string) => {
    if (path === "/api/session") return json(200, { csrf: "t" });
    throw new TypeError("Failed to fetch");
  });
  await expect(sendCommand(input, 20)).rejects.toThrow("No reply to command");
});

it("fails fast when the session cannot be fetched before sending", async () => {
  fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
  await expect(sendCommand(input)).rejects.toThrow("Failed to fetch");
  expect(fetchMock.mock.calls.some(([p]) => p === "/api/commands")).toBe(false);
});

it("answers done locally under ?fixture", async () => {
  window.history.replaceState(null, "", "/?fixture");
  await expect(sendCommand(input)).resolves.toMatchObject({ status: "done" });
  expect(fetchMock).not.toHaveBeenCalled();
});

it("works as a mutation", async () => {
  accepting();
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={createQueryClient()}>{children}</QueryClientProvider>;
  const { result } = renderHook(() => useSendCommand(), { wrapper });
  await act(async () => {
    await result.current.mutateAsync(input);
  });
  await waitFor(() => expect(result.current.data?.status).toBe("done"));
});
