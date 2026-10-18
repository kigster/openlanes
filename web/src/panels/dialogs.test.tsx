import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { HelpDialog, StopAllDialog } from "./dialogs";
import { IdeaDialog } from "./IdeaDialog";
import { findInline, recorder, renderPanel, typeInEditor } from "./testing";
import { postInterview } from "../api/client";

// No interviewer unless an example sets one, so the dialog creates the plan as it did before M6.
vi.mock("../api/client", async (original) => ({
  ...(await original<typeof import("../api/client")>()),
  postInterview: vi.fn(async () => ({ questions: [] })),
}));

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
      payload: { idea: "# Budgets\n\nTrack spending.", frontmatter: { lane: "plan", research: false, frontend: "auto", depth: "auto" }, decisions: [] },
    }]);
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(screen.getByTestId("announcer")).toHaveTextContent("Idea sent. Its plans join this run as they are created.");
  });

  it("interviews the idea one question at a time, the recommended answer marked, and sends the decisions (M6)", async () => {
    vi.mocked(postInterview).mockResolvedValueOnce({ questions: [
      { context: "Who opens the export?", options: ["The accountant", "Anyone"], recommended: 0 },
      { context: "Which format?", options: ["CSV", "XLSX"], recommended: 1 },
    ] });
    const { sent, onCommand } = recorder();
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
    act(() => { typeInEditor(baseElement, "Export the ledger"); });
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
    expect(await screen.findByRole("dialog", { name: "Before the spec: question 1 of 2" })).toHaveAccessibleDescription("Who opens the export?");
    expect(screen.getByRole("button", { name: "a) The accountant (Recommended)" })).toBeInTheDocument();
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "a) The accountant (Recommended)" })); });
    expect(screen.getByRole("button", { name: "b) XLSX (Recommended)" })).toBeInTheDocument();
    fireEvent.change(screen.getByRole("textbox", { name: "Type something instead" }), { target: { value: "Both" } });
    await act(async () => { fireEvent.keyDown(screen.getByRole("textbox", { name: "Type something instead" }), { key: "Enter" }); });
    expect(sent[0].payload.decisions).toEqual([
      { question: "Who opens the export?", answer: "a) The accountant" },
      { question: "Which format?", answer: "Both" },
    ]);
  });

  it("lets the interview be skipped, sending no decisions", async () => {
    vi.mocked(postInterview).mockResolvedValueOnce({ questions: [{ context: "Who?", options: ["A", "B"], recommended: 0 }] });
    const { sent, onCommand } = recorder();
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
    act(() => { typeInEditor(baseElement, "Export the ledger"); });
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
    await act(async () => { fireEvent.click(await screen.findByRole("button", { name: "Skip the interview" })); });
    expect(sent[0].payload.decisions).toEqual([]);
  });

  // The interview's lifecycle (Copilot and Grok on #81): a slow interviewer is answered by whatever the person did
  // in the meantime, never by a plan they did not ask for.
  describe("while the questions are being prepared", () => {
    const ONE = { questions: [{ context: "Who?", options: ["A", "B"], recommended: 0 }] };
    const later = () => {
      let resolve!: (value: { questions: { context: string; options: string[]; recommended: number }[] }) => void;
      vi.mocked(postInterview).mockReturnValueOnce(new Promise((r) => { resolve = r; }));
      return (value: Parameters<typeof resolve>[0]) => act(async () => { resolve(value); });
    };
    beforeEach(() => { vi.mocked(postInterview).mockClear(); });
    const ctrlEnter = (el: HTMLElement) => act(async () => { fireEvent.keyDown(el, { key: "Enter", code: "Enter", keyCode: 13, ctrlKey: true }); });

    it("starts one interview and creates one plan however often the shortcut is pressed", async () => {
      const answer = later();
      const { sent, onCommand } = recorder();
      const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
      let content!: HTMLElement;
      act(() => { content = typeInEditor(baseElement, "Export the ledger"); });
      await ctrlEnter(content);
      await ctrlEnter(content);
      await answer({ questions: [] });
      await ctrlEnter(content);
      expect(postInterview).toHaveBeenCalledTimes(1);
      expect(sent).toHaveLength(1);
    });

    it("creates nothing when the dialog is closed before the questions arrive", async () => {
      const answer = later();
      const { sent, onCommand } = recorder();
      const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
      act(() => { typeInEditor(baseElement, "Export the ledger"); });
      await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
      await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Cancel" })); });
      await answer({ questions: [] });
      expect(sent).toHaveLength(0);
    });

    it("drops questions about an idea that was edited while they were prepared", async () => {
      const answer = later();
      const { sent, onCommand } = recorder();
      const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
      act(() => { typeInEditor(baseElement, "Export the ledger"); });
      await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
      act(() => { typeInEditor(baseElement, "Import the ledger"); });
      await answer(ONE);
      expect(screen.getByRole("dialog", { name: "What is the product or feature you'd like to build?" })).toBeInTheDocument();
      expect(sent).toHaveLength(0);
    });

    it("can be skipped, creating the plan as before and ignoring the questions when they come", async () => {
      const answer = later();
      const { sent, onCommand } = recorder();
      const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
      act(() => { typeInEditor(baseElement, "Export the ledger"); });
      await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
      await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Skip the questions" })); });
      await answer(ONE);
      expect(sent.map((c) => c.payload.decisions)).toEqual([[]]);
      expect(screen.queryByRole("dialog", { name: /Before the spec/ })).toBeNull();
    });
  });

  it("keeps the last answer for a retry when creating the plan is refused", async () => {
    vi.mocked(postInterview).mockResolvedValueOnce({ questions: [{ context: "Which format?", options: ["CSV", "XLSX"], recommended: 0 }] });
    const sent: unknown[] = [];
    const replies = ["refused", "accepted"] as const;
    const onCommand = vi.fn(async (c: { payload: Record<string, unknown> }) => {
      sent.push(c.payload.decisions);
      return { id: "01J", status: replies[sent.length - 1], reason: "busy", at: "2026-10-18T09:00:00Z" };
    });
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={vi.fn()} onCommand={onCommand} />);
    act(() => { typeInEditor(baseElement, "Export the ledger"); });
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
    const own = await screen.findByRole("textbox", { name: "Type something instead" });
    fireEvent.change(own, { target: { value: "Both" } });
    await act(async () => { fireEvent.keyDown(own, { key: "Enter" }); });
    expect(screen.getByRole("dialog", { name: "Before the spec: question 1 of 1" })).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "Type something instead" })).toHaveValue("Both");
    await act(async () => { fireEvent.keyDown(screen.getByRole("textbox", { name: "Type something instead" }), { key: "Enter" }); });
    expect(sent).toEqual([[{ question: "Which format?", answer: "Both" }], [{ question: "Which format?", answer: "Both" }]]);
  });

  it("starts over when closed mid-interview, rather than resuming old questions", async () => {
    vi.mocked(postInterview).mockResolvedValueOnce({ questions: [{ context: "Who?", options: ["A", "A"], recommended: 0 }] });
    const onOpenChange = vi.fn();
    const { baseElement } = renderPanel(<IdeaDialog open onOpenChange={onOpenChange} onCommand={recorder().onCommand} />);
    act(() => { typeInEditor(baseElement, "Export the ledger"); });
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Break it into plans" })); });
    // Two identical labels from the model are two answers, not one.
    expect(await screen.findAllByRole("button", { name: /\) A/ })).toHaveLength(2);
    await act(async () => { fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" }); });
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(screen.getByRole("dialog", { name: "What is the product or feature you'd like to build?" })).toBeInTheDocument();
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
