import { render, renderHook, screen } from "@testing-library/react";
import { TestsPanel } from "./TestsPanel";
import { boardNews, useBoardNews } from "./useBoardNews";
import { backlogNote } from "./notes";
import { testRuns } from "../board/model";
import { sampleBoard, sampleCar, samplePlan, samplePr } from "../board/sample";

describe("TestsPanel", () => {
  it("shows the command and how far it got", () => {
    const [run] = testRuns(sampleBoard().me.plans);
    render(<TestsPanel run={run} />);
    expect(screen.getByRole("heading", { name: "001 Clean agent boundaries and transitions: tests" })).toBeInTheDocument();
    expect(screen.getByText("npm test")).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "11");
  });

  it("copes with a run of nothing", () => {
    const [run] = testRuns([samplePlan({ cars: [sampleCar({ message: "Running x: 0 of 0" })] })]);
    render(<TestsPanel run={run} />);
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "0");
  });
});

describe("boardNews", () => {
  const before = sampleBoard().me;
  it("says nothing on the first snapshot or when nothing moved", () => {
    expect(boardNews(undefined, before)).toEqual([]);
    expect(boardNews(before, structuredClone(before))).toEqual([]);
  });

  it("announces advancing, approval and merging", () => {
    const after = structuredClone(before);
    after.plans[0].station = "building_ui";
    after.plans[1].pr = samplePr({ state: "approved" });
    after.plans[2].pr = samplePr({ state: "merged", number: 46 });
    after.plans.push(samplePlan({ ordinal: "099.00" }));
    expect(boardNews(before, after)).toEqual([
      "001 moved to Building UI.",
      "005 was approved and is ready to merge.",
      "PR #46 was merged on GitHub. 006 is complete.",
    ]);
    after.plans[0].station = "mystery";
    expect(boardNews(before, after)[0]).toBe("001 moved to mystery.");
  });

  it("speaks through the announcer once per change", () => {
    const announce = vi.fn();
    const moved = structuredClone(before);
    moved.plans[0].station = "in_review";
    const { rerender } = renderHook(({ s }) => useBoardNews(s, announce), { initialProps: { s: undefined as typeof before | undefined } });
    rerender({ s: before });
    rerender({ s: moved });
    expect(announce).toHaveBeenCalledTimes(1);
    expect(announce).toHaveBeenCalledWith("001 moved to Review.");
  });
});

describe("backlogNote", () => {
  it("names what the Action menu leaves out and why", () => {
    const board = sampleBoard();
    board.others[0].plans.push(samplePlan({ ordinal: "011.00", pr: samplePr({ state: "merged" }) }));
    expect(backlogNote(board)).toBe("Not listed: 001, 005, 006, 002 in this run; 010 on sam@ci-runner-2; 011 complete.");
  });

  it("says nothing when nothing is left out", () => {
    const board = sampleBoard();
    board.me.plans = [];
    board.others = [];
    expect(backlogNote(board)).toBeUndefined();
  });
});
