import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "vitest-axe";
import { Board, MachineBoard } from "./Board";
import { PlanRow } from "./PlanRow";
import { nodePlanKey } from "./model";
import { sampleBoard, sampleCar, samplePlan, samplePr } from "./sample";

const none = new Map<string, unknown>();
const noRetire = new Set<string>();

describe("Board", () => {
  it("draws the stations, one row per plan, and cars under the station, accessibly", async () => {
    const board = sampleBoard();
    const { container } = render(<Board board={board} merged={false} retiring={noRetire} gone={none} />);
    expect(screen.getByText("Building UI")).toBeInTheDocument();
    expect(screen.getByText("luke + rey + r2d2")).toBeInTheDocument();
    expect(screen.getAllByRole("article")).toHaveLength(board.me.plans.length);
    const row = container.querySelector<HTMLElement>('[data-plan="001.00"]')!;
    expect(row.id).toBe("row-001.00");
    expect(within(row).getByText("Clean agent boundaries and transitions")).toBeInTheDocument();
    expect(within(row).getByText("needs you")).toBeInTheDocument();
    expect(row.querySelectorAll(".stop.is-done")).toHaveLength(3);
    expect(row.querySelector(".stop.is-here")).not.toBeNull();
    expect(await axe(container)).toHaveNoViolations();
  });

  it("opens a car through its name and marks the open one", async () => {
    const board = sampleBoard();
    const onOpenCar = vi.fn();
    render(
      <Board board={board} merged={false} retiring={noRetire} gone={none} openCar="001.00/rey-frontend" onOpenCar={onOpenCar}
        renderModel={(_p, car) => <span data-testid="pick">{car.model}</span>} />,
    );
    const rey = screen.getByRole("button", { name: "rey-frontend" });
    expect(rey).toHaveAttribute("aria-expanded", "true");
    await userEvent.click(screen.getByRole("button", { name: "luke-backend" }));
    expect(onOpenCar).toHaveBeenCalledWith(expect.objectContaining({ ordinal: "001.00" }), expect.objectContaining({ agent: "luke-backend" }));
    // Blocked cars show "needs you" in place of the dropdown.
    expect(screen.getAllByTestId("pick").map(e => e.textContent)).toEqual(["claude-sonnet-5-5", "claude-sonnet-5-5"]);
  });

  it("leaves gone rows out and says so when nothing is left", () => {
    const board = sampleBoard();
    const gone = new Map(board.me.plans.map(p => [p.ordinal, p]));
    render(<Board board={board} merged={false} retiring={noRetire} gone={gone} />);
    expect(screen.queryAllByRole("article")).toHaveLength(0);
    expect(screen.getByText("No plans in this run yet. Add one from Action.")).toBeInTheDocument();
  });

  it("appends other machines under ours with All machines on, read only and faded", async () => {
    const board = sampleBoard();
    board.others[0].node.ip = null;
    // A merged plan of theirs that has already left their board.
    board.others[0].plans.push(samplePlan({ ordinal: "011.00", pr: samplePr({ state: "merged" }) }));
    const life = { retiring: new Set<string>(), gone: new Map([[nodePlanKey(board.others[0].node.id, "011.00"), 1]]) };
    const { container } = render(<Board board={board} merged retiring={noRetire} gone={none} theirs={life} />);
    const heads = container.querySelectorAll(".machine-head");
    expect(heads).toHaveLength(2);
    expect(heads[0]).toHaveTextContent("dana@studio-mini10.0.4.123 plansthis machine");
    expect(heads[1]).toHaveTextContent("sam@ci-runner-21 plansread onlylast seen 0s ago");
    const theirs = container.querySelector(".plan.is-theirs")!;
    expect(theirs).toHaveAttribute("aria-label", "010 Cache agent registry lookups, on sam@ci-runner-2, read only");
    expect(within(theirs as HTMLElement).queryByRole("button")).toBeNull();
    expect(within(theirs as HTMLElement).getByText("Sonnet 5.5")).toBeInTheDocument();
    expect(await axe(container)).toHaveNoViolations();
  });
});

it("keeps another machine's merged row on the board, purple, until its lifecycle retires it", () => {
  const board = sampleBoard();
  const id = board.others[0].node.id;
  board.others[0].plans[0].pr = samplePr({ state: "merged" });
  const { container, rerender } = render(<Board board={board} merged retiring={noRetire} gone={none} />);
  expect(container.querySelector('.plan.is-theirs[data-plan="010.00"]')).not.toBeNull();
  rerender(<Board board={board} merged retiring={noRetire} gone={none} theirs={{ retiring: new Set([nodePlanKey(id, "010.00")]), gone: none }} />);
  expect(container.querySelector('[data-plan="010.00"]')).toHaveClass("is-retiring");
  rerender(<MachineBoard their={board.others[0]} me={board.me} life={{ retiring: new Set([nodePlanKey(id, "010.00")]), gone: none }} />);
  expect(container.querySelector('[data-plan="010.00"]')).toHaveClass("is-retiring");
  rerender(<MachineBoard their={board.others[0]} me={board.me} life={{ retiring: noRetire, gone: new Map([[nodePlanKey(id, "010.00"), 1]]) }} />);
  expect(container.querySelector('[data-plan="010.00"]')).toBeNull();
});

