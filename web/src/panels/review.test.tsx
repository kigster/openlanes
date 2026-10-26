// Regression tests for the PR #58 review: each one failed before its fix.
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useEffect } from "react";
import type { Reply } from "../api/types";
import { ActionMenu } from "./ActionMenu";
import { AgentDrawer } from "./AgentDrawer";
import { useAnnounce } from "./index";
import { AnnouncerProvider } from "./feedback";
import { ModelSelect } from "./ModelSelect";
import { NeedsYou } from "./NeedsYou";
import { UnblockWidget } from "./UnblockWidget";
import { carOf, findInline, planAt, question, recorder, renderPanel, snapshot, typeInEditor, type Sent } from "./testing";
import { pend, unconfirmed } from "./transcript";

/** A command callback whose replies wait until the test lets them go. */
function deferred() {
  const sent: Sent[] = [];
  let release: (r: Reply) => void = () => {};
  const onCommand = vi.fn((c: Sent) => {
    sent.push(c);
    return new Promise<Reply>((resolve) => { release = resolve; });
  });
  return { sent, onCommand, release: (status: Reply["status"] = "accepted") => release({ id: "x", status, reason: null, at: "" }) };
}

describe("one command at a time (1)", () => {
  it("ignores a second Ctrl Enter in the answer box while the first is in flight", async () => {
    const user = userEvent.setup();
    const d = deferred();
    renderPanel(<NeedsYou plans={[planAt("001.00")]} onCommand={d.onCommand} />);
    await user.type(screen.getByRole("textbox", { name: "Your answer" }), "Yes{Control>}{Enter}{Enter}{/Control}");
    expect(d.onCommand).toHaveBeenCalledTimes(1);
    await act(async () => { d.release(); });
    expect(await findInline("Answer sent to backend-coder.")).toBeInTheDocument();
  });

  it("ignores a second Ctrl Enter in CodeMirror while the first is in flight", async () => {
    const d = deferred();
    const { container } = renderPanel(<UnblockWidget plan={planAt("001.00")} onCommand={d.onCommand} onClose={() => {}} />);
    let content!: HTMLElement;
    act(() => { content = typeInEditor(container, "An answer"); });
    await act(async () => {
      fireEvent.keyDown(content, { key: "Enter", code: "Enter", keyCode: 13, ctrlKey: true });
      fireEvent.keyDown(content, { key: "Enter", code: "Enter", keyCode: 13, ctrlKey: true });
    });
    expect(d.onCommand).toHaveBeenCalledTimes(1);
    await act(async () => { d.release(); });
  });

  it("drops drawer actions and messages sent while one is in flight", async () => {
    const d = deferred();
    const plan = planAt("005.00");
    renderPanel(<AgentDrawer plan={plan} car={carOf(plan, "staff-reviewer")} models={snapshot.models} autocompact={0.4} onCommand={d.onCommand} onClose={() => {}} />);
    const box = screen.getByRole("textbox", { name: "Message staff-reviewer" });
    fireEvent.change(box, { target: { value: "hi" } });
    await act(async () => {
      fireEvent.keyDown(box, { key: "Enter", ctrlKey: true });
      fireEvent.keyDown(box, { key: "Enter", ctrlKey: true });
    });
    expect(d.onCommand).toHaveBeenCalledTimes(1);
    await act(async () => { d.release(); });
  });
});

