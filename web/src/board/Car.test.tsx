import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Car } from "./Car";
import { sampleCar, samplePlan } from "./sample";

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
    const tile = draw({ subagents: n });
    expect(tile.querySelectorAll(".car-stack-line")).toHaveLength(lines);
    expect(tile.classList.contains("car-fanned")).toBe(n > 0);
  });

  it("labels the tile, singular for one", () => {
    expect(draw({ subagents: 1 }).getAttribute("aria-label")).toBe("1 sub-agent running");
    expect(draw({ subagents: 3 }).getAttribute("title")).toBe("3 sub-agents running");
    expect(draw({ subagents: 5 }).getAttribute("aria-label")).toBe("5 sub-agents running");
  });

  it("has no label at 0 or with the field absent", () => {
    expect(draw({ subagents: 0 }).hasAttribute("aria-label")).toBe(false);
    const tile = draw({ subagents: undefined as unknown as number });
    expect(tile.hasAttribute("aria-label")).toBe(false);
    expect(tile.querySelector(".car-stack-line")).toBeNull();
    expect(tile.classList.contains("car-fanned")).toBe(false);
  });
});
