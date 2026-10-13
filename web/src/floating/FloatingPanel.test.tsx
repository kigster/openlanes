import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { axe } from "vitest-axe";
import { FloatingPanel, type FloatingPanelProps } from "./FloatingPanel";
import { BIG_STEP, MARGIN, STEP, clamp, statusBarHeight } from "./useFloatingPanel";

// jsdom lays nothing out, so the panel reports the rectangle a test gives it: 440 by 560 at (rect.x, rect.y).
const rect = { x: 500, y: 100 };
const WIDTH = 440;
const HEIGHT = 560;
const INSET = 60;

beforeEach(() => {
  rect.x = 500;
  rect.y = 100;
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
    if (!this.classList.contains("fp")) return new DOMRect();
    // A placed panel is where its inline style says; a docked one is where the test put it.
    const left = parseFloat(this.style.left);
    const top = parseFloat(this.style.top);
    return new DOMRect(Number.isNaN(left) ? rect.x : left, Number.isNaN(top) ? rect.y : top, WIDTH, HEIGHT);
  });
  Object.assign(window, { innerWidth: 1200, innerHeight: 900 });
});
afterEach(() => vi.restoreAllMocks());

type Props = Partial<FloatingPanelProps> & { startOpen?: boolean };

function Harness({ startOpen = true, ...over }: Props) {
  const [open, setOpen] = useState(startOpen);
  return (
    <>
      <FloatingPanel
        id="panel"
        dock="right"
        title="c3po-operator"
        subtitle="Copilot for this run."
        tabLabel="Copilot"
        moves="the copilot"
        bodyLabel="Conversation"
        open={open}
        onOpenChange={setOpen}
        bottomInset={() => INSET}
        footer={<button type="button">Send</button>}
        {...over}
      >
        <p>Hello.</p>
      </FloatingPanel>
    </>
  );
}

const panel = () => document.getElementById("panel") as HTMLElement;
const head = () => panel().querySelector(".fp-head") as HTMLElement;
const grip = () => screen.getByRole("button", { name: /^Move the copilot/ });
const at = () => ({ x: parseFloat(panel().style.left), y: parseFloat(panel().style.top) });
const drag = (from: { x: number; y: number }, to: { x: number; y: number }, target: Element = head()) => {
  fireEvent.pointerDown(target, { button: 0, clientX: from.x, clientY: from.y, pointerId: 1 });
  fireEvent.pointerMove(head(), { clientX: to.x, clientY: to.y, pointerId: 1 });
  fireEvent.pointerUp(head(), { clientX: to.x, clientY: to.y, pointerId: 1 });
};

it("draws a docked, labelled, non-modal dialog with its header, body and footer, accessibly", async () => {
  const { container } = render(<Harness />);
  const dialog = screen.getByRole("dialog", { name: "c3po-operator" });
  expect(dialog).toHaveAttribute("aria-modal", "false");
  expect(dialog).toHaveAttribute("data-dock", "right");
  expect(dialog).not.toHaveClass("is-placed");
  expect(dialog.style.getPropertyValue("--fp-w")).toBe("440px");
  expect(screen.getByText("Copilot for this run.")).toBeInTheDocument();
  expect(screen.getByRole("group", { name: "Conversation" })).toHaveTextContent("Hello.");
  expect(screen.getByRole("button", { name: "Send" }).closest(".fp-foot")).not.toBeNull();
  expect(screen.queryByRole("button", { name: "Copilot" })).toBeNull(); // the tab hides while the panel is open
  expect(await axe(container)).toHaveNoViolations();
});

it("sets its colours as custom properties, on the panel and on its tab", () => {
  render(<Harness startOpen={false} colors={{ head: "#D9420B", body: "#fff", tab: "#222", tabInk: "#fff" }} dock="left" />);
  expect(panel().style.getPropertyValue("--fp-head")).toBe("#D9420B");
  expect(panel().style.getPropertyValue("--fp-body")).toBe("#fff");
  const tab = screen.getByRole("button", { name: "Copilot" });
  expect(tab).toHaveAttribute("data-dock", "left");
  expect(tab.style.getPropertyValue("--fp-tab")).toBe("#222");
});

