import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { PlanManagement } from "./PlanManagement";
import type { PlanOffer } from "../api/planActions";
import { resetSession } from "../api/client";

// Documents and actions answer apart: `filesMock` stands for every files route, `actionsMock` for /actions.
let fetchMock: ReturnType<typeof vi.fn>;
type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
let filesMock: ReturnType<typeof vi.fn<Fetch>>;
let actionsMock: ReturnType<typeof vi.fn<Fetch>>;
const offer = (over: Partial<PlanOffer> = {}): PlanOffer => ({
  ordinal: "070.00", status: "planned", started: false, running: false, depends_on: ["069.00"],
  actions: ["clear_dependencies", "discard", "defer"], ...over,
});
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
beforeEach(() => {
  filesMock = vi.fn<Fetch>(async (url: string) =>
    url.endsWith("/files")
      ? new Response(JSON.stringify({ files: ["spec.md", "plan.md", "pull-requests.md"] }), { status: 200 })
      : new Response("# The spec\n", { status: 200, headers: { ETag: '"e"' } }));
  actionsMock = vi.fn<Fetch>(async () => json(offer()));
  fetchMock = vi.fn((url: string, init?: RequestInit) =>
    url.endsWith("/api/session") ? Promise.resolve(json({ csrf: "t" }))
    : url.includes("/actions") ? actionsMock(url, init)
    : filesMock(url, init));
  resetSession();
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} }));
});
afterEach(() => vi.unstubAllGlobals());

// One client per test, so a rerender keeps its cache as the page's does.
let client: QueryClient;
beforeEach(() => { client = new QueryClient({ defaultOptions: { queries: { retry: false } } }); });
const tree = (lanes?: "wide" | "narrow") => (
  <QueryClientProvider client={client}>
    <PlanManagement ordinal="070.00" lanes={lanes} />
  </QueryClientProvider>
);
const mount = (lanes?: "wide" | "narrow") => render(tree(lanes));
const list = (...files: string[]) => new Response(JSON.stringify({ files }), { status: 200 });
const section = (name: "Documents" | "Actions") => within(screen.getByRole("group", { name }));
const items = () => section("Documents").queryAllByRole("menuitem").map((i) => i.textContent);
const actions = () => section("Actions").queryAllByRole("menuitem").map((i) => i.textContent);

