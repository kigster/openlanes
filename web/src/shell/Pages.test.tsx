import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Pages } from "./Pages";

// The pages and menus are stand-ins: what is under test is the wiring, which page the URL names and where a pick goes.
const revealPane = vi.fn();
const revealWorktree = vi.fn();
vi.mock("../dependencies/DependenciesPage", () => ({ DependenciesPage: () => <p>dependencies page</p> }));
vi.mock("../settings/SettingsPage", () => ({ SettingsPage: () => <p>settings page</p> }));
vi.mock("../worktrees/WorktreesPage", () => ({ WorktreesPage: () => <p>worktrees page</p> }));
vi.mock("../settings/SettingsMenu", () => ({
  SettingsMenu: ({ onPick }: { onPick: (id: string) => void }) => <button type="button" onClick={() => onPick("web")}>pick web</button>,
}));
vi.mock("../worktrees/WorktreesMenu", () => ({
  WorktreesMenu: ({ onPick }: { onPick: (id: string) => void }) => <button type="button" onClick={() => onPick("aaa111")}>pick aaa111</button>,
}));
vi.mock("../settings/reveal", () => ({ revealPane: (id: string) => revealPane(id) }));
vi.mock("../worktrees/reveal", () => ({ revealWorktree: (id: string) => revealWorktree(id) }));
vi.mock("../panels", () => ({ HelpDialog: () => <button type="button">help</button> }));
vi.mock("./ThemeMenu", () => ({ ThemeMenu: () => <button type="button">theme</button> }));

const draw = (path = "/") => {
  window.history.replaceState(null, "", path);
  return render(<Pages><p>the board</p></Pages>);
};

beforeEach(() => { revealPane.mockClear(); revealWorktree.mockClear(); });
afterEach(() => window.history.replaceState(null, "", "/"));

it("shows the board at / and keeps it mounted, hidden, on another page", () => {
  const { unmount } = draw();
  expect(screen.getByText("the board")).toBeVisible();
  unmount();
  draw("/settings");
  expect([screen.getByText("settings page"), screen.getByText("the board")]).toHaveLength(2);
  expect(screen.getByText("the board")).not.toBeVisible();
});

it.each([
  ["/dependencies", "dependencies page"],
  ["/settings", "settings page"],
  ["/worktrees", "worktrees page"],
])("draws the page %s names", (path, text) => {
  draw(path);
  expect(screen.getByText(text)).toBeInTheDocument();
});

it("puts the theme chooser and help in the nav, on every page", () => {
  draw("/worktrees");
  expect([screen.getByRole("button", { name: "theme" }), screen.getByRole("button", { name: "help" })]).toHaveLength(2);
});

it("opens the settings page at the pane a settings pick names", async () => {
  draw();
  await userEvent.click(screen.getByRole("button", { name: "Project settings sections" }));
  await userEvent.click(screen.getByRole("button", { name: "pick web" }));
  expect([window.location.pathname, revealPane.mock.calls]).toEqual(["/settings", [["web"]]]);
  expect(screen.getByText("settings page")).toBeInTheDocument();
});

it("opens the worktrees page at the worktree a worktrees pick names", async () => {
  draw();
  await userEvent.click(screen.getByRole("button", { name: "Worktrees sections" }));
  await userEvent.click(screen.getByRole("button", { name: "pick aaa111" }));
  expect([window.location.pathname, revealWorktree.mock.calls]).toEqual(["/worktrees", [["aaa111"]]]);
  expect(screen.queryByRole("button", { name: "pick aaa111" })).not.toBeInTheDocument();
});
