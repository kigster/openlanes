import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { ActionMenu } from "./ActionMenu";
import { findInline, recorder, renderPanel, snapshot } from "./testing";

const open = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(screen.getByRole("button", { name: "Action" }));
  return screen.findByRole("menu");
};

describe("ActionMenu", () => {
  it("offers New idea and Choose an existing plan, and passes axe", async () => {
    const user = userEvent.setup();
    const { container } = renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder().onCommand} />);
    const menu = await open(user);
    expect(within(menu).getByText("Describe it here; plans are created for you")).toBeInTheDocument();
    expect(within(menu).getByText("Add a plan from .plans to this run")).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("moves with the arrow keys and closes with Esc back to the button", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder().onCommand} />);
    screen.getByRole("button", { name: "Action" }).focus();
    await user.keyboard("{ArrowDown}");
    const items = within(await screen.findByRole("menu")).getAllByRole("menuitem");
    await waitFor(() => expect(items[0]).toHaveFocus());
    await user.keyboard("{ArrowDown}");
    expect(items[1]).toHaveFocus();
    await user.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("menu")).toBeNull());
    expect(screen.getByRole("button", { name: "Action" })).toHaveFocus();
  });

  it("New idea opens the idea dialog", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder().onCommand} />);
    await user.click(within(await open(user)).getByText("New idea"));
    expect(await screen.findByRole("dialog", { name: "What is the product or feature you'd like to build?" })).toBeInTheDocument();
  });

  it("swaps to a filterable list of the backlog, blocked plans marked, with ← Back", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder().onCommand} note="Not listed: 001.00 in this run." />);
    await user.click(within(await open(user)).getByText("Choose an existing plan"));
    const menu = screen.getByRole("menu");
    expect(within(menu).getByText("012.00 Linear two-way sync")).toBeInTheDocument();
    expect(within(menu).getByText("Product Block, planning, blocked 🅱️")).toBeInTheDocument();
    expect(within(menu).getByText("New, research")).toBeInTheDocument();
    expect(within(menu).getByText("Not listed: 001.00 in this run.")).toBeInTheDocument();
    const filter = within(menu).getByRole("searchbox", { name: "Filter plans" });
    await waitFor(() => expect(filter).toHaveFocus());
    await user.type(filter, "linear");
    expect(within(menu).queryByText("013.00 Plain NNN plan numbers")).toBeNull();
    await user.clear(filter);
    await user.type(filter, "zzz");
    expect(within(menu).getByText("No plan matches “zzz”.")).toBeInTheDocument();
    await user.clear(filter);
    await user.type(filter, "{ArrowDown}");
    expect(within(menu).getAllByRole("menuitem")[1]).toHaveFocus();
    await user.click(within(menu).getByText("← Back"));
    expect(within(screen.getByRole("menu")).getByText("New idea")).toBeInTheDocument();
  });

  it("sends add_plan for the chosen plan and says so", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={onCommand} />);
    await user.click(within(await open(user)).getByText("Choose an existing plan"));
    await user.click(screen.getByText("012.00 Linear two-way sync"));
    await waitFor(() => expect(sent).toEqual([{ kind: "add_plan", plan: "012.00", agent: null, payload: { ordinal: "012.00" } }]));
    expect(screen.getByTestId("announcer")).toHaveTextContent("012.00 added to this run.");
  });

  it("shows why a plan could not be added", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder("refused", "012.00 was just taken by another machine").onCommand} />);
    await user.click(within(await open(user)).getByText("Choose an existing plan"));
    await user.click(screen.getByText("012.00 Linear two-way sync"));
    expect(await findInline("Refused: 012.00 was just taken by another machine.")).toBeInTheDocument();
  });

  it("says when there is nothing to add", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={[]} onCommand={recorder().onCommand} />);
    await user.click(within(await open(user)).getByText("Choose an existing plan"));
    expect(screen.getByText("Nothing to add: every open plan is already being worked on.")).toBeInTheDocument();
  });
});
