import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Car } from "./Car";
import { sampleCar, samplePlan } from "./sample";

const names = (n: number) => Array.from({ length: n }, (_, i) => `sub-agent-${i + 1}`);

const draw = (over: Partial<ReturnType<typeof sampleCar>>) => {
  const car = sampleCar(over);
  const { container } = render(<Car plan={samplePlan({ cars: [car] })} car={car} models={[]} />);
  return container.querySelector(".car") as HTMLElement;
};

describe("Car round and clock", () => {
  const when = (over: Partial<ReturnType<typeof sampleCar>>) => draw(over).querySelector(".car-when")!;

  it("shows the round, the rounds it may run and the time, between the tokens and the edge", () => {
    const tile = when({ round: 2, rounds: 3, elapsed: 382 });
    expect(tile).toHaveTextContent("Round 2 of 3 | 6m 22s");
    expect(tile.querySelector(".car-round")).not.toHaveClass("is-last");
    expect(tile.querySelector(".car-round")).toHaveAttribute("title", "Round 2 of 3: 1 more after this one if it does not finish.");
  });

  it("marks the last round, the one after which it asks for another", () => {
    const round = when({ round: 3, rounds: 3 }).querySelector(".car-round")!;
    expect(round).toHaveClass("is-last");
    expect(round).toHaveAttribute("title", "Round 3 of 3, its last: if it does not finish, it asks for another.");
  });

  it("never shows fewer rounds than the one it is on, and only the clock before a first round", () => {
    expect(when({ round: 4, rounds: 1, elapsed: 5 })).toHaveTextContent("Round 4 of 4 | 5s");
    expect(when({ round: 0, rounds: 1, elapsed: 5 })).toHaveTextContent(/^5s$/);
  });
});

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
