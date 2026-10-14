import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import fixture from "../api/fixtures/apps.json";
import type { AppStatus } from "../api/types";
import { runningApps } from "./model";
import { PreviewToolbar } from "./PreviewToolbar";

const apps = fixture.apps as AppStatus[];
const app = (states: AppStatus["state"][] = ["ready", "ready"], reason: string | null = null) =>
  runningApps(apps.map((a, i) => ({ ...a, state: states[i], reason: states[i] === "failed" ? reason : null })))[0];

afterEach(() => vi.unstubAllGlobals());

it("shows ● running when every process is ready", () => {
  render(<PreviewToolbar app={app()} send={vi.fn()} />);
  expect(screen.getByRole("status")).toHaveTextContent("● running");
});

it("shows restarting while a process comes back", () => {
  render(<PreviewToolbar app={app(["restarting", "ready"])} send={vi.fn()} />);
  expect(screen.getByRole("status")).toHaveTextContent("◐ restarting");
});

it("shows a failure with its process and reason", () => {
  render(<PreviewToolbar app={app(["failed", "ready"], "api exited with status 1")} send={vi.fn()} />);
  expect(screen.getByRole("status")).toHaveTextContent("✕ failed: api: api exited with status 1");
});

it("asks for every process but the previewed one on Restart backend", async () => {
  const send = vi.fn().mockResolvedValue({});
  render(<PreviewToolbar app={app()} send={send} />);
  await userEvent.click(screen.getByRole("button", { name: "Restart backend" }));
  expect(send).toHaveBeenCalledWith({ plan: "012.00", action: "restart", target: "backend" });
});

it("asks the runner to stop on Stop", async () => {
  const send = vi.fn().mockResolvedValue({});
  render(<PreviewToolbar app={app()} send={send} />);
  await userEvent.click(screen.getByRole("button", { name: "Stop" }));
  expect(send).toHaveBeenCalledWith({ plan: "012.00", action: "stop" });
});

it("opens the app in a new window", async () => {
  const open = vi.fn();
  vi.stubGlobal("open", open);
  render(<PreviewToolbar app={app()} send={vi.fn()} />);
  await userEvent.click(screen.getByRole("button", { name: "Open in new window" }));
  expect(open).toHaveBeenCalledWith("http://127.0.0.1:11101/", "_blank", "noopener");
});

it("says why a request was refused", async () => {
  const send = vi.fn().mockRejectedValue(new Error("action must be one of restart, stop"));
  render(<PreviewToolbar app={app()} send={send} />);
  await userEvent.click(screen.getByRole("button", { name: "Stop" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("action must be one of restart, stop");
  await waitFor(() => expect(screen.getByRole("button", { name: "Stop" })).toBeEnabled());
});

it("has no Restart backend to press when the app is only the previewed process", () => {
  const only = runningApps(apps.filter(a => a.preview))[0];
  render(<PreviewToolbar app={only} send={vi.fn()} />);
  expect(screen.getByRole("button", { name: "Restart backend" })).toBeDisabled();
});
