import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { sampleLastKnown } from "../board/sample";
import { AgentDrawer } from "./AgentDrawer";
import { LastKnownTable } from "./LastKnownTable";
import { carOf, planAt, recorder, renderPanel, snapshot } from "./testing";

describe("LastKnownTable", () => {
  it("renders nothing for a plan without resume records", () => {
    const { container } = render(<LastKnownTable entries={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("puts the fields down the first column and one agent in each column after it", async () => {
    const { container } = render(
      <LastKnownTable
        entries={[
          sampleLastKnown(),
          sampleLastKnown({ agent: "luke-backend", source: "harness", round: 2, next_step: null, note: "harness died" }),
        ]}
      />,
    );
    const table = screen.getByRole("table");
    expect(screen.getByRole("heading", { name: "Last known state" })).toBeInTheDocument();
    const rows = within(table).getAllByRole("row").map((r) => Array.from(r.querySelectorAll("th, td"), (c) => c.textContent));
    expect(rows).toEqual([
      ["Agent", "rey-frontend", "luke-backend"],
      ["Source", "agent", "harness"],
      ["Round", "1", "2"],
      ["Status", "Interrupted. Next step: draw the panel", "Interrupted"],
      ["Note", "—", "harness died"],
    ]);
    expect(await axe(container)).toHaveNoViolations();
  });

  it("has no next step row, and shows the next step as the status's tooltip on focus", async () => {
    const user = userEvent.setup();
    render(<LastKnownTable entries={[sampleLastKnown()]} />);
    expect(screen.queryByRole("rowheader", { name: "Next step" })).toBeNull();
    expect(screen.queryByRole("tooltip")).toBeNull();
    await user.tab();
    expect(await screen.findByRole("tooltip")).toHaveTextContent("Next step: draw the panel");
  });

  it("shows in the agent drawer for a plan that has records, and not for one without", () => {
    const plan = planAt("005.00");
    const car = carOf(plan, "hansolo-reviewer");
    const props = { car, models: snapshot.models, autocompact: snapshot.autocompact, onCommand: recorder().onCommand, onClose: () => {} };
    const { unmount } = renderPanel(<AgentDrawer plan={{ ...plan, last_known: [] }} {...props} />);
    expect(screen.queryByRole("table")).toBeNull();
    unmount();
    renderPanel(<AgentDrawer plan={{ ...plan, last_known: [sampleLastKnown()] }} {...props} />);
    expect(within(screen.getByRole("table")).getByText(/Next step: draw the panel/)).toBeInTheDocument();
  });
});
