import { QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import App from "./App";
import type { AppStatus, Board, LogLine } from "./api/types";
import apps from "./api/fixtures/apps.json";
import board from "./api/fixtures/board.json";
import { createQueryClient } from "./api/queryClient";
import type { StreamHandlers } from "./api/events";
import { sampleBoard, samplePr } from "./board/sample";

const streams: StreamHandlers[] = [];
vi.mock("./api/events", () => ({
  openStream: (h: StreamHandlers) => {
    streams.push(h);
    return () => {};
  },
}));

const renderApp = () => {
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false } });
  return render(
    <QueryClientProvider client={client}>
      <App />
    </QueryClientProvider>,
  );
};
const pills = () => within(document.querySelector<HTMLElement>(".pills")!);

beforeEach(() => {
  streams.length = 0;
  localStorage.clear();
});
afterEach(() => {
  vi.unstubAllGlobals();
  window.history.replaceState(null, "", "/");
});

it("has a fixture that satisfies the Board contract", () => {
  const typed: Board = board as Board;
  expect(typed.me.plans.length).toBeGreaterThan(0);
});

describe("under ?fixture", () => {
  beforeEach(() => window.history.replaceState(null, "", "/?fixture"));

  it("offers no chat, since nothing is connected to chat with", async () => {
    renderApp();
    const tab = await screen.findByRole("tab", { name: "sam@ci-runner-2" });
    fireEvent.contextMenu(tab);
    expect(screen.queryByRole("menu")).toBeNull();
    expect(screen.queryByRole("button", { name: /Chat with/ })).toBeNull();
  });

  it("draws the header, the tabs, the board and the status bar", async () => {
    renderApp();
    expect(await screen.findByText("Fixture data")).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Board" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: /001 tests/ })).toHaveTextContent("52 of 465");
    expect(screen.getByRole("tab", { name: "sam@ci-runner-2" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Clean agent boundaries and transitions" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^Action/ })).toBeInTheDocument();
    expect(screen.getByText("0 merged, 0 ready to merge, 2 blocked")).toBeInTheDocument();
  });

  it("switches tabs with the arrow keys and shows the Logs and test tabs", async () => {
    const user = userEvent.setup();
    renderApp();
    const boardTab = await screen.findByRole("tab", { name: "Board" });
    act(() => boardTab.focus());
    await user.keyboard("{ArrowRight}");
    expect(screen.getByRole("tab", { name: /Logs/ })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("list", { name: "Log lines, newest last" })).toBeVisible();
    await user.click(screen.getByRole("tab", { name: /001 tests/ }));
    expect(screen.getByRole("heading", { name: /001 Clean agent boundaries and transitions: tests/ })).toBeInTheDocument();
  });

  it("walks every tab with the arrow keys, the machines' tabs included", async () => {
    const user = userEvent.setup();
    renderApp();
    const run = await screen.findByRole("tab", { name: /001 tests/ });
    const sam = screen.getByRole("tab", { name: "sam@ci-runner-2" });
    act(() => run.focus());
    await user.keyboard("{ArrowRight}");
    expect(sam).toHaveFocus();
    expect(sam).toHaveAttribute("aria-selected", "true");
    await user.keyboard("{ArrowRight}");
    expect(screen.getByRole("tab", { name: "Board" })).toHaveFocus();
    await user.keyboard("{ArrowLeft}");
    expect(sam).toHaveFocus();
    await user.keyboard("{ArrowLeft}");
    expect(run).toHaveFocus();
    await user.keyboard("{End}");
    expect(sam).toHaveFocus();
    await user.keyboard("{Home}");
    expect(screen.getByRole("tab", { name: "Board" })).toHaveFocus();
  });

  it("selects every tab the arrow keys land on, each of every kind", async () => {
    const user = userEvent.setup();
    renderApp();
    const tabs = await screen.findAllByRole("tab");
    act(() => tabs[0].focus());
    for (const tab of [...tabs.slice(1), tabs[0]]) {
      await user.keyboard("{ArrowRight}");
      expect(tab).toHaveFocus();
      expect(tab).toHaveAttribute("aria-selected", "true");
    }
  });

  it("toggles a machine tab: first its board, then every machine on the Board", async () => {
    const user = userEvent.setup();
    renderApp();
    const tab = await screen.findByRole("tab", { name: "sam@ci-runner-2" });
    await user.click(tab);
    expect(tab).toHaveAttribute("aria-selected", "true");
    expect(screen.getByText(/this machine will not start them/)).toBeInTheDocument();
    await user.click(tab);
    expect(screen.getByRole("tab", { name: "Board" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("button", { name: "All machines" })).toHaveAttribute("aria-pressed", "true");
    expect(localStorage.getItem("openlanes-merged")).toBe("1");
    await waitFor(() => expect(screen.getByTestId("announcer")).toHaveTextContent("Showing every machine's plans."));
    await user.click(screen.getByRole("button", { name: "All machines" }));
    expect(screen.getByRole("button", { name: "All machines" })).toHaveAttribute("aria-pressed", "false");
    // Their pill opens their tab.
    await user.click(screen.getByTitle(/^010 .*Read only\./));
    expect(tab).toHaveAttribute("aria-selected", "true");
    // Enter on the selected machine tab is a second press.
    act(() => tab.focus());
    await user.keyboard("{Enter}");
    expect(screen.getByRole("tab", { name: "Board" })).toHaveAttribute("aria-selected", "true");
  });

  it("toggles the unblock widget from a red pill and returns focus to it", async () => {
    const user = userEvent.setup();
    renderApp();
    const pill = await screen.findByRole("button", { name: /^001 [^,]*, needs technical decision/ });
    await user.click(pill);
    expect(pill).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("region", { name: /Unblock 001/ })).toBeInTheDocument();
    await user.click(pill);
    expect(screen.queryByRole("region", { name: /Unblock 001/ })).toBeNull();
    await user.click(pill);
    await user.click(within(screen.getByRole("region", { name: /Unblock 001/ })).getByRole("button", { name: "Hide" }));
    expect(pill).toHaveFocus();
  });

  it("shows a working plan's row from its pill, and opens and closes a car's drawer", async () => {
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole("tab", { name: /Logs/ }));
    await user.click(pills().getByRole("button", { name: /^005 [^,]*, working/ }));
    expect(screen.getByRole("tab", { name: "Board" })).toHaveAttribute("aria-selected", "true");
    const hansolo = screen.getByRole("button", { name: "hansolo-reviewer" });
    expect(hansolo).toHaveFocus();
    await user.click(hansolo);
    expect(hansolo).toHaveAttribute("aria-expanded", "true");
    expect(screen.queryByRole("heading", { name: /Needs you/ })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.getByRole("heading", { name: /Needs you/ })).toBeInTheDocument();
    expect(hansolo).toHaveFocus();
  });
});

it("opens the idea dialog when the page is loaded at #start", async () => {
  window.history.replaceState(null, "", "/?fixture#start");
  renderApp();
  expect(await screen.findByRole("dialog")).toBeInTheDocument();
  expect(window.location.hash).toBe("");
  expect(window.location.search).toBe("?fixture");
});

it("does not reopen the idea dialog on a reload once #start is spent", async () => {
  window.history.replaceState(null, "", "/?fixture#start");
  const first = renderApp();
  await screen.findByRole("dialog");
  first.unmount();
  renderApp();
  await screen.findByRole("button", { name: "All machines" });
  expect(screen.queryByRole("dialog")).toBeNull();
});

it("works in a private window, where storage throws", async () => {
  window.history.replaceState(null, "", "/?fixture");
  const get = vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new Error("denied");
  });
  const set = vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("denied");
  });
  renderApp();
  const toggle = await screen.findByRole("button", { name: "All machines" });
  await userEvent.click(toggle);
  expect(toggle).toHaveAttribute("aria-pressed", "true");
  get.mockRestore();
  set.mockRestore();
});

