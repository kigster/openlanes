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
