import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { StatusBar, type StatusBarProps } from "./StatusBar";
import { sampleBoard, samplePlan, samplePr, sampleQuestion } from "../board/sample";
import type { GonePlan } from "../board/useLifecycle";

const board = sampleBoard();
const props = (over: Partial<StatusBarProps> = {}): StatusBarProps => ({
  plans: board.me.plans,
  stations: board.me.stations,
  others: board.others,
  gone: new Map(),
  offBar: new Set(),
  finishOrder: new Map(),
  unblocking: null,
  onToggleUnblock: vi.fn(),
  onShowPlan: vi.fn(),
  onOpenMachine: vi.fn(),
  onDropGone: vi.fn(),
  ...over,
});
const ours = () => within(screen.getAllByRole("list")[0]);

it("draws a pill per plan with the mockup's states and the summary, accessibly", async () => {
  const { container } = render(<StatusBar {...props({ unblocking: "001.00" })} />);
  const pill = screen.getByRole("button", { name: /^001 [^,]*, needs technical decision/ });
  expect(pill).toHaveClass("pill is-blocked");
  expect(pill).toHaveAttribute("aria-expanded", "true");
  expect(screen.getByRole("button", { name: "005 1h 38m, working, at Review" })).not.toHaveAttribute("aria-expanded");
  expect(screen.getByText("1 merged, 1 ready to merge, 3 blocked")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "010 1h 38m, on sam@ci-runner-2, read only, at Review" })).toBeInTheDocument();
  expect(await axe(container)).toHaveNoViolations();
});

// axe's label-content-name-mismatch: a pill's name begins with what it shows (its number and time), so a voice user
// can say what they see. The mark is aria-hidden, so it is not part of what is shown.
it("names every pill starting with its visible text", () => {
  render(<StatusBar {...props()} />);
  const pills = document.querySelectorAll<HTMLButtonElement>(".pill");
  expect(pills.length).toBeGreaterThan(0);
  pills.forEach(pill => {
    const shown = pill.querySelector(".pill-text")?.textContent ?? "";
    expect(shown).toMatch(/^\d{3} \S/);
    expect(pill.getAttribute("aria-label")).toMatch(new RegExp(`^${shown}, `));
  });
});

it("toggles the unblock widget from a red pill and shows the plan from any other", async () => {
  const p = props();
  render(<StatusBar {...p} />);
  await userEvent.click(screen.getByRole("button", { name: /^001 / }));
  expect(p.onToggleUnblock).toHaveBeenCalledWith(expect.objectContaining({ ordinal: "001.00" }));
  await userEvent.click(screen.getByRole("button", { name: /^005 / }));
  expect(p.onShowPlan).toHaveBeenCalledWith(expect.objectContaining({ ordinal: "005.00" }));
  await userEvent.click(screen.getByTitle(/^010 Cache agent registry lookups: on sam@ci-runner-2, at Review. Read only./));
  expect(p.onOpenMachine).toHaveBeenCalledWith(board.others[0].node.id);
});

it("puts finished plans after a divider, in the order they finished, gone ones purple", () => {
  const plans = [
    samplePlan({ ordinal: "001.00" }),
    samplePlan({ ordinal: "002.00", pr: samplePr({ state: "approved" }) }),
    samplePlan({ ordinal: "003.00", pr: samplePr({ state: "merged" }) }),
    samplePlan({ ordinal: "004.00", questions: [sampleQuestion({ held: true })] }),
  ];
  const gone = new Map<string, GonePlan>([
    ["009.00", { plan: samplePlan({ ordinal: "009.00", pr: samplePr({ state: "merged", number: 9 }) }), at: 0 }],
    ["008.00", { plan: samplePlan({ ordinal: "008.00" }), at: 0 }],
  ]);
  const finishOrder = new Map([["003.00", 1], ["002.00", 2], ["009.00", 3]]);
  const { container } = render(<StatusBar {...props({ plans, gone, offBar: new Set(["008.00"]), finishOrder, others: [] })} />);
  const ids = [...container.querySelectorAll(".pills:not(.pills-theirs) > li")].map(li => li.querySelector(".pill-id")?.textContent ?? "|");
  expect(ids).toEqual(["001", "004", "|", "003", "002", "009"]);
  expect(ours().getByRole("button", { name: /^004 [^,]*, held blocked/ })).toHaveClass("is-held");
  expect(ours().getByRole("button", { name: /^009 / })).toHaveClass("is-gone");
  expect(screen.getByText("2 merged, 1 ready to merge, 1 blocked")).toBeInTheDocument();
});

it("marks other machines' approved and merged plans", () => {
  const others = structuredClone(board.others);
  others[0].plans = [
    samplePlan({ ordinal: "010.00", pr: samplePr({ state: "approved" }) }),
    samplePlan({ ordinal: "011.00", pr: samplePr({ state: "merged" }) }),
    samplePlan({ ordinal: "012.00", station: "somewhere" }),
  ];
  render(<StatusBar {...props({ others })} />);
  expect(screen.getByTitle(/^010 .*reviewed, ready to merge/)).toHaveClass("is-done");
  expect(screen.getByTitle(/^011 .*merged on GitHub, complete/)).toHaveClass("is-gone");
  expect(screen.getByTitle(/^012 .*at somewhere/)).toBeInTheDocument();
});

