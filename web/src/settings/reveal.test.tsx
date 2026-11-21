import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { resetSession } from "../api/client";
import { SettingsPage } from "./SettingsPage";
import { doc } from "./fixture";
import { revealPane, takePendingReveal } from "./reveal";

const draw = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <SettingsPage />
    </QueryClientProvider>,
  );

beforeEach(() => {
  resetSession();
  vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(doc), { headers: { "Content-Type": "application/json" } })));
  vi.stubGlobal("requestAnimationFrame", () => 0);
});
afterEach(() => {
  takePendingReveal();
  vi.unstubAllGlobals();
});

it("opens a pane picked before the page mounted", async () => {
  revealPane("merge");
  draw();
  expect(await screen.findByRole("button", { name: "Collapse Merge" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Open General" })).toBeInTheDocument();
  expect(takePendingReveal()).toBeNull();
});

it("opens a pane picked while the page is up, and leaves nothing pending", async () => {
  draw();
  await userEvent.click(await screen.findByRole("button", { name: "Open General" }));
  act(() => revealPane("merge"));
  expect(screen.getByRole("button", { name: "Collapse Merge" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Open General" })).toBeInTheDocument();
  expect(takePendingReveal()).toBeNull();
});
