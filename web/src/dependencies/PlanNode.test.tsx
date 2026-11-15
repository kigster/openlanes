import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as Tooltip from "@radix-ui/react-tooltip";
import { ReactFlow } from "@xyflow/react";
import { NO_SUMMARY, PlanNode } from "./PlanNode";
import { graph } from "./fixture";
import { NODE_HEIGHT, NODE_WIDTH } from "./model";

const draw = (i: number) =>
  render(
    <Tooltip.Provider delayDuration={0}>
      <ReactFlow
        nodeTypes={{ plan: PlanNode }}
        nodesDraggable={false}
        panOnDrag={false} // d3-drag reads event.view.document, which user-event does not send
        nodes={[{ id: "n", type: "plan", position: { x: 0, y: 0 }, width: NODE_WIDTH, height: NODE_HEIGHT, data: { plan: graph.plans[i]!, state: graph.states[0] } }]}
      />
    </Tooltip.Provider>,
  );

it("shows the summary on hover", async () => {
  draw(0);
  await userEvent.hover(await screen.findByRole("button", { name: /First/ }));
  expect((await screen.findAllByText("The first plan."))[0]).toBeInTheDocument();
});

it("keeps it open after a click, and shows the fallback when there is none", async () => {
  draw(1);
  const box = await screen.findByRole("button", { name: /Second/ });
  await userEvent.click(box);
  expect(box).toHaveAttribute("aria-pressed", "true");
  expect((await screen.findAllByText(NO_SUMMARY))[0]).toBeInTheDocument();
  await userEvent.unhover(box);
  expect(screen.getAllByText(NO_SUMMARY)[0]).toBeInTheDocument();
});
