import { act, fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { NeedsYou } from "./NeedsYou";
import { UnblockWidget } from "./UnblockWidget";
import { findInline, planAt, question, recorder, renderPanel, typeInEditor } from "./testing";

describe("UnblockWidget", () => {
  it("renders nothing without a plan", () => {
    const { container } = renderPanel(<UnblockWidget plan={null} onCommand={recorder().onCommand} onClose={() => {}} />);
    expect(container.querySelector(".unblock")).toBeNull();
  });

  it("shows the plan's question with a full-width Markdown editor and Send beside it", async () => {
    const { container } = renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={recorder().onCommand} onClose={() => {}} />);
    expect(screen.getByRole("region", { name: "Unblock 001.00: Clean agent boundaries and transitions" })).toBeInTheDocument();
    expect(container.querySelector(".unblock-answer .cm-content")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Send answer" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Preview" })).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("offers a question's options before the editor, which opens to type something instead", async () => {
    const user = userEvent.setup();
    const plan = planAt("001.00");
    plan.questions = [question({ options: [
      { letter: "a", label: "Rebase", recommended: true, answer: "a) Rebase" },
      { letter: "b", label: "Merge", recommended: false, answer: "b) Merge" },
    ] })];
    const { container } = renderPanel(<UnblockWidget plan={plan} onCommand={recorder().onCommand} onClose={() => {}} />);
    expect(container.querySelector(".unblock-answer")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Type something instead" }));
    expect(container.querySelector(".unblock-answer .cm-content")).not.toBeNull();
    expect(screen.getByRole("button", { name: /Rebase/ })).toBeInTheDocument();
  });

  it("sends the answer from the editor, by button and by Ctrl Enter, then closes itself", async () => {
    const { sent, onCommand } = recorder();
    const onClose = vi.fn();
    const { container } = renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={onCommand} onClose={onClose} />);
    fireEvent.click(screen.getByRole("button", { name: "Send answer" }));
    expect(screen.getByRole("textbox", { name: "Your answer" })).toHaveAttribute("aria-invalid", "true");
    let content!: HTMLElement;
    act(() => { content = typeInEditor(container, "Carry the **checkout path**."); });
    await act(async () => { fireEvent.keyDown(content, { key: "Enter", code: "Enter", keyCode: 13, ctrlKey: true }); });
    expect(sent[0]).toEqual({ kind: "answer", plan: "001.00", agent: "luke-backend", payload: { question: "B1", text: "Carry the **checkout path**." } });
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it("shares its draft with the card in Needs you", async () => {
    const { onCommand } = recorder();
    const plan = planAt("001.00");
    const { container } = renderPanel(<><UnblockWidget plan={plan} onCommand={onCommand} onClose={() => {}} /><NeedsYou plans={[plan]} onCommand={onCommand} /></>);
    act(() => { typeInEditor(container, "half typed"); });
    expect(screen.getAllByRole("textbox", { name: "Your answer" })[1]).toHaveValue("half typed");
  });

  it("hides on Hide and on Esc", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={recorder().onCommand} onClose={onClose} />);
    await user.click(screen.getByRole("button", { name: "Hide" }));
    fireEvent.keyDown(screen.getByRole("region"), { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it("tags a held question and offers Release hold", async () => {
    const user = userEvent.setup();
    const { sent, onCommand } = recorder();
    const plan = planAt("001.00");
    plan.questions = [question({ held: true })];
    renderPanel(<UnblockWidget plan={plan} onCommand={onCommand} onClose={() => {}} />);
    expect(screen.getByText("held blocked")).toBeInTheDocument();
    const release = screen.getByRole("button", { name: "Release hold" });
    expect(release).toHaveAttribute("aria-pressed", "true");
    await user.click(release);
    expect(sent[0]).toEqual({ kind: "release_hold", plan: "001.00", agent: "luke-backend", payload: { question: "B1" } });
    expect(await screen.findByRole("button", { name: "Hold blocked" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByTestId("announcer")).toHaveTextContent("001.00 no longer held.");
  });

  it("closes after a hold has faded out", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const onClose = vi.fn();
    renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={recorder().onCommand} onClose={onClose} />);
    await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Hold blocked" })); });
    await act(async () => { vi.advanceTimersByTime(500); });
    expect(onClose).toHaveBeenCalled();
    vi.useRealTimers();
  });

  it("keeps a refused hold on screen with its reason", async () => {
    const user = userEvent.setup();
    renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={recorder("refused").onCommand} onClose={() => {}} />);
    await user.click(screen.getByRole("button", { name: "Hold blocked" }));
    expect(await findInline("Refused: no reason given.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Hold blocked" })).toBeInTheDocument();
  });

  it("closes itself when the plan has nothing left to ask", () => {
    const onClose = vi.fn();
    renderPanel(<UnblockWidget plan={planAt("005.00")} onCommand={recorder().onCommand} onClose={onClose} />);
    expect(onClose).toHaveBeenCalled();
  });
});
