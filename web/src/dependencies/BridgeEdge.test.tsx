import { fireEvent, render, screen } from "@testing-library/react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { Position, type Edge, type EdgeProps } from "@xyflow/react";
import { BridgeEdge, type BridgeData } from "./BridgeEdge";

const props = {
  id: "b", source: "001.00", target: "003.00", sourceX: 0, sourceY: 0, targetX: 200, targetY: 40,
  sourcePosition: Position.Right, targetPosition: Position.Left,
  data: { from: "001.00", to: "003.00", names: ["002.00 Second"] },
} as unknown as EdgeProps<Edge<BridgeData>>;

const draw = () =>
  render(
    <Tooltip.Provider delayDuration={0}>
      <svg>
        <BridgeEdge {...props} />
      </svg>
    </Tooltip.Provider>,
  );

// Entering the arrow opens the tooltip outright: Radix alone waits for a mouse's pointermove (F1 on #234).
it("names the hidden plans while the pointer is over the bridge, and stops when it leaves", async () => {
  draw();
  const bridge = screen.getByLabelText("Bridge 001.00 to 003.00");
  fireEvent.pointerEnter(bridge);
  expect((await screen.findAllByText("Passes through hidden plan: 002.00 Second"))[0]).toBeInTheDocument();
  fireEvent.pointerLeave(bridge);
  expect(screen.queryByText("Passes through hidden plan: 002.00 Second")).toBeNull();
});
