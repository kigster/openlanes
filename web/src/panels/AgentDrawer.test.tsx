import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import type { Car, Plan } from "../api/types";
import type { AgentAction } from "./AgentActionMenu";
import { AgentDrawer } from "./AgentDrawer";
import { carOf, findInline, planAt, question, recorder, renderPanel, snapshot, type Sent } from "./testing";

function drawer(plan: Plan, car: Car, onCommand = recorder().onCommand, onClose = vi.fn()) {
  return renderPanel(<AgentDrawer plan={plan} car={car} models={snapshot.models} autocompact={snapshot.autocompact} onCommand={onCommand} onClose={onClose} />);
}
// The log starts closed, so reading it means opening it first, the way a person would.
const transcript = () => {
  const toggle = screen.getByRole("button", { name: /Show log|Hide log/ });
  if (toggle.getAttribute("aria-expanded") === "false") fireEvent.click(toggle);
  return within(screen.getByRole("list", { name: /Transcript of/ })).getAllByRole("listitem").map((li) => li.textContent);
};

describe("AgentDrawer", () => {
  it("shows the agent, its model, tokens, elapsed time and context, focusing Close", async () => {
    const plan = planAt("005.00");
    const { container } = drawer(plan, carOf(plan, "hansolo-reviewer"));
    expect(screen.getByRole("heading", { name: "hansolo-reviewer" })).toBeInTheDocument();
    expect(screen.getByText("005.00 Review state labels. Model Sonnet 5.5.")).toBeInTheDocument();
    expect(screen.getByText("Switches this agent now, then runs /compact.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Close" })).toHaveFocus();
    expect(screen.getByText("Context").parentElement).toHaveTextContent("Context 27% of 200.0k, 54.1k used. Autocompacts at 40%.");
    expect(container.querySelector(".d-ctx-bar b")).toHaveStyle({ left: "40%" });
    expect(container.querySelector(".d-ctx-bar i")).toHaveStyle({ width: "27.05%" });
    expect(screen.getByText("Tokens in").querySelector("strong")).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("says when the adapter does not report its context", () => {
    const plan = planAt("005.00");
    const car = { ...carOf(plan, "hansolo-reviewer"), context: null };
    drawer(plan, car);
    expect(screen.getByText("not reported")).toBeInTheDocument();
  });

  it("sends a message, puts it in the transcript and clears the box", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("005.00");
    drawer(plan, carOf(plan, "hansolo-reviewer"), onCommand);
    await user.click(screen.getByRole("button", { name: "Send message" }));
    expect(sent).toHaveLength(0);
    expect(screen.getByRole("textbox", { name: "Message hansolo-reviewer" })).toHaveFocus();
    await user.type(screen.getByRole("textbox", { name: "Message hansolo-reviewer" }), "Look at the CI first{Meta>}{Enter}{/Meta}");
    await waitFor(() => expect(sent).toEqual([{ kind: "message", plan: "005.00", agent: "hansolo-reviewer", payload: { text: "Look at the CI first" } }]));
    expect(transcript()[0]).toBe("you: Look at the CI first");
    expect(screen.getByRole("textbox", { name: "Message hansolo-reviewer" })).toHaveValue("");
    expect(screen.getByTestId("announcer")).toHaveTextContent("Message sent to hansolo-reviewer.");
  });

  it("shows a refused message and keeps the text", async () => {
    const user = userEvent.setup();
    const plan = planAt("005.00");
    drawer(plan, carOf(plan, "hansolo-reviewer"), recorder("refused", "the agent has finished").onCommand);
    await user.type(screen.getByRole("textbox", { name: "Message hansolo-reviewer" }), "hi");
    await user.click(screen.getByRole("button", { name: "Send message" }));
    expect(await findInline("Refused: the agent has finished.")).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "Message hansolo-reviewer" })).toHaveValue("hi");
  });

  it.each<[string, AgentAction, string]>([
    ["Hold for now", "hold", "you: Asked to hold for now."],
    ["Wrap up", "wrap_up", "you: Asked to wrap up."],
    ["Stop agent", "stop", "you: Asked to stop."],
    ["Compact", "compact", "you: Asked to compact its context; it runs /compact at its next step."],
  ])("Action ▸ %s sends %s", async (item, kind, line) => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("005.00");
    drawer(plan, carOf(plan, "hansolo-reviewer"), onCommand);
    await user.click(screen.getByRole("button", { name: "Action" }));
    const menu = await screen.findByRole("menu");
    expect(within(menu).getByText("Run /compact now; 27% of its context used")).toBeInTheDocument();
    await user.click(within(menu).getByText(item));
    await waitFor(() => expect(sent).toEqual([{ kind, plan: "005.00", agent: "hansolo-reviewer", payload: {} } satisfies Sent]));
    expect(transcript()[0]).toBe(line);
  });

  it("says Compacted once the reply is done, and a refusal in place", async () => {
    const user = userEvent.setup();
    const plan = planAt("005.00");
    const { unmount } = drawer(plan, carOf(plan, "hansolo-reviewer"), recorder("done").onCommand);
    await user.click(screen.getByRole("button", { name: "Action" }));
    await user.click(await screen.findByText("Compact"));
    await waitFor(() => expect(transcript()[0]).toBe("you: Compacted its context."));
    unmount();
    drawer(plan, carOf(plan, "hansolo-reviewer"), recorder("refused", "it is not running").onCommand);
    await user.click(screen.getByRole("button", { name: "Action" }));
    await user.click(await screen.findByText("Wrap up"));
    expect(await findInline("Refused: it is not running.")).toBeInTheDocument();
  });

  it("opens the Action menu with the keyboard and closes it with Esc without closing the drawer", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    const plan = planAt("005.00");
    drawer(plan, carOf(plan, "hansolo-reviewer"), recorder().onCommand, onClose);
    screen.getByRole("button", { name: "Action" }).focus();
    await user.keyboard("{Enter}");
    expect(await screen.findByRole("menu")).toBeInTheDocument();
    await user.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("menu")).toBeNull());
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.keyDown(screen.getByRole("button", { name: "Close" }), { key: "Escape" });
    fireEvent.keyDown(screen.getByRole("button", { name: "Close" }), { key: "a" });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("switches the model now through switch_model", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("005.00");
    drawer(plan, carOf(plan, "hansolo-reviewer"), onCommand);
    const select = screen.getByRole("combobox", { name: "Model" });
    await user.click(select);
    await user.click(await screen.findByRole("option", { name: "Opus 5.5" }));
    await waitFor(() => expect(sent).toEqual([{ kind: "switch_model", plan: "005.00", agent: "hansolo-reviewer", payload: { model: "claude-opus-5-5" } }]));
    expect(transcript()[0]).toBe("you: Switching from Sonnet 5.5 to Opus 5.5; it runs /compact first.");
  });

  it("shows a stuck agent's question, answers it and puts the answer in the transcript", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("001.00");
    drawer(plan, carOf(plan, "luke-backend"), onCommand);
    expect(screen.getByText("Blocked on your answer.")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    expect(sent).toHaveLength(0);
    await user.type(screen.getByRole("textbox", { name: "Your answer" }), "The checkout path.");
    await user.click(screen.getByRole("button", { name: "Send answer" }));
    await waitFor(() => expect(sent[0]).toEqual({ kind: "answer", plan: "001.00", agent: "luke-backend", payload: { question: "B1", text: "The checkout path." } }));
    expect(transcript()[0]).toBe("You answered: The checkout path.");
    expect(screen.queryByText("Blocked on your answer.")).toBeNull();
  });

  it("offers Yes and No for a declared yes/no question", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("006.00");
    const car = { ...carOf(plan, "r2d2-mechanic"), state: "stuck" as const };
    drawer(plan, car, onCommand);
    await user.click(screen.getByRole("button", { name: "Yes" }));
    await waitFor(() => expect(sent[0].payload).toEqual({ question: "B1", text: "yes" }));
  });

  it("opens a box under Yes and No to type something instead", async () => {
    const user = userEvent.setup();
    const plan = planAt("006.00");
    drawer(plan, { ...carOf(plan, "r2d2-mechanic"), state: "stuck" });
    expect(screen.queryByRole("textbox", { name: "Your answer" })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Type something instead" }));
    expect(screen.getByRole("textbox", { name: "Your answer" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "No" })).toBeInTheDocument();
  });

  it("offers a lettered question's options and sends the one chosen", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("001.00");
    plan.questions = [question({ body: "Which?", options: [
      { letter: "a", label: "Rebase", recommended: false, answer: "a) Rebase" },
      { letter: "b", label: "Merge", recommended: true, answer: "b) Merge" },
    ] })];
    drawer(plan, carOf(plan, "luke-backend"), onCommand);
    expect(screen.getByText("Recommended")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /Rebase/ }));
    await waitFor(() => expect(sent[0].payload).toEqual({ question: "B1", text: "a) Rebase" }));
  });

  it("keeps the log closed on open, with its line count, and the composer and Action menu in view", async () => {
    const plan = planAt("005.00");
    const car = carOf(plan, "hansolo-reviewer");
    const { container } = drawer(plan, car);
    const toggle = screen.getByRole("button", { name: /Show log/ });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).toHaveTextContent(`${car.history.length} line`);
    const log = container.querySelector(`#${CSS.escape(toggle.getAttribute("aria-controls") ?? "")}`);
    expect(log).toHaveAttribute("hidden");
    expect(log).toHaveAttribute("aria-live", "off");
    expect(screen.queryByRole("list", { name: /Transcript of/ })).toBeNull();
    expect(screen.getByRole("textbox", { name: "Message hansolo-reviewer" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Send message" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Action" })).toBeVisible();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("opens and closes the log, announcing it only while open", async () => {
    const user = userEvent.setup();
    const plan = planAt("005.00");
    const car = carOf(plan, "hansolo-reviewer");
    drawer(plan, car);
    await user.click(screen.getByRole("button", { name: /Show log/ }));
    const toggle = screen.getByRole("button", { name: /Hide log/ });
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    const list = screen.getByRole("list", { name: "Transcript of hansolo-reviewer" });
    expect(list).toHaveAttribute("aria-live", "polite");
    expect(list.id).toBe(toggle.getAttribute("aria-controls"));
    expect(within(list).getAllByRole("listitem").map((li) => li.textContent)).toEqual(car.history);
    await user.click(toggle);
    expect(screen.getByRole("button", { name: /Show log/ })).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("list", { name: /Transcript of/ })).toBeNull();
  });

  it("sends a message with the log closed and counts the new line", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("005.00");
    const car = carOf(plan, "hansolo-reviewer");
    drawer(plan, car, onCommand);
    await user.type(screen.getByRole("textbox", { name: "Message hansolo-reviewer" }), "Ship it");
    await user.click(screen.getByRole("button", { name: "Send message" }));
    await waitFor(() => expect(sent).toEqual([{ kind: "message", plan: "005.00", agent: "hansolo-reviewer", payload: { text: "Ship it" } }]));
    expect(screen.getByRole("button", { name: /Show log/ })).toHaveTextContent(`${car.history.length + 1} lines`);
    expect(screen.queryByRole("list", { name: /Transcript of/ })).toBeNull();
  });

  it("shows a stuck agent's question with its log still closed", () => {
    const plan = planAt("001.00");
    drawer(plan, carOf(plan, "luke-backend"));
    expect(screen.getByText("Blocked on your answer.")).toBeVisible();
    expect(screen.getByRole("button", { name: /Show log/ })).toHaveAttribute("aria-expanded", "false");
    expect(screen.getByRole("button", { name: "Send message" })).toBeVisible();
  });

  it("closes the log again for another car", async () => {
    const user = userEvent.setup();
    const plan = planAt("001.00");
    const { rerender } = drawer(plan, carOf(plan, "rey-frontend"));
    await user.click(screen.getByRole("button", { name: /Show log/ }));
    expect(screen.getByRole("button", { name: /Hide log/ })).toBeInTheDocument();
    rerender(<AgentDrawer plan={plan} car={carOf(plan, "luke-backend")} models={snapshot.models} autocompact={0.4} onCommand={recorder().onCommand} onClose={() => {}} />);
    expect(screen.getByRole("button", { name: /Show log/ })).toHaveAttribute("aria-expanded", "false");
  });

  it("starts a fresh transcript for another car", () => {
    const plan = planAt("001.00");
    const { rerender } = drawer(plan, carOf(plan, "rey-frontend"));
    rerender(<AgentDrawer plan={plan} car={carOf(plan, "luke-backend")} models={snapshot.models} autocompact={0.4} onCommand={recorder().onCommand} onClose={() => {}} />);
    expect(screen.getByRole("heading", { name: "luke-backend" })).toBeInTheDocument();
  });
});
