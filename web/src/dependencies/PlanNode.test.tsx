import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as Tooltip from "@radix-ui/react-tooltip";
import { NO_SUMMARY, PlanNode } from "./PlanNode";
import { graph } from "./fixture";

const draw = (i: number) =>
  render(
    <Tooltip.Provider delayDuration={0}>
      <PlanNode plan={graph.plans[i]!} state={graph.states[0]} x={0} y={0} />
    </Tooltip.Provider>,
  );

it("shows the summary on hover", async () => {
  draw(0);
  await userEvent.hover(screen.getByRole("button"));
  expect((await screen.findAllByText("The first plan."))[0]).toBeInTheDocument();
});

it("keeps it open after a click, and shows the fallback when there is none", async () => {
  draw(1);
  const box = screen.getByRole("button");
  await userEvent.click(box);
  expect(box).toHaveAttribute("aria-pressed", "true");
  expect((await screen.findAllByText(NO_SUMMARY))[0]).toBeInTheDocument();
  await userEvent.unhover(box);
  expect(screen.getAllByText(NO_SUMMARY)[0]).toBeInTheDocument();
});
