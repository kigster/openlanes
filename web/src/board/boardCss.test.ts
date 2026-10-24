import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

// vitest runs with css: false, which empties a ?raw import, so read the file itself.
const css = readFileSync(new URL("./board.css", import.meta.url), "utf8");

describe("board.css gear", () => {
  it("defines the spin keyframes", () => {
    expect(css).toMatch(/@keyframes car-gear-spin\s*\{/);
  });

  it("spins a running car's gear forever", () => {
    expect(css).toMatch(/\.car\.is-running \.car-gear\s*\{[^}]*animation:\s*car-gear-spin[^;}]*infinite/);
  });

  it("stills the gear under reduced motion with a selector as specific as the spinning one", () => {
    const block = css.slice(css.indexOf("@media (prefers-reduced-motion: reduce)"));
    expect(block).toMatch(/\.car\.is-running \.car-gear\s*\{\s*animation:\s*none;?\s*\}/);
  });
});
