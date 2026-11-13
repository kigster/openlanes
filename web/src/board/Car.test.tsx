import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Car, SpendBadge } from "./Car";
import { sampleCar, samplePlan } from "./sample";

const names = (n: number) => Array.from({ length: n }, (_, i) => `sub-agent-${i + 1}`);

const draw = (over: Partial<ReturnType<typeof sampleCar>>) => {
  const car = sampleCar(over);
  const { container } = render(<Car plan={samplePlan({ cars: [car] })} car={car} models={[]} />);
  return container.querySelector(".car") as HTMLElement;
};

describe("Car sub-agent lines", () => {
  it.each([
    [0, 0],
    [1, 1],
    [3, 3],
    [5, 3],
  ])("draws %i sub-agents as %i lines", (n, lines) => {
    const tile = draw({ subagents: names(n) });
    expect(tile.querySelectorAll(".car-stack-line")).toHaveLength(lines);
    expect(tile.classList.contains("car-fanned")).toBe(n > 0);
  });

  it("labels the tile, singular for one", () => {
    expect(draw({ subagents: names(1) }).getAttribute("aria-label")).toBe("1 sub-agent running");
    expect(draw({ subagents: names(3) }).getAttribute("title")).toBe("3 sub-agents running");
    expect(draw({ subagents: names(5) }).getAttribute("aria-label")).toBe("5 sub-agents running");
  });

  it("has no label at 0 or with the field absent", () => {
    expect(draw({ subagents: [] }).hasAttribute("aria-label")).toBe(false);
    const tile = draw({ subagents: undefined as unknown as string[] });
    expect(tile.hasAttribute("aria-label")).toBe(false);
    expect(tile.querySelector(".car-stack-line")).toBeNull();
    expect(tile.classList.contains("car-fanned")).toBe(false);
  });
});

describe("SpendBadge", () => {
  const show = (spend: Parameters<typeof SpendBadge>[0]["spend"]) => render(<SpendBadge spend={spend} />).container;

  it("shows spend against the cap with a meter", () => {
    const c = show({ usd: 1.84, cap: 5, over: false, unpriced_runs: 0 });
    expect(c.textContent).toContain("$1.84 / $5.00");
    expect(c.querySelector(".spend-meter")?.getAttribute("aria-valuenow")).toBe("37");
    expect(c.querySelector(".is-over")).toBeNull();
  });

  it("shows the over-budget style and reason past the cap", () => {
    const c = show({ usd: 6, cap: 5, over: true, unpriced_runs: 0 });
    expect(c.querySelector(".spend.is-over")).not.toBeNull();
    expect(c.textContent).toContain("over budget: $6.00 / $5.00");
  });

  it("shows the figure alone with no cap, and unpriced runs apart", () => {
    const c = show({ usd: 1.84, cap: null, over: false, unpriced_runs: 2 });
    expect(c.textContent).toContain("$1.84");
    expect(c.textContent).not.toContain("/");
    expect(c.querySelector(".spend-meter")).toBeNull();
    expect(c.textContent).toContain("+2 unpriced");
  });

  it("draws nothing without spend", () => {
    expect(show(undefined).textContent).toBe("");
  });
});
