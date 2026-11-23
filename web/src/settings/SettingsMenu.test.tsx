import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SettingsMenu } from "./SettingsMenu";
import { doc } from "./fixture";

const draw = (onPick = vi.fn()) =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <SettingsMenu onPick={onPick} />
    </QueryClientProvider>,
  );

afterEach(() => vi.unstubAllGlobals());

it("lists the outer panes' headings and hands back the one picked", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(doc), { headers: { "Content-Type": "application/json" } })));
  const pick = vi.fn();
  draw(pick);
  expect(screen.getByText("Loading…")).toBeInTheDocument();
  await screen.findByRole("button", { name: "General" });
  expect(screen.getAllByRole("button").map(b => b.textContent)).toEqual(["General", "Merge"]);
  await userEvent.click(screen.getByRole("button", { name: "Merge" }));
  expect(pick).toHaveBeenCalledWith("merge");
});

it("says so when the settings cannot be loaded", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 500 })));
  draw();
  expect(await screen.findByText("Settings unavailable")).toBeInTheDocument();
});
