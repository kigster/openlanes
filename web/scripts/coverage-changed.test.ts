import { isMeasured, measure, report, type FileCoverage } from "./coverage-changed";

const entry = (path: string, hits: number[]): FileCoverage => ({ path, s: Object.fromEntries(hits.map((n, i) => [String(i), n])) });
const coverage = {
  "/w/src/a.ts": entry("/w/src/a.ts", [1, 1, 1, 1]),
  "/w/src/b.ts": entry("/w/src/b.ts", [1, 0, 1, 1]),
  "/w/src/types.ts": entry("/w/src/types.ts", []),
};

it("passes when every changed file is at or above 95%", () => {
  const { ok, lines } = report(measure(coverage, ["src/a.ts", "src/types.ts"], "/w"));
  expect(ok).toBe(true);
  expect(lines.join("\n")).toContain("src/a.ts");
});

it("fails a file under 95% and names it", () => {
  const { ok, lines } = report(measure(coverage, ["src/a.ts", "src/b.ts"], "/w"));
  expect(ok).toBe(false);
  expect(lines.at(-1)).toContain("src/b.ts");
  expect(lines.at(-1)).not.toContain("src/a.ts");
});

it("fails a changed file that no test loaded", () => {
  const { ok, lines } = report(measure(coverage, ["src/never.ts"], "/w"));
  expect(ok).toBe(false);
  expect(lines.at(-1)).toContain("src/never.ts");
});

it("passes with no changed files", () => {
  const { ok, lines } = report([]);
  expect(ok).toBe(true);
  expect(lines[0]).toMatch(/no changed files/);
});

it("measures only source files", () => {
  expect(isMeasured("src/a.tsx")).toBe(true);
  expect(isMeasured("src/a.test.tsx")).toBe(false);
  expect(isMeasured("src/test/setup.ts")).toBe(false);
  expect(isMeasured("src/vite-env.d.ts")).toBe(false);
  expect(isMeasured("src/index.css")).toBe(false);
});
