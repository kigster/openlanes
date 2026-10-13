import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { HelpDialog, StopAllDialog } from "./dialogs";
import { IdeaDialog } from "./IdeaDialog";
import { findInline, recorder, renderPanel, typeInEditor } from "./testing";

describe("StopAllDialog", () => {
  it("asks with the live counts, Cancel focused, and passes axe", async () => {
    const user = userEvent.setup();
    const { container } = renderPanel(<StopAllDialog agents={4} plans={3} onCommand={recorder().onCommand} />);
    await user.click(screen.getByRole("button", { name: "Stop All Local" }));
    const dialog = await screen.findByRole("dialog", { name: "Stop all local agents?" });
    expect(dialog).toHaveAccessibleDescription("Are you sure you want to shut down 4 agents currently working on 3 plans, and then the engine and this page? This only affects this machine.");
    expect(screen.getByRole("button", { name: "Cancel" })).toHaveFocus();
    expect(await axe(container.ownerDocument.body)).toHaveNoViolations();
    await user.keyboard("{Enter}");
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByRole("button", { name: "Stop All Local" })).toHaveFocus();
  });

  it("sends stop_all and closes", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<StopAllDialog agents={2} plans={1} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Stop All Local" }));
    await user.click(await screen.findByRole("button", { name: "Stop them" }));
    expect(sent).toEqual([{ kind: "stop_all", plan: null, agent: null, payload: {} }]);
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByTestId("announcer")).toHaveTextContent("Stopping 2 agents on this machine.");
  });

  it("stays open with the reason when refused, and can be controlled", async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    renderPanel(<StopAllDialog open agents={2} plans={1} onOpenChange={onOpenChange} onCommand={recorder("refused", "nothing is running").onCommand} />);
    await user.click(screen.getByRole("button", { name: "Stop them" }));
    expect(await findInline("Refused: nothing is running.")).toBeInTheDocument();
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(onOpenChange).not.toHaveBeenCalled();
  });
});

describe("HelpDialog", () => {
  it("opens from the ? pill, says the draft word for word, and closes on Got it", async () => {
    const user = userEvent.setup();
    renderPanel(<HelpDialog />);
    await user.click(screen.getByRole("button", { name: "How this works" }));
    const dialog = await screen.findByRole("dialog", { name: "How this works" });
    expect(dialog).toHaveTextContent("This is a distributed software factory. Every machine that runs openlanes on this repository and points at the same Redis works on the same set of plans, side by side.");
    expect(dialog).toHaveTextContent("You join by sharing $REDIS_URL. There is no other mechanism: no invitation, no accounts.");
    expect(dialog).toHaveTextContent("Stop All Local stops the agents on this machine, then its engine and this page. The other machines keep running.");
    await user.click(screen.getByRole("button", { name: "Got it" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByRole("button", { name: "How this works" })).toHaveFocus();
  });

  it("closes on Esc", async () => {
    const user = userEvent.setup();
    renderPanel(<HelpDialog />);
    await user.click(screen.getByRole("button", { name: "How this works" }));
    await screen.findByRole("dialog");
    await user.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});

describe("IdeaDialog", () => {
  it("shows the frontmatter form with its explanations, and passes axe", async () => {
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={() => {}} onCommand={recorder().onCommand} />);
    expect(screen.getByRole("group", { name: "Lane" })).toBeInTheDocument();
    expect(screen.getByText("Complex feature engaging all agents; costs the most in tokens.")).toBeInTheDocument();
    expect(screen.getByText(/No sends the spec straight to the copywriter/)).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "Your idea, in Markdown" })).toBeInTheDocument();
    expect(await axe(baseElement)).toHaveNoViolations();
  });

  it("explains each choice and turns research off off the full lane", async () => {
    const user = userEvent.setup();
    renderPanel(<IdeaDialog open onOpenChange={() => {}} onCommand={recorder().onCommand} />);
    await user.click(within(screen.getByRole("group", { name: "Research?" })).getByRole("radio", { name: "Yes" }));
    expect(screen.getByText(/Yes adds a research section/)).toBeInTheDocument();
    await user.click(screen.getByRole("radio", { name: "Quick" }));
    expect(screen.getByText("The plan and quick lanes skip research, so there is nothing to choose.")).toBeInTheDocument();
    expect(within(screen.getByRole("group", { name: "Research?" })).getByRole("radio", { name: "Yes" })).toBeDisabled();
    await user.click(screen.getByRole("radio", { name: "Plan decides" }));
    await user.click(within(screen.getByRole("group", { name: "Front end" })).getByRole("radio", { name: "No" }));
    expect(screen.getByText("A back-end-only feature or task.")).toBeInTheDocument();
    await user.click(screen.getByRole("radio", { name: "Deep" }));
    expect(screen.getByText("xHigh effort.")).toBeInTheDocument();
  });

  it("asks for the idea first, then sends create_plans with the idea and frontmatter", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const onOpenChange = vi.fn();
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={onOpenChange} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Break it into plans" }));
    expect(screen.getByText("Write the idea first. A sentence is enough.")).toBeInTheDocument();
    expect(sent).toHaveLength(0);
    await user.click(within(screen.getByRole("group", { name: "Research?" })).getByRole("radio", { name: "Yes" }));
    await user.click(screen.getByRole("radio", { name: "Plan" }));
    let content!: HTMLElement;
    act(() => { content = typeInEditor(baseElement, "# Budgets\n\nTrack spending."); });
    await act(async () => { fireEvent.keyDown(content, { key: "Enter", code: "Enter", keyCode: 13, ctrlKey: true }); });
    expect(sent).toEqual([{
      kind: "create_plans", plan: null, agent: null,
      payload: { idea: "# Budgets\n\nTrack spending.", frontmatter: { lane: "plan", research: false, frontend: "auto", depth: "auto" } },
    }]);
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(screen.getByTestId("announcer")).toHaveTextContent("Idea sent. Its plans join this run as they are created.");
  });

  it("keeps the idea and shows the reason when refused", async () => {
    const onOpenChange = vi.fn();
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={onOpenChange} onCommand={recorder("refused", "no planner configured").onCommand} />);
    act(() => { typeInEditor(baseElement, "An idea"); });
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
    expect(await findInline("Refused: no planner configured.")).toBeInTheDocument();
    expect(onOpenChange).not.toHaveBeenCalled();
  });

  it("Cancel closes it", async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    renderPanel(<IdeaDialog open onOpenChange={onOpenChange} onCommand={recorder().onCommand} />);
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });
});
