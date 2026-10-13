import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { Logs } from "./Logs";
import type { LogLine } from "../api/types";

const line = (over: Partial<LogLine>): LogLine => ({ at: "2026-10-13T09:00:00Z", source: "engine", level: "info", text: "tick", plan: null, ...over });
const lines: LogLine[] = [
  line({ text: "started luke-backend on 001.00" }),
  line({ source: "api", level: "warn", text: "slow POST" }),
  line({ source: "redis", level: "error", text: "XADD timed out" }),
  line({ level: "debug", text: "polling" }),
];
const list = () => screen.getByRole("list", { name: "Log lines, newest last" });

it("shows every source but debug lines by default, accessibly", async () => {
  const { container } = render(<Logs lines={lines} />);
  expect(within(list()).getAllByRole("listitem")).toHaveLength(3);
  expect(screen.getByRole("button", { name: "redis" })).toHaveAttribute("aria-pressed", "true");
  expect(screen.getByRole("button", { name: "debug" })).toHaveAttribute("aria-pressed", "false");
  expect(screen.getByText("Tailing .openlanes/log/engine.log and .openlanes/log/api.log")).toBeInTheDocument();
  expect(await axe(container)).toHaveNoViolations();
});

it("filters by source, level and text", async () => {
  render(<Logs lines={lines} />);
  await userEvent.click(screen.getByRole("button", { name: "api" }));
  await userEvent.click(screen.getByRole("button", { name: "debug" }));
  expect(within(list()).queryByText("slow POST")).toBeNull();
  expect(within(list()).getByText("polling")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: "api" }));
  await userEvent.type(screen.getByLabelText("Filter log lines"), "LUKE");
  expect(within(list()).getAllByRole("listitem")).toHaveLength(1);
  await userEvent.clear(screen.getByLabelText("Filter log lines"));
  await userEvent.type(screen.getByLabelText("Filter log lines"), "nothing like this");
  expect(screen.getByText("No lines match. Loosen the filters above.")).toBeInTheDocument();
});

it("stops following when scrolled up and resumes at the bottom", async () => {
  render(<Logs lines={lines} />);
  const follow = screen.getByRole("button", { name: "Follow" });
  const el = list();
  Object.defineProperty(el, "scrollHeight", { configurable: true, value: 1000 });
  Object.defineProperty(el, "clientHeight", { configurable: true, value: 200 });
  el.scrollTop = 100;
  fireEvent.scroll(el);
  expect(follow).toHaveAttribute("aria-pressed", "false");
  el.scrollTop = 800;
  fireEvent.scroll(el);
  expect(follow).toHaveAttribute("aria-pressed", "true");
  await userEvent.click(follow);
  expect(follow).toHaveAttribute("aria-pressed", "false");
});
