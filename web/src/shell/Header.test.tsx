import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { Header, type HeaderProps } from "./Header";
import { applyPalette, PALETTE_KEY, PALETTES, restorePalette } from "./usePalette";
import { sampleBoard } from "../board/sample";
import type { Snapshot } from "../api/types";
import freshJson from "../api/fixtures/snapshot.json";
import recoveredJson from "../api/fixtures/snapshot-outage.json";

const fresh = freshJson as unknown as Snapshot;
const recovered = recoveredJson as unknown as Snapshot;

const props = (over: Partial<HeaderProps> = {}): HeaderProps => ({
  snapshot: sampleBoard().me,
  connection: "live",
  merged: false,
  onToggleMerged: vi.fn(),
  ...over,
});

afterEach(() => {
  delete document.documentElement.dataset.theme;
  delete document.documentElement.dataset.palette;
  localStorage.clear();
});

it("is a bar of pills: the toggles carry a checkbox, the theme and help stand apart, accessibly", async () => {
  const { container } = render(
    <Header {...props({ merged: true, narrow: false, onToggleNarrow: vi.fn(), hideInactive: false, onToggleHideInactive: vi.fn() })}
      actionMenu={<button type="button">Actions</button>} stopAll={<button type="button">Stop Local Workers</button>}
      help={<button type="button" aria-label="How this works">?</button>} />,
  );
  expect(screen.getByRole("heading", { level: 1, name: "OpenLanes control room" })).toHaveClass("sr-only");
  const nav = within(screen.getByRole("navigation", { name: "Run controls" }));
  expect(nav.getAllByRole("button").map(b => b.textContent)).toEqual(["Menu", "✓All Machines", "Narrow Lanes", "Hide Inactive", "Actions", "Stop Local Workers"]);
  expect(nav.queryByRole("button", { name: /theme/i })).toBeNull();
  expect(nav.queryByRole("button", { name: "How this works" })).toBeNull();
  expect(screen.queryByText("Fixture data")).toBeNull();
  expect(screen.getByRole("img", { name: "openlanes" })).toBeInTheDocument();
  expect(await axe(container)).toHaveNoViolations();
});

it("folds the pills behind Menu: it opens and closes them, and Escape or a click elsewhere closes them", async () => {
  render(<Header {...props()} />);
  const menu = screen.getByRole("button", { name: "Menu" });
  const nav = screen.getByRole("navigation", { name: "Run controls" });
  const open = () => [menu.getAttribute("aria-expanded"), nav.hasAttribute("data-open")];
  const states = [open()];
  await userEvent.click(menu);
  states.push(open());
  await userEvent.keyboard("{Escape}");
  states.push(open());
  await userEvent.click(menu);
  await userEvent.click(screen.getByRole("button", { name: "All Machines" }));
  states.push(open());
  await userEvent.click(document.body);
  states.push(open());
  expect(states).toEqual([["false", false], ["true", true], ["false", false], ["true", true], ["false", false]]);
  expect(menu).toHaveAttribute("aria-controls", "nav-items");
});

it("titles a project that is not openlanes itself", () => {
  const snapshot = sampleBoard().me;
  snapshot.project = "Ledger";
  render(<Header {...props({ snapshot })} />);
  expect(screen.getByRole("heading", { level: 1, name: "Ledger" })).toBeInTheDocument();
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
  const pills = screen.getByRole("button", { name: "All Machines" });
  rerender(<Header {...props({ snapshot, connection: "reconnecting" })} />);
  expect(screen.getByRole("status")).toHaveTextContent("Reconnecting…");
  // The bar stays as it was while the stream is down: nothing is rebuilt or blanked.
  expect(screen.getByRole("button", { name: "All Machines" })).toBe(pills);
  rerender(<Header {...props({ snapshot, connection: "live" })} />);
  expect(screen.queryByRole("status")).toBeNull();
  expect(screen.getByRole("button", { name: "All Machines" })).toBe(pills);
});

it("presses All Machines", async () => {
  const onToggleMerged = vi.fn();
  render(<Header {...props({ merged: true, onToggleMerged })} />);
  const button = screen.getByRole("button", { name: "All Machines" });
  expect(button).toHaveAttribute("aria-pressed", "true");
  await userEvent.click(button);
  expect(onToggleMerged).toHaveBeenCalled();
});

