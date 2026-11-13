import { QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DependenciesPage } from "./DependenciesPage";
import { createQueryClient } from "../api/queryClient";
import { graph } from "./fixture";

const draw = () => {
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false } });
  return render(
    <QueryClientProvider client={client}>
      <DependenciesPage />
    </QueryClientProvider>,
  );
};
const boxes = () => Array.from(document.querySelectorAll<HTMLElement>(".dep-node")).map(n => n.dataset.plan);

beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => graph }));
});
afterEach(() => vi.unstubAllGlobals());

it("draws a box per plan in a checked state and an arrow per edge, Approved off by default", async () => {
  draw();
  await waitFor(() => expect(boxes()).toEqual(["001.00", "002.00", "003.00", "004.00"]));
  expect(document.querySelectorAll("path.dep-edge[data-from]")).toHaveLength(2);
});

it("brings the archived plan in when Approved is checked", async () => {
  draw();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Approved/ }));
  expect(boxes()).toContain("005.00");
});

it("removes a state's boxes and leaves a dashed bridge whose tooltip names the hidden plan", async () => {
  draw();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Planned/ }));
  expect(boxes()).not.toContain("002.00");
  expect(document.querySelectorAll("path.dep-edge[data-from]")).toHaveLength(0);
  const bridge = document.querySelector<SVGElement>(".dep-bridge")!;
  expect(bridge.querySelector(".dep-edge")).toHaveClass("is-dashed");
  await userEvent.hover(bridge);
  expect((await screen.findAllByText(/002\.00 Second/))[0]).toBeInTheDocument();
});

it("says so when nothing is checked", async () => {
  draw();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Building/ }));
  await userEvent.click(screen.getByRole("checkbox", { name: /Planned/ }));
  expect(screen.getByText(/No plans in the checked states/)).toBeInTheDocument();
});

it("reports a failed load", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }));
  draw();
  expect(await screen.findByRole("alert")).toHaveTextContent("500");
});
