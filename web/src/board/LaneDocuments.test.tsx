import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { LaneDocuments } from "./LaneDocuments";

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn(async (url: string) =>
    url.endsWith("/files")
      ? new Response(JSON.stringify({ files: ["spec.md", "plan.md", "pull-requests.md"] }), { status: 200 })
      : new Response("# The spec\n", { status: 200, headers: { ETag: '"e"' } }));
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} }));
});
afterEach(() => vi.unstubAllGlobals());

// One client per test, so a rerender keeps its cache as the page's does.
let client: QueryClient;
beforeEach(() => { client = new QueryClient({ defaultOptions: { queries: { retry: false } } }); });
const tree = (lanes?: "wide" | "narrow") => (
  <QueryClientProvider client={client}>
    <LaneDocuments ordinal="070.00" lanes={lanes} />
  </QueryClientProvider>
);
const mount = (lanes?: "wide" | "narrow") => render(tree(lanes));
const list = (...files: string[]) => new Response(JSON.stringify({ files }), { status: 200 });
const items = () => screen.queryAllByRole("menuitem").map((i) => i.textContent);

describe("LaneDocuments", () => {
  it("lists the labels in order, and opening Specification mounts the modal until it is closed", async () => {
    mount();
    const trigger = screen.getByRole("button", { name: "Documents of 070.00" });
    await waitFor(() => expect(trigger).toBeEnabled());
    await userEvent.click(trigger);
    expect(screen.getAllByRole("menuitem").map((i) => i.textContent)).toEqual(["Specification", "Plan", "Pull requests"]);
    await userEvent.click(screen.getByRole("menuitem", { name: "Specification" }));
    const dialog = await screen.findByRole("dialog");
    expect(await within(dialog).findByRole("heading", { name: "The spec" })).toBeInTheDocument();
    await userEvent.click(within(dialog).getByText("Close"));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("shows a document written after the lane mounted, the next time the menu opens", async () => {
    fetchMock.mockImplementation(async () => list("spec.md"));
    mount();
    const trigger = screen.getByRole("button", { name: "Documents of 070.00" });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    fetchMock.mockImplementation(async () => list("spec.md", "plan.md", "pull-requests.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Plan", "Pull requests"]));
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("drops a document that was removed, the next time the menu opens", async () => {
    fetchMock.mockImplementation(async () => list("spec.md", "blocked.md"));
    mount();
    const trigger = screen.getByRole("button", { name: "Documents of 070.00" });
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Blocked"]));
    await userEvent.keyboard("{Escape}");
    fetchMock.mockImplementation(async () => list("spec.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps the trigger usable for a plan with no documents, says so in the menu, and reads again on the next open", async () => {
    fetchMock.mockImplementation(async () => list());
    mount();
    const trigger = screen.getByRole("button", { name: "Documents of 070.00" });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(trigger).toBeEnabled();
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["This plan has no documents yet"]));
    expect(screen.getByRole("menuitem")).toHaveAttribute("aria-disabled", "true");
    await userEvent.keyboard("{Escape}");
    fetchMock.mockImplementation(async () => list("spec.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps the trigger usable after a failed list, says why in the menu, and retries on the next open", async () => {
    fetchMock.mockImplementation(async () => new Response(JSON.stringify({ error: "the server is restarting" }), { status: 503 }));
    mount();
    const trigger = screen.getByRole("button", { name: "Documents of 070.00" });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(trigger).toBeEnabled();
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Could not list the documents: the server is restarting"]));
    await userEvent.keyboard("{Escape}");
    fetchMock.mockImplementation(async () => list("spec.md", "plan.md"));
    await userEvent.click(trigger);
    await waitFor(() => expect(items()).toEqual(["Specification", "Plan"]));
  });

  it("shows a loading item, not an empty menu, while the list is on its way", async () => {
    let answer: (r: Response) => void = () => {};
    fetchMock.mockImplementation(() => new Promise<Response>((r) => { answer = r; }));
    mount();
    await userEvent.click(screen.getByRole("button", { name: "Documents of 070.00" }));
    expect(items()).toEqual(["Loading\u2026"]);
    expect(screen.getByRole("menuitem")).toHaveAttribute("aria-busy", "true");
    answer(list("spec.md"));
    await waitFor(() => expect(items()).toEqual(["Specification"]));
  });

  it("keeps an open document open when the lane goes narrow, and shows no menu", async () => {
    const view = mount();
    await userEvent.click(screen.getByRole("button", { name: "Documents of 070.00" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: "Specification" }));
    const dialog = await screen.findByRole("dialog");
    view.rerender(tree("narrow"));
    expect(screen.getByRole("dialog")).toBe(dialog);
    expect(screen.queryByRole("button", { name: "Documents of 070.00", hidden: true })).toBeNull();
    await userEvent.click(within(dialog).getByText("Close"));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("shows nothing and fetches nothing on a narrow lane", () => {
    mount("narrow");
    expect(screen.queryByRole("button")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
