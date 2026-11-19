import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as Tooltip from "@radix-ui/react-tooltip";
import { ReactFlow } from "@xyflow/react";
import { NO_SUMMARY, PlanNode } from "./PlanNode";
import { graph } from "./fixture";
import { NODE_HEIGHT, NODE_WIDTH } from "./model";

const draw = (i: number) =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
    <Tooltip.Provider delayDuration={0}>
      <ReactFlow
        nodeTypes={{ plan: PlanNode }}
        nodesDraggable={false}
        panOnDrag={false} // d3-drag reads event.view.document, which user-event does not send
        nodes={[{ id: "n", type: "plan", position: { x: 0, y: 0 }, width: NODE_WIDTH, height: NODE_HEIGHT, data: { plan: graph.plans[i]!, state: graph.states[0] } }]}
      />
    </Tooltip.Provider>
    </QueryClientProvider>,
  );

afterEach(() => vi.unstubAllGlobals());

it("shows the summary on hover", async () => {
  draw(0);
  await userEvent.hover(await screen.findByRole("button", { name: /First/ }));
  expect((await screen.findAllByText("The first plan."))[0]).toBeInTheDocument();
});

it("keeps it open after a click, and shows the fallback when there is none", async () => {
  draw(1);
  const box = await screen.findByRole("button", { name: /Second/ });
  await userEvent.click(box);
  expect(box).toHaveAttribute("aria-pressed", "true");
  expect((await screen.findAllByText(NO_SUMMARY))[0]).toBeInTheDocument();
  await userEvent.unhover(box);
  expect(screen.getAllByText(NO_SUMMARY)[0]).toBeInTheDocument();
});

it("lists the plan's documents from its box, asking only once the menu is opened, and opens one to read", async () => {
  const fetchMock = vi.fn(async (url: string) =>
    url.endsWith("/files")
      ? new Response(JSON.stringify({ files: ["spec.md", "plan.md"] }), { status: 200 })
      : new Response("# The spec\n", { status: 200, headers: { ETag: '"e"' } }));
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", (q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} }));
  draw(0);
  const trigger = await screen.findByRole("button", { name: "Plan Management of 001.00" });
  expect(fetchMock).not.toHaveBeenCalled();
  await userEvent.click(trigger);
  expect(await screen.findByRole("menuitem", { name: "Specification" })).toBeInTheDocument();
  expect(screen.getByRole("menuitem", { name: "Plan" })).toBeInTheDocument();
  await userEvent.click(screen.getByRole("menuitem", { name: "Specification" }));
  expect(await within(await screen.findByRole("dialog")).findByRole("heading", { name: "The spec" })).toBeInTheDocument();
});
