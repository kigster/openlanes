import { render, screen } from "@testing-library/react";
import { axe } from "vitest-axe";
import { PlanRow, UnackedBadge } from "./PlanRow";
import { sampleBoard, samplePlan } from "./sample";

describe("UnackedBadge", () => {
  it("shows nothing at zero", () => {
    const { container } = render(<UnackedBadge count={0} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("shows the count, warning-styled, and names it for a screen reader", () => {
    const { container } = render(<UnackedBadge count={2} />);
    const badge = container.querySelector(".unacked")!;
    expect(badge).toHaveClass("is-warning");
    expect(badge).toHaveTextContent("✉ 2");
    expect(screen.getByText("2 unacked messages")).toHaveClass("sr-only");
  });

  it("explains in its tooltip who is waiting on whom, and that nothing waits on it", () => {
    const mail = [
      { from: "backend-coder", to: "frontend-coder", count: 4, since: "2026-10-18 09:41:07 AM PDT" },
      { from: "frontend-coder", to: "backend-coder", count: 3, since: "2026-10-18 10:02:11 AM PDT" },
    ];
    const { container } = render(<UnackedBadge count={7} mail={mail} />);
    expect(container.querySelector(".unacked")!.getAttribute("title")).toBe(
      [
        "7 messages between this plan's agents that the recipient has not acked yet:",
        "backend-coder → frontend-coder: 4, oldest 2026-10-18 09:41:07 AM PDT",
        "frontend-coder → backend-coder: 3, oldest 2026-10-18 10:02:11 AM PDT",
        "",
        "A warning only: no round waits on it. It clears when the recipient acks the mail, usually on its next round.",
      ].join("\n"),
    );
  });

  it("says message for one", () => {
    render(<UnackedBadge count={1} />);
    expect(screen.getByText("1 unacked message")).toBeInTheDocument();
  });

  it("rides in the plan row's meta line, accessibly, and only when there is unacked mail", async () => {
    const { stations, models } = sampleBoard().me;
    const { container, rerender } = render(<PlanRow plan={samplePlan()} stations={stations} models={models} />);
    expect(container.querySelector(".plan-meta .unacked")).toBeNull();
    rerender(<PlanRow plan={samplePlan({ unacked: 2 })} stations={stations} models={models} />);
    expect(container.querySelector(".plan-meta .unacked.is-warning")).toHaveTextContent("2");
    expect(await axe(container)).toHaveNoViolations();
  });
});

describe("PlanRow's head", () => {
  // A whole plan used to read 009 beside a sub-plan's 008.01, so the titles after them started at different places.
  it("is the full NNN.MM for whole plans and sub-plans alike", () => {
    const { stations, models } = sampleBoard().me;
    const { container, rerender } = render(<PlanRow plan={samplePlan()} stations={stations} models={models} />);
    expect(container.querySelector(".plan-id")!.firstChild!.textContent).toBe("001.00");
    rerender(<PlanRow plan={samplePlan({ ordinal: "008.01" })} stations={stations} models={models} />);
    expect(container.querySelector(".plan-id")!.firstChild!.textContent).toBe("008.01");
  });

  it("says what its status means and, on the title, what the spec is about", () => {
    const { stations, models } = sampleBoard().me;
    const { container } = render(<PlanRow plan={samplePlan()} stations={stations} models={models} />);
    expect(container.querySelector(".plan-status")).toHaveAttribute("title", "Building: an agent is building the plan's work units");
    expect(container.querySelector(".plan-title")).toHaveAttribute("title", "Agents may write docs and code, but nothing leaves the machine.");
  });
});
