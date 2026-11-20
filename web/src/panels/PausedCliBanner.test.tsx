import { render, screen, within } from "@testing-library/react";
import { axe } from "vitest-axe";
import type { PausedCli } from "../api/types";
import { PausedCliBanner } from "./PausedCliBanner";

const cli = (over: Partial<PausedCli> = {}): PausedCli => ({
  adapter: "claude",
  reason: "OAuth session expired",
  since: "2026-11-12T10:00:00Z",
  ...over,
});

const banner = () => screen.getByRole("region", { name: /paused/ });

describe("PausedCliBanner", () => {
  it("renders nothing when no CLI is paused", () => {
    const { container } = render(<PausedCliBanner paused={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("names the CLI and its own words for why, accessibly", async () => {
    const { container } = render(<PausedCliBanner paused={[cli()]} />);
    expect(banner()).toHaveTextContent("claude paused");
    expect(within(banner()).getByText("OAuth session expired")).toBeInTheDocument();
    expect(banner()).toHaveTextContent("no round is spent");
    expect(within(banner()).getByText(/since/)).toHaveAttribute("datetime", "2026-11-12T10:00:00Z");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("says until when a rate-limit pause lifts, instead of since when", () => {
    render(<PausedCliBanner paused={[cli({ reason: "paused for rate limit", until: "2026-11-12T10:05:00Z" })]} />);
    expect(within(banner()).getByText("paused for rate limit")).toBeInTheDocument();
    expect(within(banner()).getByText(/^until /)).toHaveAttribute("datetime", "2026-11-12T10:05:00Z");
    expect(within(banner()).queryByText(/^since /)).toBeNull();
  });

  it("lists every paused CLI under a count when there are several", () => {
    render(<PausedCliBanner paused={[cli(), cli({ adapter: "codex", reason: "not signed in" })]} />);
    expect(banner()).toHaveTextContent("2 CLIs paused");
    const items = within(banner()).getAllByRole("listitem");
    expect(items.map((i) => i.getAttribute("data-adapter"))).toEqual(["claude", "codex"]);
    expect(items[1]).toHaveTextContent("not signed in");
  });
});