it("is dragged by its header and keeps the pointer's grip on it", () => {
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 320, y: 210 });
  expect(at()).toEqual({ x: 300, y: 200 });
  expect(panel()).toHaveClass("is-placed");
  expect(panel()).not.toHaveClass("is-dragging");
});

it("shows it is being dragged until the pointer lets go", () => {
  render(<Harness />);
  fireEvent.pointerDown(head(), { button: 0, clientX: 520, clientY: 110, pointerId: 1 });
  expect(panel()).toHaveClass("is-dragging");
  fireEvent.pointerCancel(head(), { pointerId: 1 });
  expect(panel()).not.toHaveClass("is-dragging");
  // A cancelled drag leaves the panel where the last move put it, here still docked.
  expect(panel()).not.toHaveClass("is-placed");
  fireEvent.pointerMove(head(), { clientX: 0, clientY: 0 }); // no drag in progress: nothing moves
  expect(panel()).not.toHaveClass("is-placed");
});

it("drags from the grip too, but not from the header's other buttons or with another mouse button", () => {
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 420, y: 110 }, screen.getByRole("button", { name: "Minimise" }));
  expect(panel()).not.toHaveClass("is-placed");
  fireEvent.pointerDown(head(), { button: 2, clientX: 520, clientY: 110 });
  expect(panel()).not.toHaveClass("is-dragging");
  drag({ x: 520, y: 110 }, { x: 420, y: 110 }, grip());
  expect(at()).toEqual({ x: 400, y: 100 });
});

it("stays inside the window and above the status bar", () => {
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 5000, y: 5000 });
  expect(at()).toEqual({ x: 1200 - WIDTH - MARGIN, y: 900 - INSET - HEIGHT - MARGIN });
  drag({ x: 1000, y: 300 }, { x: -5000, y: -5000 });
  expect(at()).toEqual({ x: MARGIN, y: MARGIN });
});

it("clamps to the top-left when the window is smaller than the panel, so its header stays reachable", () => {
  Object.assign(window, { innerWidth: 300, innerHeight: 400 });
  expect(clamp({ x: 200, y: 200 }, { width: WIDTH, height: HEIGHT }, INSET)).toEqual({ x: MARGIN, y: MARGIN });
});

it("moves with the arrow keys on its grip, further with Shift, and goes home with Home", async () => {
  const user = userEvent.setup();
  render(<Harness />);
  grip().focus();
  await user.keyboard("{ArrowLeft}");
  expect(at()).toEqual({ x: 500 - STEP, y: 100 });
  await user.keyboard("{ArrowUp}");
  expect(at()).toEqual({ x: 500 - STEP, y: 100 - STEP });
  await user.keyboard("{Shift>}{ArrowRight}{/Shift}");
  expect(at()).toEqual({ x: 500 - STEP + BIG_STEP, y: 100 - STEP });
  await user.keyboard("{ArrowDown}");
  expect(at().y).toBe(100);
  await user.keyboard("a"); // not a move: nothing happens
  expect(at().y).toBe(100);
  await user.keyboard("{Home}");
  expect(panel()).not.toHaveClass("is-placed");
  expect(panel().style.left).toBe("");
});

it("goes back to its corner on a double-click on the header, but not on its buttons", async () => {
  const user = userEvent.setup();
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 320, y: 210 });
  await user.dblClick(screen.getByRole("button", { name: "Minimise" }));
  // The double-click minimised it twice over, but did not send it home.
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  expect(panel()).toHaveClass("is-placed");
  await user.dblClick(screen.getByRole("heading", { name: "c3po-operator" }));
  expect(panel()).not.toHaveClass("is-placed");
});

it("keeps a dragged panel inside a window that shrinks", () => {
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 720, y: 210 });
  expect(at()).toEqual({ x: 700, y: 200 });
  act(() => {
    Object.assign(window, { innerWidth: 900 });
    window.dispatchEvent(new Event("resize"));
  });
  expect(at().x).toBe(900 - WIDTH - MARGIN);
});