describe("PlanManagement", () => {
  it("lists the labels in order, and opening Specification mounts the modal until it is closed", async () => {
    mount();
    const trigger = screen.getByRole("button", { name: "Plan Management of 070.00" });
    await waitFor(() => expect(trigger).toBeEnabled());
    await userEvent.click(trigger);
    expect(items()).toEqual(["Specification", "Plan", "Pull requests"]);
    await userEvent.click(screen.getByRole("menuitem", { name: "Specification" }));
    const dialog = await screen.findByRole("dialog");
    expect(await within(dialog).findByRole("heading", { name: "The spec" })).toBeInTheDocument();
    await userEvent.click(within(dialog).getByText("Close"));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("shows a document written after the lane mounted, the next time the menu opens", async () => {
    filesMock.mockImplementation(async () => list("spec.md"));
    mount();
    const trigger = screen.getByRole("button", { name: "Plan Management of 070.00" });
    await waitFor(() => expect(filesMock).toHaveBeenCalledTimes(1));
    filesMock.mockImplementation(async () => list("spec.md", "plan.md", "pull-requests.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Plan", "Pull requests"]));
    expect(filesMock).toHaveBeenCalledTimes(2);
  });

  it("drops a document that was removed, the next time the menu opens", async () => {
    filesMock.mockImplementation(async () => list("spec.md", "blocked.md"));
    mount();
    const trigger = screen.getByRole("button", { name: "Plan Management of 070.00" });
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Blocked"]));
    await userEvent.keyboard("{Escape}");
    filesMock.mockImplementation(async () => list("spec.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps the trigger usable for a plan with no documents, says so in the menu, and reads again on the next open", async () => {
    filesMock.mockImplementation(async () => list());
    mount();
    const trigger = screen.getByRole("button", { name: "Plan Management of 070.00" });
    await waitFor(() => expect(filesMock).toHaveBeenCalledTimes(1));
    expect(trigger).toBeEnabled();
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["This plan has no documents yet"]));
    expect(section("Documents").getByRole("menuitem")).toHaveAttribute("aria-disabled", "true");
    await userEvent.keyboard("{Escape}");
    filesMock.mockImplementation(async () => list("spec.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps the trigger usable after a failed list, says why in the menu, and retries on the next open", async () => {
    filesMock.mockImplementation(async () => new Response(JSON.stringify({ error: "the server is restarting" }), { status: 503 }));
    mount();
    const trigger = screen.getByRole("button", { name: "Plan Management of 070.00" });
    await waitFor(() => expect(filesMock).toHaveBeenCalledTimes(1));
    expect(trigger).toBeEnabled();
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Could not list the documents: the server is restarting"]));
    await userEvent.keyboard("{Escape}");
    filesMock.mockImplementation(async () => list("spec.md", "plan.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Plan"]));
  });

  it("shows a loading item, not an empty menu, while the list is on its way", async () => {
    let answer: (r: Response) => void = () => {};
    filesMock.mockImplementation(() => new Promise<Response>((r) => { answer = r; }));
    mount();
    await userEvent.click(screen.getByRole("button", { name: "Plan Management of 070.00" }));
    expect(items()).toEqual(["Loading\u2026"]);
    expect(section("Documents").getByRole("menuitem")).toHaveAttribute("aria-busy", "true");
    answer(list("spec.md"));
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps an open document open when the lane goes narrow, and shows no menu", async () => {
    const view = mount();
    await userEvent.click(screen.getByRole("button", { name: "Plan Management of 070.00" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: "Specification" }));
    const dialog = await screen.findByRole("dialog");
    view.rerender(tree("narrow"));
    expect(screen.getByRole("dialog")).toBe(dialog);
    expect(screen.queryByRole("button", { name: "Plan Management of 070.00", hidden: true })).toBeNull();
    await userEvent.click(within(dialog).getByText("Close"));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("shows nothing and fetches nothing on a narrow lane", () => {
    mount("narrow");
    expect(screen.queryByRole("button")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  describe("Actions", () => {
    const openMenu = async () => {
      mount();
      await userEvent.click(screen.getByRole("button", { name: "Plan Management of 070.00" }));
    };

    it("lists Documents, a divider, then the actions a plan not yet started offers", async () => {
      await openMenu();
      await waitFor(() => expect(actions()).toEqual(["Clear Dependencies", "Don't Start and Discard", "Defer"]));
      expect(screen.getByRole("separator")).toBeInTheDocument();
      expect(screen.getByText("Documents")).toBeInTheDocument();
      expect(screen.getByText("Actions")).toBeInTheDocument();
    });

    it("calls discarding a started plan Abort & Discard, and offers only what the server allows", async () => {
      actionsMock.mockImplementation(async () => json(offer({ started: true, depends_on: [], actions: ["discard", "defer"] })));
      await openMenu();
      await waitFor(() => expect(actions()).toEqual(["Abort & Discard", "Defer"]));
    });

    it("says so when the state offers nothing", async () => {
      actionsMock.mockImplementation(async () => json(offer({ actions: [] })));
      await openMenu();
      await waitFor(() => expect(actions()).toEqual(["Nothing to do from this state"]));
    });

    it("defers only once a trigger is named, and posts it", async () => {
      await openMenu();
      await userEvent.click(await screen.findByRole("menuitem", { name: "Defer" }));
      const dialog = await screen.findByRole("dialog", { name: "Defer: 070.00?" });
      const go = within(dialog).getByRole("button", { name: "Defer" });
      expect(go).toBeDisabled();
      actionsMock.mockImplementation(async () => json(offer({ status: "deferred" })));
      await userEvent.type(within(dialog).getByLabelText("What should bring it back?"), "when the API is stable");
      await userEvent.click(go);
      await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
      const post = actionsMock.mock.calls.find(([, init]) => (init as RequestInit | undefined)?.method === "POST");
      expect(JSON.parse(String((post?.[1] as RequestInit).body))).toEqual({ action: "defer", reason: "when the API is stable" });
    });

    it("keeps the dialog open with the server's reason when it refuses", async () => {
      await openMenu();
      await userEvent.click(await screen.findByRole("menuitem", { name: "Clear Dependencies" }));
      const dialog = await screen.findByRole("dialog");
      expect(dialog).toHaveTextContent("070.00 waits on 069.00");
      actionsMock.mockImplementation(async () => json({ error: "an agent is working on 070.00; stop it first" }, 409));
      await userEvent.click(within(dialog).getByRole("button", { name: "Clear Dependencies" }));
      expect(await within(dialog).findByRole("alert")).toHaveTextContent("stop it first");
    });
  });
});
