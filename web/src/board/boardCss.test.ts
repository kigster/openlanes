/// <reference types="node" />
import { readFileSync } from "node:fs";

// Read from disk (vitest runs from web/): vitest runs with css: false, which turns a ?raw import of a stylesheet into an empty string.
const css = readFileSync("src/board/board.css", "utf8");

describe("board.css gear", () => {
  it("defines the spin keyframe", () => {
    expect(css).toMatch(/@keyframes car-gear-spin\s*\{[^@]*rotate\(360deg\)/);
  });

  it("spins the gear forever on a running car", () => {
    expect(css).toMatch(/\.car\.is-running \.car-gear\s*\{[^}]*animation:\s*car-gear-spin[^;]*infinite/);
  });

  it("stills the gear under reduced motion", () => {
    const block = css.slice(css.indexOf("@media (prefers-reduced-motion: reduce)"));
    // The selector must match the spin rule's: a bare .car-gear is less specific and loses, so the gear kept turning.
    expect(block).toMatch(/\.car\.is-running \.car-gear\s*\{\s*animation:\s*none;/);
  });

  it("keeps the name on the left when the gear joins the header", () => {
    // Under space-between alone, a third child (the gear) split the slack around the name and it left the edge.
    expect(css).toMatch(/\.car-top > :is\(\.car-agent, \.car-open\)\s*\{\s*margin-right:\s*auto;/);
  });
});
