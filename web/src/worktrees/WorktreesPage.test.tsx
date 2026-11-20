import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { Worktree } from "../api/worktrees";
import { revealWorktree, takePendingWorktree } from "./reveal";
import { WorktreesMenu } from "./WorktreesMenu";
import { WorktreesPage } from "./WorktreesPage";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const planned: Worktree = {
  id: "aaa111",
  path: "/home/someone/wt/003.00-tax-rule-dsl",
  branch: "someone/003.00-tax-rule-dsl",
  plan: { ordinal: "003.00", title: "Tax Rule DSL", status: "building", label: "Building", emoji: "🔨", working: true },
  modified: [" M a.rb", "?? b.rb"],
  lines: { added: 12, removed: 3 },
};
const scratch: Worktree = { id: "bbb222", path: "/tmp/wt/scratch", branch: "", plan: null, modified: [], lines: { added: 0, removed: 0 } };

let fetchMock: ReturnType<typeof vi.fn>;
const answer = (worktrees: Worktree[] | Response = [planned, scratch]) =>
  fetchMock.mockImplementation(async (url: string) => {
    if (url === "/api/worktrees") return worktrees instanceof Response ? worktrees : json({ worktrees });
    if (url.endsWith("/pulls"))
      return json({
        pulls: [
          { number: 7, title: "Add the DSL", url: "https://github.test/o/r/pull/7", state: "open", ci: "pass" },
          { number: 8, title: "Fix the DSL", url: "https://github.test/o/r/pull/8", state: "open", ci: "fail" },
        ],
      });
    if (url.endsWith("/diff"))
      return json({ stat: " a.rb | 2 +-\n", patch: "--- a/a.rb\n+++ b/a.rb\n@@ -1 +1 @@\n-one\n+two\n", truncated: true, base: "main", compare_url: "https://github.test/o/r/compare/main...x" });
    return json({}, 404);
  });

const draw = (ui = <WorktreesPage />) =>
  render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{ui}</QueryClientProvider>);

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

it("draws each worktree folded, its folder and branch as headings with the line counts beneath", async () => {
  answer();
  draw();
  await screen.findByRole("heading", { level: 1, name: "Worktrees" });
  expect(screen.getAllByRole("heading", { level: 2 }).map(h => h.textContent)).toEqual(["~/wt/003.00-tax-rule-dsl", "someone/003.00-tax-rule-dsl", "/tmp/wt/scratch", "detached HEAD"]);
  expect(screen.getByLabelText("12 lines added, 3 removed against main")).toHaveTextContent("+12 −3");
  expect(screen.queryByText(/Plan 003.00/)).not.toBeInTheDocument();
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("opens one worktree at a time, with its plan, state, modified files and pull requests", async () => {
  answer();
  draw();
  await userEvent.click(await screen.findByRole("button", { name: "Open ~/wt/003.00-tax-rule-dsl" }));
  expect(screen.getByText("Plan 003.00 · Tax Rule DSL")).toBeInTheDocument();
  expect(screen.getByText(/Building · agent working/)).toBeInTheDocument();
  const files = screen.getByRole("button", { name: "Show Modified Files (2)" });
  expect(screen.getByLabelText("git status")).not.toBeVisible();
  await userEvent.click(files);
  expect(screen.getByLabelText("git status")).toHaveTextContent("M a.rb ?? b.rb");
  expect(screen.getByRole("button", { name: "Hide Modified Files (2)" })).toHaveAttribute("aria-expanded", "true");
  const pulls = await screen.findByRole("list", { name: "Pull requests" });
  expect(within(pulls).getByRole("link", { name: "#7 Add the DSL" })).toHaveAttribute("href", "https://github.test/o/r/pull/7");
  expect(within(pulls).getAllByRole("img").map(i => i.getAttribute("aria-label"))).toEqual(["CI passed", "CI failed"]);
  await userEvent.click(screen.getByRole("button", { name: "Open /tmp/wt/scratch" }));
  expect(screen.queryByText("Plan 003.00 · Tax Rule DSL")).not.toBeInTheDocument();
  expect(screen.getByText("No plan on this branch")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Show Modified Files (0)" })).toBeInTheDocument();
});

it("shows the diff with main in a modal, with a link to GitHub", async () => {
  answer();
  draw();
  await userEvent.click(await screen.findByRole("button", { name: "Open ~/wt/003.00-tax-rule-dsl" }));
  await userEvent.click(screen.getByRole("button", { name: "Show Diff with Main" }));
  const dialog = await screen.findByRole("dialog");
  expect(await within(dialog).findByLabelText("Patch")).toHaveTextContent("+two");
  expect(within(dialog).getByRole("heading", { name: "someone/003.00-tax-rule-dsl against main" })).toBeInTheDocument();
  expect(within(dialog).getByText(/cut short/)).toBeInTheDocument();
  expect(within(dialog).getByRole("link", { name: "Open on GitHub" })).toHaveAttribute("href", "https://github.test/o/r/compare/main...x");
  await userEvent.click(within(dialog).getByRole("button", { name: "Close" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

it("opens the worktree picked from the nav menu, before or after the page mounts", async () => {
  answer();
  revealWorktree("bbb222");
  draw();
  expect(await screen.findByText("No plan on this branch")).toBeInTheDocument();
  expect(takePendingWorktree()).toBeNull();
  act(() => revealWorktree("aaa111"));
  expect(screen.getByText("Plan 003.00 · Tax Rule DSL")).toBeInTheDocument();
  expect(screen.queryByText("No plan on this branch")).not.toBeInTheDocument();
});

it("says so when there is nothing, or the list cannot be read", async () => {
  answer([]);
  const { unmount } = draw();
  expect(await screen.findByText("No worktrees besides the main checkout.")).toBeInTheDocument();
  unmount();
  answer(json({}, 500));
  draw();
  expect(await screen.findByRole("alert")).toHaveTextContent("Could not list the worktrees");
});

it("lists the worktrees in the nav menu, and hands back the one picked", async () => {
  answer();
  const onPick = vi.fn();
  draw(<WorktreesMenu onPick={onPick} />);
  await userEvent.click(await screen.findByRole("button", { name: /\/tmp\/wt\/scratch/ }));
  expect(onPick).toHaveBeenCalledWith("bbb222");
  expect(screen.getByRole("button", { name: /~\/wt\/003.00-tax-rule-dsl/ })).toHaveTextContent("someone/003.00-tax-rule-dsl");
});

it("says so in the nav menu when there are no worktrees, or they cannot be read", async () => {
  answer([]);
  const { unmount } = draw(<WorktreesMenu onPick={vi.fn()} />);
  expect(await screen.findByText("No worktrees")).toBeInTheDocument();
  unmount();
  answer(json({}, 500));
  draw(<WorktreesMenu onPick={vi.fn()} />);
  expect(await screen.findByText("Worktrees unavailable")).toBeInTheDocument();
});
