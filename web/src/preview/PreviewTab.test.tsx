import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import fixture from "../api/fixtures/apps.json";
import type { AppStatus } from "../api/types";
import { runningApps } from "./model";
import { PreviewTab } from "./PreviewTab";

const apps = fixture.apps as AppStatus[];
const appWith = (web: Partial<AppStatus>) => runningApps(apps.map(a => (a.preview ? { ...a, ...web } : a)))[0];

afterEach(() => vi.unstubAllGlobals());

it("is headed with plan, branch and port", () => {
  render(<PreviewTab app={appWith({})} send={vi.fn()} />);
  expect(screen.getByRole("heading", { name: "012 · kig/012.00-app-runner-and-preview · :11101" })).toBeInTheDocument();
});

it("frames the preview process when the runner says it may", () => {
  render(<PreviewTab app={appWith({ framing: "frame" })} send={vi.fn()} />);
  expect(screen.getByTitle("web of plan 012")).toHaveAttribute("src", "http://127.0.0.1:11101/");
});

it("opens a window instead of framing an app that refuses it", async () => {
  const open = vi.fn();
  vi.stubGlobal("open", open);
  render(<PreviewTab app={appWith({ framing: "window" })} send={vi.fn()} />);
  expect(screen.queryByTitle("web of plan 012")).toBeNull();
  await userEvent.click(screen.getByRole("button", { name: "Open http://127.0.0.1:11101/ in a new window" }));
  expect(open).toHaveBeenCalledWith("http://127.0.0.1:11101/", "_blank", "noopener");
});

it("says the preview process is starting until it is ready", () => {
  render(<PreviewTab app={appWith({ state: "starting", framing: null })} send={vi.fn()} />);
  expect(screen.getByText("web is starting on port 11101…")).toBeInTheDocument();
  expect(screen.queryByTitle("web of plan 012")).toBeNull();
});

it("says the preview process did not start when it failed", () => {
  render(<PreviewTab app={appWith({ state: "failed", framing: null, reason: "exited" })} send={vi.fn()} />);
  expect(screen.getByText("web did not start.")).toBeInTheDocument();
});
