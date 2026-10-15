import { render, screen, within } from "@testing-library/react";
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

  it("renders one row per agent: agent, source, round, status, next step and note", async () => {
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
    const rows = within(table).getAllByRole("row").slice(1).map((r) => Array.from(r.querySelectorAll("th, td"), (c) => c.textContent));
    expect(rows).toEqual([
      ["rey-frontend", "agent", "1", "Interrupted", "draw the panel", "—"],
      ["luke-backend", "harness", "2", "Interrupted", "—", "harness died"],
    ]);
    expect(await axe(container)).toHaveNoViolations();
  });

  it("shows in the agent drawer for a plan that has records, and not for one without", () => {
    const plan = planAt("005.00");
    const car = carOf(plan, "hansolo-reviewer");
    const props = { car, models: snapshot.models, autocompact: snapshot.autocompact, onCommand: recorder().onCommand, onClose: () => {} };
    const { unmount } = renderPanel(<AgentDrawer plan={{ ...plan, last_known: [] }} {...props} />);
    expect(screen.queryByRole("table")).toBeNull();
    unmount();
    renderPanel(<AgentDrawer plan={{ ...plan, last_known: [sampleLastKnown()] }} {...props} />);
    expect(within(screen.getByRole("table")).getByText("draw the panel")).toBeInTheDocument();
  });
});