describe("live", () => {
  const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });

  it("waits for the board, then follows the stream", async () => {
    const first = sampleBoard();
    first.me.plans[0].cars[0].state = "stuck";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(first)));
    renderApp();
    expect(screen.getByText("Connecting to the engine…")).toBeInTheDocument();
    await screen.findByRole("tab", { name: "Board" });
    expect(screen.getByRole("status")).toHaveTextContent("Reconnecting…");
    const stream = streams.at(-1)!;

    // New warnings count on the Logs tab until it is opened.
    const next = structuredClone(first);
    const warn: LogLine = { at: "2026-10-13T09:00:10Z", source: "api", level: "warn", text: "slow", plan: null };
    next.me.seq += 1; // every change the engine publishes carries a higher seq
    next.me.log.push(warn);
    next.me.plans[1].pr = samplePr({ state: "merged", number: 44 });
    next.me.plans[0].cars[1].message = "Writing tests";
    act(() => {
      stream.onState("live");
      stream.onBoard(structuredClone(next));
    });
    const logs = screen.getByRole("tab", { name: /Logs/ });
    expect(logs).toHaveTextContent("Logs1");
    await waitFor(() => expect(screen.getByTestId("announcer")).toHaveTextContent("PR #44 was merged on GitHub. 005 is complete."));
    expect(screen.queryByRole("tab", { name: /001 tests/ })).toBeNull();
    await userEvent.click(logs);
    expect(logs).toHaveTextContent(/^Logs$/);

    // A stuck car with no question: its pill opens the drawer.
    next.me.plans[0].questions = [];
    next.me.seq += 1;
    act(() => stream.onBoard(structuredClone(next)));
    await userEvent.click(pills().getByRole("button", { name: /^001 / }));
    expect(screen.getByRole("button", { name: "luke-backend" })).toHaveAttribute("aria-expanded", "true");
  });

  it("shows a Preview tab only while an app with a preview process runs (plan 012)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(sampleBoard())));
    renderApp();
    await screen.findByRole("tab", { name: "Board" });
    expect(screen.queryByRole("tab", { name: /▶/ })).toBeNull();
    const stream = streams.at(-1)!;
    act(() => stream.onApps?.(apps.apps as AppStatus[]));
    const tab = await screen.findByRole("tab", { name: "▶ 012 · kig/012.00-app-runner-and-preview · :11101" });
    await userEvent.click(tab);
    expect(screen.getByTitle("web of plan 012")).toHaveAttribute("src", "http://127.0.0.1:11101/");
    act(() => stream.onApp?.({ ...(apps.apps[1] as AppStatus), state: "stopped" }));
    await waitFor(() => expect(screen.queryByRole("tab", { name: /▶/ })).toBeNull());
    expect(screen.getByRole("tab", { name: "Board" })).toHaveAttribute("aria-selected", "true");
  });

  it("opens a machine's chat menu from its caret or a right-click, while a click still opens its board", async () => {
    const first = sampleBoard();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(first)));
    renderApp();
    await screen.findByRole("tab", { name: "Board" });
    const label = `${first.others[0].node.user}@${first.others[0].node.host}`;
    const tab = screen.getByRole("tab", { name: label });
    fireEvent.contextMenu(tab);
    expect(await screen.findByRole("menuitem", { name: /Start Chat/ })).toBeInTheDocument();
    await userEvent.keyboard("{Escape}");
    await userEvent.click(screen.getByRole("button", { name: `Chat with ${label}` }));
    expect(await screen.findByRole("menuitem", { name: /Start Chat/ })).toBeInTheDocument();
    await userEvent.keyboard("{Escape}");
    await userEvent.click(tab);
    expect(tab).toHaveAttribute("aria-selected", "true");
  });

  it("renders a peer node's tab read only and sends no command from it", async () => {
    const first = sampleBoard();
    const fetchMock = vi.fn().mockResolvedValue(json(first));
    vi.stubGlobal("fetch", fetchMock);
    renderApp();
    await screen.findByRole("tab", { name: "Board" });
    const label = `${first.others[0].node.user}@${first.others[0].node.host}`;
    await userEvent.click(screen.getByRole("tab", { name: label }));
    const panel = screen.getByRole("tabpanel", { name: label });
    expect(within(panel).getByText(/Read only\./)).toBeInTheDocument();
    expect(within(panel).getAllByRole("article")).toHaveLength(first.others[0].plans.length);
    expect(within(panel).queryAllByRole("button")).toHaveLength(0);
    expect(panel.querySelectorAll(".car-open, .model-trigger")).toHaveLength(0);
    // Pressing the plan and the car text does nothing: no POST ever left the page.
    for (const car of Array.from(panel.querySelectorAll(".car-agent, article"))) await userEvent.click(car);
    const posts = fetchMock.mock.calls.filter(([, init]) => (init as RequestInit | undefined)?.method === "POST");
    expect(posts).toHaveLength(0);
  });

  it("does not switch views when Tab only moves focus onto a machine's tab", async () => {
    const first = sampleBoard();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(first)));
    renderApp();
    const boardTab = await screen.findByRole("tab", { name: "Board" });
    const label = `${first.others[0].node.user}@${first.others[0].node.host}`;
    act(() => screen.getByRole("tab", { name: label }).focus());
    expect(boardTab).toHaveAttribute("aria-selected", "true");
    // Enter on it is the deliberate press that switches.
    await userEvent.keyboard("{Enter}");
    expect(screen.getByRole("tab", { name: label })).toHaveAttribute("aria-selected", "true");
  });

  it("counts only agents still at work in Stop All Local, and keeps their merged rows ten seconds", async () => {
    const first = sampleBoard();
    first.me.plans[1].cars[0].state = "done"; // 005: its reviewer finished, the car lingers
    first.me.plans[2].cars[0].state = "failed"; // 006: nothing left to stop
    first.others[0].plans[0].pr = samplePr({ state: "merged" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(first)));
    localStorage.setItem("openlanes-merged", "1");
    renderApp();
    await screen.findByRole("tab", { name: "Board" });
    // Their merged row is still on the merged board, not dropped on sight.
    expect(document.querySelector('.plan.is-theirs[data-plan="010.00"]')).not.toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Stop All Local" }));
    expect(await screen.findByText(/shut down 2 agents currently working on 1 plans/)).toBeInTheDocument();
  });

  it("fades another machine's merged row after ten seconds and drops it a second later", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      const first = sampleBoard();
      first.others[0].plans[0].pr = samplePr({ state: "merged" });
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(first)));
      localStorage.setItem("openlanes-merged", "1");
      renderApp();
      await screen.findByRole("tab", { name: "Board" });
      const row = () => document.querySelector('.plan.is-theirs[data-plan="010.00"]');
      act(() => vi.advanceTimersByTime(9_000));
      expect(row()).not.toHaveClass("is-retiring");
      act(() => vi.advanceTimersByTime(1_100));
      expect(row()).toHaveClass("is-retiring");
      act(() => vi.advanceTimersByTime(1_100));
      expect(row()).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it("says how to start an engine when the server has no board yet, then draws the one that arrives", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json({ me: null, others: [] })));
    renderApp();
    const empty = await screen.findByText(/No engine is running for this checkout/);
    expect(empty.closest("main")).toHaveAttribute("aria-busy", "true");
    expect(empty.closest("main")).toHaveTextContent(
      'Please use openlanes start, or start an engine in another terminal by running "openlanes run".'
    );
    act(() => streams.at(-1)!.onBoard(sampleBoard()));
    expect(await screen.findByRole("tab", { name: "Board" })).toBeInTheDocument();
  });

  it("says when the board cannot be loaded", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("{}", { status: 500 })));
    renderApp();
    expect(await screen.findByRole("alert")).toHaveTextContent("Could not load the board: GET /api/board answered 500.");
  });
});
