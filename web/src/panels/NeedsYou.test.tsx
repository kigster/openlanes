import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { NeedsYou } from "./NeedsYou";
import { findInline, getInline, planAt, question, recorder, renderPanel } from "./testing";

const LETTERED = [
  { letter: "a", label: "Carry the remote URL and the worktree name", recommended: true, answer: "a) Carry the remote URL and the worktree name" },
  { letter: "b", label: "Carry the checkout path", recommended: false, answer: "b) Carry the checkout path" },
];
const lettered = () => {
  const plan = planAt("001.00");
  plan.questions = [question({ body: "Redis keys need one name per checkout. Which?", options: LETTERED })];
  return plan;
};

const interrupted = () => {
  const plan = planAt("001.00");
  plan.questions = [];
  plan.interrupted = { agent: "rey-frontend", at: new Date(Date.now() - 4 * 60000).toISOString(), note: "4 of 7 sources are read." };
  return plan;
};

describe("NeedsYou", () => {
  it("lists open questions with a count, and passes axe", async () => {
    const { onCommand } = recorder();
    const { container } = renderPanel(<NeedsYou plans={[planAt("001.00"), planAt("005.00"), planAt("006.00")]} onCommand={onCommand} />);
    expect(screen.getByRole("heading", { name: "Needs you (2)" })).toBeInTheDocument();
    expect(screen.getByText("Questions and interrupted agents wait here until you act.")).toBeInTheDocument();
    expect(screen.getByText("001.00 — luke-backend")).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("says when nothing waits", () => {
    renderPanel(<NeedsYou plans={[planAt("005.00")]} onCommand={recorder().onCommand} />);
    expect(screen.getByText("Nothing waiting on you. Agents will ask here.")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Needs you" })).toBeInTheDocument();
  });

  it("refuses an empty answer, then sends the answer and settles the card", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[planAt("001.00")]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    const box = screen.getByRole("textbox", { name: "Your answer" });
    expect(box).toHaveAttribute("aria-invalid", "true");
    expect(box).toHaveAttribute("placeholder", "Type an answer first");
    expect(onCommand).not.toHaveBeenCalled();
    await user.type(box, "The checkout path.");
    expect(box).not.toHaveAttribute("aria-invalid");
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    expect(sent).toEqual([{ kind: "answer", plan: "001.00", agent: "luke-backend", payload: { question: "B1", text: "The checkout path." } }]);
    expect(await findInline("Answer sent to luke-backend.")).toBeInTheDocument();
    expect(screen.getByTestId("announcer")).toHaveTextContent("Answer sent to luke-backend.");
  });

  it("sends with Ctrl Enter from the answer box", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[planAt("001.00")]} onCommand={onCommand} />);
    await user.type(screen.getByRole("textbox", { name: "Your answer" }), "Yes{Control>}{Enter}{/Control}");
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].payload).toEqual({ question: "B1", text: "Yes" });
  });

  it("keeps the card and shows the reason when the answer is refused", async () => {
    const user = userEvent.setup();
    const { onCommand } = recorder("refused", "the plan is no longer blocked");
    renderPanel(<NeedsYou plans={[planAt("001.00")]} onCommand={onCommand} />, { announcer: false });
    await user.type(screen.getByRole("textbox", { name: "Your answer" }), "x");
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    const reason = await findInline("Refused: the plan is no longer blocked.");
    expect(reason).toHaveAttribute("aria-live", "polite");
    expect(screen.getByRole("textbox", { name: "Your answer" })).toBeInTheDocument();
  });

  it("reads a rejected promise as a refusal", async () => {
    const user = userEvent.setup();
    renderPanel(<NeedsYou plans={[planAt("006.00")]} onCommand={recorder(new Error("network down")).onCommand} />);
    await user.click(screen.getByRole("button", { name: "Yes" }));
    expect(await findInline("Refused: network down.")).toBeInTheDocument();
  });

  it("answers a yes/no question with its buttons, or opens the box under them to type something instead", async () => {
    const user = userEvent.setup();
    const { onCommand } = recorder();
    renderPanel(<NeedsYou plans={[planAt("006.00")]} onCommand={onCommand} />);
    expect(screen.queryByRole("textbox")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Type something instead" }));
    expect(screen.getByRole("textbox", { name: "Your answer" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Yes" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Type something instead" })).toBeNull();
  });

  it("stacks a lettered question's options in order, the recommended one tagged, and Type something instead last", async () => {
    const { container } = renderPanel(<NeedsYou plans={[lettered()]} onCommand={recorder().onCommand} />);
    const group = screen.getByRole("group", { name: "Choose an answer" });
    expect(within(group).getAllByRole("button").map((b) => b.textContent)).toEqual([
      "a)Carry the remote URL and the worktree nameRecommended", "b)Carry the checkout path", "Type something instead",
    ]);
    expect(within(group).getAllByRole("button")[0]).toHaveClass("is-recommended");
    expect(screen.getByText("Redis keys need one name per checkout. Which?")).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("sends a lettered option as its letter and label", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[lettered()]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: /Carry the checkout path/ }));
    expect(sent[0]).toEqual({ kind: "answer", plan: "001.00", agent: "luke-backend", payload: { question: "B1", text: "b) Carry the checkout path" } });
    expect(await findInline("Answered b) to luke-backend.")).toBeInTheDocument();
  });

  it("sends typed words for a lettered question, the options still above the box", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[lettered()]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Type something instead" }));
    expect(screen.getByRole("button", { name: /Carry the checkout path/ })).toBeInTheDocument();
    await user.type(screen.getByRole("textbox", { name: "Your answer" }), "Neither: use the plan number.");
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    expect(sent[0].payload).toEqual({ question: "B1", text: "Neither: use the plan number." });
  });

  it("sends the word itself for Yes", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[planAt("006.00")]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "No" }));
    expect(sent[0]).toEqual({ kind: "answer", plan: "006.00", agent: "r2d2-mechanic", payload: { question: "B1", text: "no" } });
    expect(await findInline("Answered no to r2d2-mechanic.")).toBeInTheDocument();
  });

  it("holds a question blocked: says so, then fades the card out over half a second", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[planAt("001.00")]} onCommand={onCommand} />);
    const hold = screen.getByRole("button", { name: "Hold blocked" });
    expect(hold).toHaveAttribute("aria-pressed", "false");
    await act(async () => { fireEvent.click(hold); });
    expect(sent[0]).toEqual({ kind: "hold_blocked", plan: "001.00", agent: "luke-backend", payload: { question: "B1" } });
    const note = screen.getByText("Held blocked. 001.00 stays red in the status bar; click it to answer.");
    expect(note.closest(".ask")).toHaveClass("is-leaving");
    expect(screen.getByTestId("announcer")).toHaveTextContent("001.00 held blocked. Its red pill in the status bar brings it back.");
    await act(async () => { vi.advanceTimersByTime(500); });
    expect(screen.queryByText(/Held blocked\./)).toBeNull();
    vi.useRealTimers();
  });

  it("leaves held questions out of the rail", () => {
    const plan = planAt("001.00");
    plan.questions = [question({ held: true })];
    renderPanel(<NeedsYou plans={[plan]} onCommand={recorder().onCommand} />);
    expect(screen.getByText("Nothing waiting on you. Agents will ask here.")).toBeInTheDocument();
  });

  it("resumes an interrupted agent", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    renderPanel(<NeedsYou plans={[interrupted()]} onCommand={onCommand} />);
    expect(screen.getByText("You interrupted rey-frontend 4 minutes ago. Its resume note says: 4 of 7 sources are read.")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Keep work and resume" }));
    expect(sent[0]).toEqual({ kind: "resume", plan: "001.00", agent: "rey-frontend", payload: {} });
    expect(await findInline("Kept rey-frontend's work. It resumes from its note.")).toBeInTheDocument();
  });

  it("confirms a plan-wide discard, naming the other agents it stops", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const { container } = renderPanel(<NeedsYou plans={[interrupted()]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Discard work" }));
    const confirm = screen.getByRole("group", { name: "Discard work on 001.00?" });
    expect(confirm).toHaveTextContent("It also stops luke-backend, resets the plan's worktree and sends the plan back one state.");
    expect(within(confirm).getByRole("button", { name: "Cancel" })).toHaveFocus();
    expect(await axe(container)).toHaveNoViolations();
    await user.click(within(confirm).getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("button", { name: "Keep work and resume" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Discard work" }));
    await user.click(within(screen.getByRole("group")).getByRole("button", { name: "Discard work" }));
    expect(sent[0]).toEqual({ kind: "discard", plan: "001.00", agent: null, payload: {} });
    expect(await findInline("Discarded rey-frontend's work. It starts again.")).toBeInTheDocument();
  });

  it("names no others when the interrupted agent was alone", async () => {
    const user = userEvent.setup();
    const plan = interrupted();
    plan.cars = [];
    plan.interrupted = { ...plan.interrupted!, note: "" };
    renderPanel(<NeedsYou plans={[plan]} onCommand={recorder().onCommand} />);
    expect(screen.getByText("You interrupted rey-frontend 4 minutes ago.")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Discard work" }));
    expect(screen.getByText(/It resets the plan's worktree and sends the plan back one state\./)).toBeInTheDocument();
  });

  it("keeps a settled note after the snapshot drops its question", async () => {
    const user = userEvent.setup();
    const { onCommand } = recorder();
    const plan = planAt("006.00");
    const { rerender } = renderPanel(<NeedsYou plans={[plan]} onCommand={onCommand} />);
    await user.click(screen.getByRole("button", { name: "Yes" }));
    await findInline("Answered yes to r2d2-mechanic.");
    rerender(<NeedsYou plans={[{ ...plan, questions: [] }]} onCommand={onCommand} />);
    expect(getInline("Answered yes to r2d2-mechanic.")).toBeInTheDocument();
  });
});
