import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import type { LogLine } from "../api/types";
import { Ticker } from "./Ticker";

const line = (text: string, over: Partial<LogLine> = {}): LogLine => ({ at: "2026-11-12T21:47:49Z", source: "engine", level: "info", text, plan: null, ...over });

describe("Ticker", () => {
  it("shows the last three lines that are not debug, newest last, and passes axe", async () => {
    const lines = [line("one"), line("two"), line("noise", { level: "debug" }), line("three", { level: "warn", plan: "066.00" }), line("four", { level: "error" })];
    const { container } = render(<Ticker lines={lines} onOpen={() => {}} />);
    const shown = Array.from(container.querySelectorAll(".ticker-line"));
    expect(shown.map(l => [l.querySelector(".ticker-src")?.textContent, l.querySelector(".ticker-text")?.textContent, l.className.replace("ticker-line ", "")]))
      .toEqual([["engine", "two", "is-info"], ["066.00 engine", "three", "is-warn"], ["engine", "four", "is-error"]]);
    expect(await axe(container)).toHaveNoViolations();
  });

  it("is one button that opens Logs", async () => {
    const onOpen = vi.fn();
    render(<Ticker lines={[line("moved: New to Ready for Planning")]} onOpen={onOpen} />);
    await userEvent.click(screen.getByRole("button", { name: /^Open Logs\. Latest activity: .*moved: New to Ready for Planning$/ }));
    expect(onOpen).toHaveBeenCalledOnce();
  });

  it("holds its place with nothing to press when the log is empty", () => {
    const { container } = render(<Ticker lines={[]} onOpen={() => {}} />);
    expect([screen.queryByRole("button"), container.querySelector(".ticker.is-empty") !== null]).toEqual([null, true]);
  });
});
