import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { LaneDocuments } from "./LaneDocuments";

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn(async (url: string) =>
    url.endsWith("/files")
      ? new Response(JSON.stringify({ files: ["pull-requests.md", "plan.md", "spec.md"] }), { status: 200 })
      : new Response("# The spec\n", { status: 200, headers: { ETag: '"e"' } }));
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} }));
});
afterEach(() => vi.unstubAllGlobals());

const mount = (lanes?: "wide" | "narrow") =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <LaneDocuments ordinal="070.00" lanes={lanes} />
    </QueryClientProvider>,
  );

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

  it("disables the trigger when the plan has no documents", async () => {
    fetchMock.mockImplementation(async () => new Response(JSON.stringify({ files: [] }), { status: 200 }));
    mount();
    await waitFor(() => expect(screen.getByRole("button", { name: "Documents of 070.00" })).toBeDisabled());
    expect(screen.getByRole("button", { name: "Documents of 070.00" })).toHaveAttribute("title", "This plan has no documents yet");
  });

  it("shows nothing and fetches nothing on a narrow lane", () => {
    mount("narrow");
    expect(screen.queryByRole("button")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
