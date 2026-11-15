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
const legend = async () => userEvent.click(await screen.findByRole("button", { name: /States legend/ }));
const boxes = () => Array.from(document.querySelectorAll<HTMLElement>(".dep-node")).map(n => n.dataset.plan);

beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => graph }));
});
afterEach(() => vi.unstubAllGlobals());

it("draws a box per plan in a checked state and an arrow per edge, Approved off by default", async () => {
  draw();
  await waitFor(() => expect(boxes()).toEqual(["001.00", "002.00", "003.00", "004.00"]));
  await waitFor(() => expect(document.querySelectorAll("path.dep-edge[data-from]")).toHaveLength(2));
});

it("keeps the states legend folded until its button is pressed, and says how many states are drawn", async () => {
  draw();
  const toggle = await screen.findByRole("button", { name: /States legend/ });
  expect(toggle).toHaveAttribute("aria-expanded", "false");
  expect(toggle).toHaveTextContent("2 of 3 shown");
  expect(screen.queryByRole("checkbox")).toBeNull();
  await userEvent.click(toggle);
  expect(toggle).toHaveAttribute("aria-expanded", "true");
  expect(screen.getAllByRole("checkbox")).toHaveLength(3);
  await userEvent.click(toggle);
  expect(screen.queryByRole("checkbox")).toBeNull();
});

it("brings the archived plan in when Approved is checked", async () => {
  draw();
  await legend();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Approved/ }));
  expect(boxes()).toContain("005.00");
});

it("removes a state's boxes and leaves a dashed bridge whose tooltip names the hidden plan", async () => {
  draw();
  await legend();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Planned/ }));
  expect(boxes()).not.toContain("002.00");
  expect(document.querySelectorAll("path.dep-edge[data-from]")).toHaveLength(0);
  const bridge = document.querySelector<SVGElement>(".dep-bridge")!;
  expect(bridge.querySelector(".dep-edge")).toHaveClass("is-dashed");
  await userEvent.hover(bridge);
  expect((await screen.findAllByText(/002\.00 Second/))[0]).toBeInTheDocument();
});

it("re-arranges the same boxes and arrows when a layout is picked, and remembers the pick", async () => {
  const { unmount } = draw();
  const at = () => Object.fromEntries(Array.from(document.querySelectorAll<HTMLElement>(".react-flow__node")).map(n => [n.dataset.id, n.style.transform]));
  await waitFor(() => expect(boxes()).toHaveLength(4));
  expect(screen.getByRole("radio", { name: "Adaptive" })).toBeChecked();
  const before = at();
  for (const name of ["Top to bottom", "Circular", "Grid", "Left to right"]) {
    await userEvent.click(screen.getByRole("radio", { name }));
    await waitFor(() => expect(at()).not.toEqual(before));
    expect(boxes()).toEqual(["001.00", "002.00", "003.00", "004.00"]);
    expect(document.querySelectorAll("path.dep-edge[data-from]")).toHaveLength(2);
  }
  await userEvent.click(screen.getByRole("radio", { name: "Circular" }));
  expect(screen.getByTestId("dep-canvas")).toHaveAttribute("data-layout", "circular");
  unmount();
  draw();
  expect(await screen.findByRole("radio", { name: "Circular" })).toBeChecked();
});

it("says so when nothing is checked", async () => {
  draw();
  await legend();
  await userEvent.click(await screen.findByRole("checkbox", { name: /Building/ }));
  await userEvent.click(screen.getByRole("checkbox", { name: /Planned/ }));
  expect(screen.getByText(/No plans in the checked states/)).toBeInTheDocument();
});

it("reports a failed load", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }));
  draw();
  expect(await screen.findByRole("alert")).toHaveTextContent("500");
});