it("minimises with Esc to a tab on its edge, focusing the tab, and reopens with focus inside", async () => {
  const user = userEvent.setup();
  const outer = vi.fn();
  document.addEventListener("keydown", outer);
  render(<Harness />);
  screen.getByRole("button", { name: "Send" }).focus();
  await user.keyboard("{Escape}");
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(outer).not.toHaveBeenCalled(); // Esc minimised the panel and nothing else
  const tab = screen.getByRole("button", { name: "Copilot" });
  expect(tab).toHaveFocus();
  expect(tab).toHaveAttribute("aria-expanded", "false");
  expect(tab).toHaveAttribute("aria-controls", "panel");
  await user.keyboard("a{Escape}"); // other keys inside the panel are its own business
  await user.click(tab);
  expect(screen.getByRole("heading", { name: "c3po-operator" })).toHaveFocus();
  await user.keyboard("x");
  expect(screen.getByRole("dialog")).toBeInTheDocument();
  document.removeEventListener("keydown", outer);
});

it("focuses what it is told to on open, and takes no focus on its first render", async () => {
  const user = userEvent.setup();
  function WithInput() {
    const [open, setOpen] = useState(false);
    const [input] = useState(() => ({ current: null as HTMLElement | null }));
    return (
      <FloatingPanel id="panel" dock="left" title="Chat" tabLabel="Chat" moves="the chat" bodyLabel="Chat" open={open} onOpenChange={setOpen} initialFocus={input}>
        <label>
          Say <input ref={el => void (input.current = el)} />
        </label>
      </FloatingPanel>
    );
  }
  render(<WithInput />);
  expect(document.body).toHaveFocus();
  await user.click(screen.getByRole("button", { name: "Chat" }));
  expect(screen.getByRole("textbox", { name: "Say" })).toHaveFocus();
});

it("keeps a dragged place across minimise by default, for the visit", async () => {
  const user = userEvent.setup();
  render(<Harness />);
  drag({ x: 520, y: 110 }, { x: 320, y: 210 });
  await user.click(screen.getByRole("button", { name: "Minimise" }));
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  expect(at()).toEqual({ x: 300, y: 200 });
});

it("returns to its corner on restore when told to (the chat's left dock)", async () => {
  const user = userEvent.setup();
  render(<Harness dock="left" restore="dock" />);
  drag({ x: 520, y: 110 }, { x: 320, y: 210 });
  await user.click(screen.getByRole("button", { name: "Minimise" }));
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  expect(panel()).not.toHaveClass("is-placed");
  expect(panel()).toHaveAttribute("data-dock", "left");
});

it("puts a dot on the tab, and says so, when something was said while minimised", () => {
  render(<Harness startOpen={false} unread />);
  const tab = screen.getByRole("button", { name: "Copilot , new reply" });
  expect(tab.querySelector(".fp-dot")).not.toBeNull();
});

it("holds two panels at once, each with its own place", () => {
  render(
    <>
      <Harness />
      <FloatingPanel id="chat" dock="left" title="Chat" tabLabel="Chat" moves="the chat" bodyLabel="Chat" open onOpenChange={() => {}} live>
        <p>Hi</p>
      </FloatingPanel>
    </>,
  );
  drag({ x: 520, y: 110 }, { x: 320, y: 210 });
  expect(panel()).toHaveClass("is-placed");
  expect(document.getElementById("chat")).not.toHaveClass("is-placed");
  expect(screen.getByRole("log", { name: "Chat" })).toBeInTheDocument();
});

it("measures the status bar it must stay above", () => {
  expect(statusBarHeight()).toBe(0);
  const bar = document.createElement("footer");
  bar.className = "statusbar";
  Object.defineProperty(bar, "offsetHeight", { value: 60 });
  document.body.append(bar);
  expect(statusBarHeight()).toBe(60);
  bar.remove();
});
