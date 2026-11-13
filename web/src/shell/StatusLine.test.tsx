import { render, screen } from "@testing-library/react";
import { axe } from "vitest-axe";
import { sampleBoard } from "../board/sample";
import type { Snapshot } from "../api/types";
import { StatusLine } from "./StatusLine";
import { planCounts } from "./planCounts";

const COUNTS = { merged: 1, ready: 1, blocked: 3 };
const me = (over: Partial<Snapshot> = {}): Snapshot => ({ ...sampleBoard().me, ...over });

it("says where the run is, what it has cost and how the plans stand, in one accessible line", async () => {
  const snapshot = me();
  snapshot.run.started_at = "2026-10-13T08:42:00Z";
  const { container } = render(<StatusLine snapshot={snapshot} counts={COUNTS} />);
  expect(screen.getByText("dana@studio-mini")).toBeInTheDocument();
  expect(screen.getByText("18 min")).toBeInTheDocument();
  expect(screen.getByText("agents", { exact: false, selector: ".topbar-stat" })).toHaveTextContent("4 of 4 agents");
  expect(screen.getByText("2.82M")).toBeInTheDocument();
  expect(screen.getByText("$14.80")).toBeInTheDocument();
  expect(screen.getByText("1 merged, 1 ready to merge, 3 blocked")).toBeInTheDocument();
  expect(await axe(container)).toHaveNoViolations();
});

it("breaks only between items: each one is followed by a space", () => {
  const { container } = render(<StatusLine snapshot={me({ redis_url: "redis://localhost:6379/0" })} counts={COUNTS} />);
  const items = Array.from(container.querySelectorAll(".status-item"));
  expect(items.slice(0, -1).every(item => item.nextSibling?.textContent === " ")).toBe(true);
});

it("shows the agents working against the run's limit", () => {
  const snapshot = me();
  snapshot.run.agents_working = 3;
  snapshot.run.jobs = 4;
  render(<StatusLine snapshot={snapshot} counts={COUNTS} />);
  expect(screen.getByText(/agents$/, { selector: ".topbar-stat" })).toHaveTextContent("3 of 4 agents");
});

it("leaves out a missing description", () => {
  const { container } = render(<StatusLine snapshot={me({ description: "" })} counts={COUNTS} />);
  expect(container.querySelector(".status-about")).toBeNull();
});

// Two engines on different Redis servers never see each other's claims, so the line says which one this engine uses.
describe("the Redis the engine uses", () => {
  it("is shown as the engine sent it", () => {
    render(<StatusLine snapshot={me({ redis_url: "redis://localhost:6379/0" })} counts={COUNTS} />);
    expect(screen.getByText("redis://localhost:6379/0")).toBeInTheDocument();
  });

  it("never shows a password or user name, even from an engine that sent one", () => {
    render(<StatusLine snapshot={me({ redis_url: "rediss://dana:hunter2@10.0.4.2:6380/3" })} counts={COUNTS} />);
    expect(screen.getByText("rediss://:***@10.0.4.2:6380/3")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent("hunter2");
  });

  it("is left out when the engine did not say", () => {
    render(<StatusLine snapshot={me({ redis_url: null })} counts={COUNTS} />);
    expect(screen.queryByText(/^Redis/)).toBeNull();
  });
});

it("counts merged, approved and blocked plans, merged ones that left the board included", () => {
  const { me: mine } = sampleBoard();
  const counts = planCounts(mine.plans, mine.stations, new Map());
  const left = mine.plans.find(p => p.pr?.state === "merged") ?? mine.plans[0];
  const without = planCounts(mine.plans, mine.stations, new Map([[left.ordinal, { plan: left, at: 0 }]]));
  expect([counts, without.merged]).toEqual([{ merged: 1, ready: 1, blocked: 3 }, counts.merged]);
});
