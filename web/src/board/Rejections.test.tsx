import { render, screen } from "@testing-library/react";
import { axe } from "vitest-axe";
import { PlanRow } from "./PlanRow";
import { sampleBoard, samplePlan } from "./sample";

const { stations, models } = sampleBoard().me;
const row = (over: Parameters<typeof samplePlan>[0]) => render(<PlanRow plan={samplePlan(over)} stations={stations} models={models} />);

describe("plan row rejections and arbitration", () => {
  it("says rejected N of M from rejections", async () => {
    const { container } = row({ rejections: { count: 2, max: 3 } });
    expect(container.querySelector(".plan-meta .rejections")).toHaveTextContent("rejected 2 of 3");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("shows nothing when the count is 0 or the field is absent", () => {
    expect(row({ rejections: { count: 0, max: 3 } }).container.querySelector(".rejections")).toBeNull();
    expect(row({}).container.querySelector(".rejections")).toBeNull();
  });

  it("shows the marker only while arbitrating, and names it for a screen reader", async () => {
    const off = row({ arbitrating: false });
    expect(off.container.querySelector(".arbitrating")).toBeNull();
    off.unmount();
    const on = row({ arbitrating: true });
    expect(on.container.querySelector(".arbitrating")).toHaveTextContent("⚖️");
    expect(screen.getByText("arbitrating")).toHaveClass("sr-only");
    expect(await axe(on.container)).toHaveNoViolations();
  });
});