describe("MachineBoard", () => {
  it("opens with the read-only note and draws their plans", () => {
    const board = sampleBoard();
    render(<MachineBoard their={board.others[0]} me={board.me} />);
    expect(screen.getByText(/is working on these in \/srv\/checkouts\/openlanes; this machine will not start them. Last seen 0s ago./)).toBeInTheDocument();
    expect(screen.getByText("(10.0.4.37)", { exact: false })).toBeInTheDocument();
    expect(screen.getByText("on sam@ci-runner-2")).toBeInTheDocument();
  });

  it("leaves the IP out when the node has none", () => {
    const board = sampleBoard();
    board.others[0].node.ip = null;
    render(<MachineBoard their={board.others[0]} me={board.me} />);
    expect(screen.queryByText(/10\.0\.4\.37/)).toBeNull();
  });
});

describe("PlanRow", () => {
  const stations = sampleBoard().me.stations;
  const models = sampleBoard().me.models;

  it("ends at the PR terminus with approved, merged and other states", () => {
    const { rerender, container } = render(
      <PlanRow plan={samplePlan({ station: "pr", pr: samplePr({ state: "approved", ci: "passing" }) })} stations={stations} models={models} />,
    );
    const link = screen.getByRole("link", { name: /PR #44/ });
    expect(link).toHaveAttribute("href", "https://github.com/example-org/example-repo/pull/44");
    expect(link).toHaveAttribute("target", "_blank");
    expect(screen.getByText("CI passing")).toBeInTheDocument();
    expect(screen.getByText("approved")).toHaveClass("chip-approved");
    expect(container.querySelector(".cars")).toHaveClass("is-late");

    rerender(<PlanRow plan={samplePlan({ station: "pr", pr: samplePr({ state: "merged", ci: "passing" }) })} stations={stations} models={models} />);
    expect(screen.getByRole("link", { name: /PR #44/ })).toHaveClass("is-merged");
    expect(screen.queryByText("CI passing")).toBeNull();
    expect(screen.getByText("merged")).toBeInTheDocument();

    rerender(<PlanRow plan={samplePlan({ station: "pr", pr: samplePr({ state: "rejected", ci: "failing" }) })} stations={stations} models={models} />);
    expect(screen.getByText("CI failing")).toBeInTheDocument();
    expect(screen.getByText("rejected")).toBeInTheDocument();

    rerender(<PlanRow plan={samplePlan({ station: "pr", pr: samplePr({ state: "closed", ci: null }) })} stations={stations} models={models} />);
    expect(screen.getByText("closed")).toHaveClass("chip");
  });

  it("shows cars and the PR under review side by side", () => {
    render(<PlanRow plan={samplePlan({ station: "in_review", pr: samplePr() })} stations={stations} models={models} onOpenCar={vi.fn()} />);
    expect(screen.getByText("CI running")).toBeInTheDocument();
    expect(screen.getByText("review-in-progress")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "luke-backend" })).toBeInTheDocument();
    // Without a model slot the model shows as text.
    expect(screen.getByText("Opus 5.5")).toBeInTheDocument();
  });

  it("shows an interrupted plan's queued car", () => {
    render(
      <PlanRow plan={samplePlan({ cars: [], interrupted: { agent: "leah-researcher", at: "t", note: "" } })} stations={stations} models={models} />,
    );
    expect(screen.getByText("interrupted")).toBeInTheDocument();
    expect(screen.getByText("You interrupted it. Keep its work or discard it in Needs you.")).toBeInTheDocument();
  });

  it("marks a failed car red and a retiring row as leaving", () => {
    const { container } = render(
      <PlanRow plan={samplePlan({ cars: [sampleCar({ state: "failed", message: "rspec crashed" })] })} stations={stations} models={models} retiring />,
    );
    expect(container.querySelector(".plan")).toHaveClass("is-retiring");
    expect(screen.getByText("failed")).toBeInTheDocument();
    expect(screen.getByText("rspec crashed")).toHaveAttribute("title", "rspec crashed");
  });
});

describe("locked plan", () => {
  const stations = sampleBoard().me.stations;
  const models = sampleBoard().me.models;

  it("shows 🔑 on its car, titled with the holder", () => {
    const locked = { pid: 4242, host: "studio-mini", started_at: "2026-10-13T09:00:00Z" };
    render(<PlanRow plan={samplePlan({ locked })} stations={stations} models={models} />);
    expect(screen.getByLabelText(/locked by pid 4242 on studio-mini/)).toHaveTextContent("🔑");
  });

  it("shows no 🔑 when the plan is unlocked", () => {
    render(<PlanRow plan={samplePlan({ locked: null })} stations={stations} models={models} />);
    expect(screen.queryByText("🔑")).toBeNull();
  });
});
