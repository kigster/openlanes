import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { PlanRow, UnackedBadge } from "./PlanRow";
import { sampleBoard, samplePlan, sampleQuestion } from "./sample";

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
    const { stations } = sampleBoard().me;
const adapters = sampleBoard().me.adapters;
    const { container, rerender } = render(<PlanRow plan={samplePlan()} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-meta .unacked")).toBeNull();
    rerender(<PlanRow plan={samplePlan({ unacked: 2 })} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-meta .unacked.is-warning")).toHaveTextContent("2");
    expect(await axe(container)).toHaveNoViolations();
  });
});

describe("PlanRow's head", () => {
  // A whole plan used to read 009 beside a sub-plan's 008.01, so the titles after them started at different places.
  it("is the full NNN.MM for whole plans and sub-plans alike", () => {
    const { stations } = sampleBoard().me;
const adapters = sampleBoard().me.adapters;
    const { container, rerender } = render(<PlanRow plan={samplePlan()} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-id")!.firstChild!.textContent).toBe("001.00");
    rerender(<PlanRow plan={samplePlan({ ordinal: "008.01" })} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-id")!.firstChild!.textContent).toBe("008.01");
  });

  it("says what its status means and, on the title, what the spec is about", () => {
    const { stations } = sampleBoard().me;
const adapters = sampleBoard().me.adapters;
    const { container } = render(<PlanRow plan={samplePlan()} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-status")).toHaveAttribute("title", "Building: an agent is building the plan's work units");
    expect(container.querySelector(".plan-title")).toHaveAttribute("title", "Agents may write docs and code, but nothing leaves the machine.");
  });

  it("names the state beside its emoji, so ⭕ is never left to be guessed", () => {
    const { stations, adapters } = sampleBoard().me;
    const blocked = samplePlan({ status: { key: "blocked", emoji: "⭕", label: "Technical Block", note: "cannot proceed" } });
    const { container } = render(<PlanRow plan={blocked} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-id")).toHaveTextContent("001.00⭕(Technical Block)");
    expect(container.querySelector(".plan-state")).toHaveAttribute("aria-hidden", "true");
  });

  it("offers Unblock only on a lane with questions waiting, and hands the plan back", async () => {
    const { stations, adapters } = sampleBoard().me;
    const onUnblock = vi.fn();
    const quiet = samplePlan();
    const asking = samplePlan({ questions: [sampleQuestion(), sampleQuestion({ id: "001.00/B2", number: 2 })] });
    const { rerender } = render(<PlanRow plan={quiet} stations={stations} adapters={adapters} onUnblock={onUnblock} />);
    expect(screen.queryByRole("button", { name: /Unblock/ })).toBeNull();
    rerender(<PlanRow plan={asking} stations={stations} adapters={adapters} onUnblock={onUnblock} />);
    await userEvent.setup().click(screen.getByRole("button", { name: "Unblock 001.00: 2 questions waiting" }));
    expect(onUnblock).toHaveBeenCalledWith(asking);
    // Another machine's row is read only: no button, whatever it is asking.
    rerender(<PlanRow plan={asking} stations={stations} adapters={adapters} owner={sampleBoard().me.node} onUnblock={onUnblock} />);
    expect(screen.queryByRole("button", { name: /Unblock/ })).toBeNull();
  });
});
