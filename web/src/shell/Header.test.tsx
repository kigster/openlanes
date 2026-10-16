import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { Header, type HeaderProps } from "./Header";
import { currentTheme } from "./useTheme";
import { sampleBoard } from "../board/sample";

const props = (over: Partial<HeaderProps> = {}): HeaderProps => ({
  snapshot: sampleBoard().me,
  connection: "live",
  merged: false,
  onToggleMerged: vi.fn(),
  ...over,
});

afterEach(() => {
  delete document.documentElement.dataset.theme;
});

it("names this machine and prints the run's totals as plain text, accessibly", async () => {
  const snapshot = sampleBoard().me;
  snapshot.run.started_at = "2026-10-13T08:42:00Z";
  const { container } = render(
    <Header {...props({ snapshot })} actionMenu={<button type="button">Action</button>} stopAll={<button type="button">Stop All Local</button>}
      help={<button type="button" aria-label="How this works">?</button>} />,
  );
  expect(screen.getByRole("heading", { level: 1, name: "OpenLanes control room" })).toHaveClass("sr-only");
  expect(screen.getByText("dana@studio-mini")).toBeInTheDocument();
  expect(screen.getByText("18 min")).toBeInTheDocument();
  expect(screen.getByText("4")).toBeInTheDocument();
  expect(screen.getByText("2.82M")).toBeInTheDocument();
  expect(screen.getByText("$14.80")).toBeInTheDocument();
  expect(screen.queryByText("Sample data")).toBeNull();
  expect(screen.queryByText("Fixture data")).toBeNull();
  expect(screen.getByRole("button", { name: "Stop All Local" })).toBeInTheDocument();
  expect(screen.getByRole("img", { name: "openlanes" })).toBeInTheDocument();
  expect(await axe(container)).toHaveNoViolations();
});

it("titles a project that is not openlanes itself and leaves out a missing description", () => {
  const snapshot = sampleBoard().me;
  snapshot.project = "Ledger";
  snapshot.description = null;
  snapshot.node.ip = null;
  render(<Header {...props({ snapshot })} />);
  expect(screen.getByRole("heading", { level: 1, name: "Ledger" })).not.toHaveClass("sr-only");
  expect(screen.queryByText(/software factory/)).toBeNull();
  expect(screen.getByText("dana@studio-mini").parentElement).not.toHaveAttribute("title", expect.stringContaining("IP"));
});

it("flags fixture data and a lost connection", () => {
  const { rerender } = render(<Header {...props({ fixture: true, connection: "reconnecting" })} />);
  expect(screen.getByText("Fixture data")).toBeInTheDocument();
  expect(screen.getByRole("status")).toHaveTextContent("Reconnecting…");
  rerender(<Header {...props({ connection: "offline" })} />);
  expect(screen.getByRole("status")).toHaveTextContent("Offline, retrying");
});

it("shows reconnecting when the stream errors and clears it when the stream reopens, the board unchanged", () => {
  const snapshot = sampleBoard().me;
  const { rerender } = render(<Header {...props({ snapshot })} />);
  expect(screen.queryByRole("status")).toBeNull();
  const totals = screen.getByText("$14.80");
  rerender(<Header {...props({ snapshot, connection: "reconnecting" })} />);
  expect(screen.getByRole("status")).toHaveTextContent("Reconnecting…");
  // The totals stay on screen while the stream is down: the last board is kept, not blanked.
  expect(screen.getByText("$14.80")).toBe(totals);
  rerender(<Header {...props({ snapshot, connection: "live" })} />);
  expect(screen.queryByRole("status")).toBeNull();
  expect(screen.getByText("$14.80")).toBe(totals);
});

it("presses All machines", async () => {
  const onToggleMerged = vi.fn();
  render(<Header {...props({ merged: true, onToggleMerged })} />);
  const button = screen.getByRole("button", { name: "All machines" });
  expect(button).toHaveAttribute("aria-pressed", "true");
  await userEvent.click(button);
  expect(onToggleMerged).toHaveBeenCalled();
});

it("toggles the theme, follows the OS until pressed", async () => {
  const listeners: Array<() => void> = [];
  let dark = false;
  const media = vi.spyOn(window, "matchMedia").mockImplementation(
    query =>
      ({
        get matches() {
          return dark;
        },
        media: query,
        addEventListener: (_: string, l: () => void) => listeners.push(l),
        removeEventListener: vi.fn(),
      }) as unknown as MediaQueryList,
  );
  const { unmount } = render(<Header {...props()} />);
  await userEvent.click(screen.getByRole("button", { name: "Switch to dark theme" }));
  expect(document.documentElement.dataset.theme).toBe("dark");
  await userEvent.click(screen.getByRole("button", { name: "Switch to light theme" }));
  expect(currentTheme()).toBe("light");
  delete document.documentElement.dataset.theme;
  dark = true;
  act(() => listeners.forEach(l => l()));
  expect(screen.getByRole("button", { name: "Switch to light theme" })).toBeInTheDocument();
  unmount();
  media.mockRestore();
});

it("offers narrow lanes as a pressed-or-not toggle", async () => {
  const onToggleNarrow = vi.fn();
  const { rerender } = render(<Header {...props({ narrow: false, onToggleNarrow })} />);
  const toggle = screen.getByRole("button", { name: "Narrow lanes" });
  expect(toggle).toHaveAttribute("aria-pressed", "false");
  await userEvent.click(toggle);
  expect(onToggleNarrow).toHaveBeenCalledTimes(1);
  rerender(<Header {...props({ narrow: true, onToggleNarrow })} />);
  expect(screen.getByRole("button", { name: "Narrow lanes" })).toHaveAttribute("aria-pressed", "true");
});

it("has no lanes toggle when nobody handles it", () => {
  render(<Header {...props()} />);
  expect(screen.queryByRole("button", { name: "Narrow lanes" })).toBeNull();
});