describe("ActionMenu (2, 8)", () => {
  it("shows a successful add in place, not only to screen readers", async () => {
    const user = userEvent.setup();
    renderPanel(<ActionMenu backlog={snapshot.backlog} onCommand={recorder().onCommand} />);
    await user.click(screen.getByRole("button", { name: "Action" }));
    await user.click(await screen.findByText("Choose an existing plan"));
    await user.click(screen.getByText("012.00 Linear two-way sync"));
    expect(await findInline("012.00 added to this run.")).toBeInTheDocument();
  });

  it("lets the page open the idea dialog and hears it close", async () => {
    const user = userEvent.setup();
    const onIdeaOpenChange = vi.fn();
    renderPanel(<ActionMenu backlog={[]} onCommand={recorder().onCommand} ideaOpen onIdeaOpenChange={onIdeaOpenChange} />);
    expect(screen.getByRole("dialog", { name: "What is the product or feature you'd like to build?" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onIdeaOpenChange).toHaveBeenCalledWith(false);
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("keeps the dialog closed while the page says so, even from New idea", async () => {
    const user = userEvent.setup();
    const onIdeaOpenChange = vi.fn();
    renderPanel(<ActionMenu backlog={[]} onCommand={recorder().onCommand} ideaOpen={false} onIdeaOpenChange={onIdeaOpenChange} />);
    await user.click(screen.getByRole("button", { name: "Action" }));
    await user.click(await screen.findByText("New idea"));
    expect(onIdeaOpenChange).toHaveBeenCalledWith(true);
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("AgentDrawer (3, 4)", () => {
  it("renders the stuck agent's question as Markdown", () => {
    const plan = planAt("001.00");
    plan.questions = [question({ body: "Carry the **checkout path**?\n\n<script>bad()</script>" })];
    const { container } = renderPanel(<AgentDrawer plan={plan} car={carOf(plan, "backend-coder")} models={snapshot.models} autocompact={0.4} onCommand={recorder().onCommand} onClose={() => {}} />);
    const block = container.querySelector(".d-block")!;
    expect(block.querySelector("strong + *, .ask-text strong")).toHaveTextContent("checkout path");
    expect(block.textContent).not.toContain("**");
    expect(block.querySelector("script")).toBeNull();
    expect(block.querySelector("p p, p div")).toBeNull();
  });

  it("drops an optimistic line once the history carries it, one for one", async () => {
    const user = userEvent.setup();
    const plan = planAt("005.00");
    const car = carOf(plan, "staff-reviewer");
    const props = { plan, models: snapshot.models, autocompact: 0.4, onCommand: recorder().onCommand, onClose: () => {} };
    const { rerender } = renderPanel(<AgentDrawer car={car} {...props} />);
    const box = screen.getByRole("textbox", { name: "Message staff-reviewer" });
    for (let i = 0; i < 2; i++) {
      await user.type(box, "again");
      await user.click(screen.getByRole("button", { name: "Send message" }));
      await waitFor(() => expect(box).toHaveValue(""));
    }
    const count = () => screen.getAllByText("you: again").length;
    expect(count()).toBe(2);
    rerender(<AgentDrawer car={{ ...car, history: ["you: again", ...car.history] }} {...props} />);
    expect(count()).toBe(2);
    rerender(<AgentDrawer car={{ ...car, history: ["you: again", "you: again", ...car.history] }} {...props} />);
    expect(count()).toBe(2);
    rerender(<AgentDrawer car={car} {...props} />);
    expect(screen.queryByText("you: again")).toBeNull();
  });

  it("confirms by exact text, one history line per entry", () => {
    const pending = pend(pend(pend([], ["a"], "a"), ["a"], "a"), ["a"], "b");
    expect(unconfirmed(pending, ["a"]).map((p) => p.text)).toEqual(["b", "a", "a"]);
    expect(unconfirmed(pending, ["a", "a", "c"]).map((p) => p.text)).toEqual(["b", "a"]);
    expect(unconfirmed(pending, ["a", "a", "a", "b"])).toEqual([]);
  });
});

describe("ModelSelect (5)", () => {
  it("clears the queued model once the car runs it, or on another car", async () => {
    const user = userEvent.setup();
    const plan = planAt("005.00");
    const car = carOf(plan, "staff-reviewer");
    const props = { plan: "005.00", models: snapshot.models, mode: "next" as const, onCommand: recorder().onCommand };
    const { rerender } = renderPanel(<ModelSelect car={car} {...props} />);
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Opus 5.5" }));
    await waitFor(() => expect(screen.getByRole("combobox")).toHaveClass("is-changed"));
    rerender(<ModelSelect car={{ ...car, model: "claude-opus-5-5" }} {...props} />);
    expect(screen.getByRole("combobox")).not.toHaveClass("is-changed");
    rerender(<ModelSelect car={car} {...props} />);
    expect(screen.getByRole("combobox")).toHaveTextContent("Sonnet 5.5");
    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Haiku 5.5" }));
    await waitFor(() => expect(screen.getByRole("combobox")).toHaveClass("is-changed"));
    rerender(<ModelSelect car={{ ...car, key: "005.00/other" }} {...props} />);
    expect(screen.getByRole("combobox")).toHaveTextContent("Sonnet 5.5");
  });
});

describe("AnnouncerProvider (6, 7)", () => {
  it("re-announces the same sentence as a fresh node", () => {
    let say: (t: string) => void = () => {};
    function Speaker() {
      const { announce } = useAnnounce();
      useEffect(() => { say = announce; }, [announce]);
      return null;
    }
    render(<AnnouncerProvider><Speaker /></AnnouncerProvider>);
    act(() => say("Asked to stop."));
    const first = screen.getByTestId("announcer").firstElementChild;
    act(() => say("Asked to stop."));
    const second = screen.getByTestId("announcer").firstElementChild;
    expect(second).toHaveTextContent("Asked to stop.");
    expect(second).not.toBe(first);
  });
});