it("offers the palettes in a menu, applies the one chosen, and remembers it", async () => {
  const { unmount } = render(<Header {...props()} />);
  await userEvent.click(screen.getByRole("button", { name: "Theme: Daylight. Change theme" }));
  expect(screen.getAllByRole("menuitemradio").map(i => i.textContent?.replace(/Light:.*|Dark:.*|✓/g, "")))
    .toEqual(["Daylight", "Paper", "Earth", "Forest", "Midnight", "Ember", "Azure"]);
  await userEvent.click(screen.getByRole("menuitemradio", { name: /Ember/ }));
  const { dataset } = document.documentElement;
  expect([dataset.theme, dataset.palette, localStorage.getItem(PALETTE_KEY)]).toEqual(["dark", "ember", "ember"]);
  expect(screen.getByRole("button", { name: "Theme: Ember. Change theme" })).toBeInTheDocument();
  unmount();
});

it("leaves the built-in themes to the scheme alone", () => {
  const { dataset } = document.documentElement;
  applyPalette(PALETTES.find(p => p.id === "forest")!);
  const forest = [dataset.theme, dataset.palette];
  applyPalette(PALETTES.find(p => p.id === "dark")!);
  expect([forest, dataset.theme, dataset.palette]).toEqual([["light", "forest"], "dark", undefined]);
});

it("restores the stored palette before anything renders", () => {
  localStorage.setItem(PALETTE_KEY, "azure");
  restorePalette();
  expect([document.documentElement.dataset.theme, document.documentElement.dataset.palette]).toEqual(["dark", "azure"]);
});

it("starts on what the operating system prefers when nothing is stored, or the stored one is unknown", () => {
  const media = vi.spyOn(window, "matchMedia").mockImplementation(query => ({ matches: query.includes("dark"), media: query }) as MediaQueryList);
  localStorage.setItem(PALETTE_KEY, "neon");
  restorePalette();
  const dark = [document.documentElement.dataset.theme, document.documentElement.dataset.palette];
  media.mockImplementation(query => ({ matches: false, media: query }) as MediaQueryList);
  localStorage.clear();
  restorePalette();
  expect([dark, document.documentElement.dataset.theme]).toEqual([["dark", undefined], "light"]);
  media.mockRestore();
});

it("offers narrow lanes as a pressed-or-not toggle", async () => {
  const onToggleNarrow = vi.fn();
  const { rerender } = render(<Header {...props({ narrow: false, onToggleNarrow })} />);
  const toggle = screen.getByRole("button", { name: "Narrow Lanes" });
  expect(toggle).toHaveAttribute("aria-pressed", "false");
  await userEvent.click(toggle);
  expect(onToggleNarrow).toHaveBeenCalledTimes(1);
  rerender(<Header {...props({ narrow: true, onToggleNarrow })} />);
  expect(screen.getByRole("button", { name: "Narrow Lanes" })).toHaveAttribute("aria-pressed", "true");
});

it("offers Hide Inactive as a pressed-or-not toggle, and leaves it out when nobody handles it", async () => {
  const onToggleHideInactive = vi.fn();
  const { rerender } = render(<Header {...props({ hideInactive: false, onToggleHideInactive })} />);
  const toggle = screen.getByRole("button", { name: "Hide Inactive" });
  expect(toggle).toHaveAttribute("aria-pressed", "false");
  await userEvent.click(toggle);
  expect(onToggleHideInactive).toHaveBeenCalledTimes(1);
  rerender(<Header {...props({ hideInactive: true })} />);
  expect(screen.queryByRole("button", { name: "Hide Inactive" })).toBeNull();
});

it("has no lanes toggle when nobody handles it", () => {
  render(<Header {...props()} />);
  expect(screen.queryByRole("button", { name: "Narrow Lanes" })).toBeNull();
});

describe("Redis outage notice", () => {
  const at = Date.parse(fresh.at);
  it("says nothing when the snapshot is fresh and no outage is recorded", () => {
    render(<Header {...props({ snapshot: fresh, now: at + 5000 })} />);
    expect(screen.queryByText(/Redis/)).toBeNull();
  });

  it("warns when the snapshot is older than the threshold", () => {
    render(<Header {...props({ snapshot: fresh, now: at + 42000 })} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Engine not publishing for 42 s, Redis may be down");
  });

  it("reports a recovered outage and which side the run state came from", () => {
    render(<Header {...props({ snapshot: recovered, now: Date.parse(recovered.at) + 1000 })} />);
    expect(screen.getByTestId("outage-recovered")).toHaveTextContent("Redis was down 72 s (by heartbeat), run state from redis");
    expect(screen.queryByRole("alert")).toBeNull();
  });
});
