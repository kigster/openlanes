import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as api from "../api/planFiles";
import { PlanDrawer } from "./PlanDrawer";
import { carOf, planAt, renderPanel, snapshot } from "./testing";

const idle = () => {
  const plan = planAt(snapshot.plans[0]!.ordinal);
  plan.cars = [];
  return plan;
};

beforeEach(() => {
  vi.spyOn(api, "readPlanFile").mockResolvedValue({ body: "# Doc\n", etag: '"e"' });
});
afterEach(() => vi.restoreAllMocks());

describe("PlanDrawer", () => {
  it("renders nothing without a plan", () => {
    const { container } = renderPanel(<PlanDrawer plan={null} />);
    expect(container.querySelector(".plan-drawer")).toBeNull();
  });

  it("lists exactly the plan's files in a dropdown", async () => {
    vi.spyOn(api, "listPlanFiles").mockResolvedValue(["spec.md", "blocked.md"]);
    const plan = idle();
    renderPanel(<PlanDrawer plan={plan} />);
    const select = await screen.findByRole("combobox", { name: "Plan file" });
    const names = Array.from(select.querySelectorAll("option")).map((o) => o.value).filter(Boolean);
    expect(names).toEqual(["spec.md", "blocked.md"]);
    expect(api.listPlanFiles).toHaveBeenCalledWith(plan.ordinal);
  });

  it("says so when the plan has no files", async () => {
    vi.spyOn(api, "listPlanFiles").mockResolvedValue([]);
    renderPanel(<PlanDrawer plan={idle()} />);
    expect(await screen.findByText("No markdown files in this plan")).toBeInTheDocument();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("shows a failed listing", async () => {
    vi.spyOn(api, "listPlanFiles").mockRejectedValue(new Error("boom"));
    renderPanel(<PlanDrawer plan={idle()} />);
    expect(await screen.findByRole("alert")).toHaveTextContent("boom");
  });

  it("keeps one popup, replaced by the next choice, and may edit spec.md only without a car", async () => {
    vi.spyOn(api, "listPlanFiles").mockResolvedValue(["spec.md", "blocked.md"]);
    const user = userEvent.setup();
    renderPanel(<PlanDrawer plan={idle()} />);
    const select = await screen.findByRole("combobox", { name: "Plan file" });
    await user.selectOptions(select, "blocked.md");
    expect(await screen.findByRole("dialog", { name: /blocked\.md/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Close" }));
    await user.selectOptions(screen.getByRole("combobox", { name: "Plan file" }), "spec.md");
    await waitFor(() => expect(screen.getAllByRole("dialog")).toHaveLength(1));
    expect(screen.getByRole("dialog")).toHaveAccessibleName(/spec\.md/);
    expect(await screen.findByRole("button", { name: "Edit" })).toBeInTheDocument();
  });

  it("offers no Edit while the plan has a car", async () => {
    vi.spyOn(api, "listPlanFiles").mockResolvedValue(["spec.md"]);
    const plan = planAt(snapshot.plans.find((p) => p.cars.length > 0)!.ordinal);
    expect(carOf(plan, plan.cars[0]!.agent)).toBeTruthy();
    const user = userEvent.setup();
    renderPanel(<PlanDrawer plan={plan} />);
    await user.selectOptions(await screen.findByRole("combobox", { name: "Plan file" }), "spec.md");
    await screen.findByRole("heading", { name: "Doc" });
    expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
  });
});