it("wears approved solid green and merged solid purple, both checked, for as long as their rows stay", async () => {
  const finishOrder = new Map([["008.00", 1], ["007.00", 2]]);
  const { container } = render(<StatusBar {...props({ finishOrder })} />);
  const approved = ours().getByRole("button", { name: /^007 [^,]*, reviewed, PR #47 ready to merge$/ });
  const merged = ours().getByRole("button", { name: /^008 [^,]*, PR #45 merged on GitHub, plan complete$/ });
  expect(approved).toHaveClass("pill is-done");
  expect(merged).toHaveClass("pill is-merged");
  expect([approved, merged].map(p => p.querySelector(".pill-mark")?.textContent)).toEqual(["✅", "✅"]);
  // Both sit after the divider, in the order they finished.
  const ids = [...container.querySelectorAll(".pills:not(.pills-theirs) > li")].map(li => li.querySelector(".pill-id")?.textContent ?? "|");
  expect(ids.slice(ids.indexOf("|"))).toEqual(["|", "008", "007"]);
  expect(await axe(container)).toHaveNoViolations();
});

describe("past two lines", () => {
  const now = Date.now();
  const gone = () => new Map<string, GonePlan>([
    ["007.00", { plan: samplePlan({ ordinal: "007.00" }), at: now - 10 * 60_000 }],
    ["006.00", { plan: samplePlan({ ordinal: "006.00" }), at: now - 20 * 60_000 }],
    ["005.00", { plan: samplePlan({ ordinal: "005.00" }), at: now }],
  ]);
  beforeEach(() => vi.useFakeTimers({ now }));
  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("takes the oldest purple pill off once it has stayed long enough", () => {
    const onDropGone = vi.fn();
    const height = vi.spyOn(HTMLElement.prototype, "scrollHeight", "get").mockReturnValue(500);
    render(<StatusBar {...props({ plans: [], gone: gone(), onDropGone })} />);
    expect(onDropGone).toHaveBeenCalledWith("006.00");
    onDropGone.mockClear();
    height.mockReturnValue(0);
    act(() => vi.advanceTimersByTime(15_000));
    expect(onDropGone).not.toHaveBeenCalled();
  });

  // The pills wrap rather than scroll sideways, so a wide list is no reason to take one off: only a third line is.
  it("keeps every pill while they fit in two lines, however wide", () => {
    const onDropGone = vi.fn();
    vi.spyOn(HTMLElement.prototype, "scrollWidth", "get").mockReturnValue(5000);
    render(<StatusBar {...props({ plans: [], gone: gone(), onDropGone })} />);
    act(() => vi.advanceTimersByTime(15_000));
    expect(onDropGone).not.toHaveBeenCalled();
  });
});

// The page's bottom padding and the floating panels keep clear of the bar through --statusbar-h, so a bar that wrapped
// to two lines writes its real height there, and takes it back when it goes.
it("writes its real height into --statusbar-h, follows it as it changes, and puts it back on unmount", () => {
  let resized: () => void = () => {};
  const observe = vi.fn();
  const disconnect = vi.fn();
  const Real = globalThis.ResizeObserver;
  globalThis.ResizeObserver = class {
    constructor(callback: () => void) { resized = callback; }
    observe = observe;
    unobserve() {}
    disconnect = disconnect;
  } as unknown as typeof ResizeObserver;
  const height = vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(60);
  const root = document.documentElement.style;
  try {
    const { unmount } = render(<StatusBar {...props()} />);
    expect(root.getPropertyValue("--statusbar-h")).toBe("60px");
    expect(observe).toHaveBeenCalledWith(document.querySelector(".statusbar"));
    height.mockReturnValue(110);
    act(() => resized());
    expect(root.getPropertyValue("--statusbar-h")).toBe("110px");
    unmount();
    expect(disconnect).toHaveBeenCalled();
    expect(root.getPropertyValue("--statusbar-h")).toBe("");
  } finally {
    height.mockRestore();
    globalThis.ResizeObserver = Real;
  }
});

// Two engines on different Redis servers never see each other's claims, so the bar says which one this engine uses.
describe("the Redis the engine uses", () => {
  it("is shown as the engine sent it", () => {
    render(<StatusBar {...props({ redisUrl: "redis://localhost:6379/0" })} />);
    expect(screen.getByText("redis://localhost:6379/0")).toBeInTheDocument();
  });

  it("never shows a password or user name, even from an engine that sent one", () => {
    render(<StatusBar {...props({ redisUrl: "rediss://dana:hunter2@10.0.4.2:6380/3" })} />);
    expect(screen.getByText("rediss://:***@10.0.4.2:6380/3")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent("hunter2");
  });

  it("is left out when the engine did not say", () => {
    render(<StatusBar {...props({ redisUrl: null })} />);
    expect(screen.queryByText(/^Redis/)).toBeNull();
  });
});
