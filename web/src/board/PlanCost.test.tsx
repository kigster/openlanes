import { render } from "@testing-library/react";
import { axe } from "vitest-axe";
import { PlanRow } from "./PlanRow";
import { sampleBoard, samplePlan } from "./sample";

const { stations, adapters, node } = sampleBoard().me;

describe("plan row cost", () => {
  it("shows the dollars the plan has spent, named for a screen reader", async () => {
    const { container } = render(<PlanRow plan={samplePlan({ cost: 4.256 })} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-meta .plan-cost")).toHaveTextContent("Spent $4.26");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("shows $0.00 on a plan nobody has worked yet", () => {
    const { container } = render(<PlanRow plan={samplePlan({ cost: 0 })} stations={stations} adapters={adapters} />);
    expect(container.querySelector(".plan-cost")).toHaveTextContent("$0.00");
  });

  it("leaves it off another machine's row, with the tokens", () => {
    const { container } = render(<PlanRow plan={samplePlan({ cost: 4.256 })} stations={stations} adapters={adapters} owner={node} faded />);
    expect(container.querySelector(".plan-cost")).toBeNull();
  });
});
