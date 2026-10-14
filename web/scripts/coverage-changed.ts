// Fails when a web/src file changed on this branch has under 95% statement coverage.
// Run after `vitest run --coverage`: reads coverage/coverage-final.json (the istanbul `json` reporter).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const THRESHOLD = 95;

/** One file's entry in coverage-final.json; `s` maps a statement id to its hit count. */
export interface FileCoverage {
  path: string;
  s: Record<string, number>;
}

export interface Row {
  file: string;
  covered: number;
  total: number;
  percent: number;
}

/** Statement coverage per changed file, as a percentage. A changed file with no entry was never loaded by a test: 0%. */
export function measure(coverage: Record<string, FileCoverage>, changed: string[], root: string): Row[] {
  const byRelative = new Map<string, FileCoverage>();
  for (const entry of Object.values(coverage)) byRelative.set(relative(root, entry.path), entry);
  return changed.map((file) => {
    const found = byRelative.get(file);
    if (!found) return { file, covered: 0, total: 0, percent: 0 };
    const counts = Object.values(found.s);
    const covered = counts.filter((n) => n > 0).length;
    // A file with no statements (types only) has nothing to cover.
    const percent = counts.length === 0 ? 100 : (covered / counts.length) * 100;
    return { file, covered, total: counts.length, percent };
  });
}

/** Only source files count: tests, fixtures of the test harness and declaration files are not measured. */
export function isMeasured(file: string): boolean {
  return /^src\/.*\.tsx?$/.test(file) && !/\.test\.tsx?$/.test(file) && !file.startsWith("src/test/") && !file.endsWith(".d.ts");
}

export function report(rows: Row[], threshold = THRESHOLD): { ok: boolean; lines: string[] } {
  if (rows.length === 0) return { ok: true, lines: ["coverage:changed: no changed files under web/src"] };
  const lines = rows.map((r) => `${r.percent >= threshold ? "ok  " : "FAIL"} ${r.percent.toFixed(1).padStart(5)}%  ${r.covered}/${r.total}  ${r.file}`);
  const failing = rows.filter((r) => r.percent < threshold);
  if (failing.length) lines.push(`coverage:changed: ${failing.length} file(s) under ${threshold}%: ${failing.map((r) => r.file).join(", ")}`);
  return { ok: failing.length === 0, lines };
}

function main(): number {
  const webRoot = resolve(fileURLToPath(import.meta.url), "../..");
  const git = (args: string[]) => execFileSync("git", args, { cwd: webRoot, encoding: "utf8" });
  const top = git(["rev-parse", "--show-toplevel"]).trim();
  const changed = git(["diff", "--name-only", "--diff-filter=d", "origin/main...HEAD", "--", "src"])
    .split("\n")
    .filter(Boolean)
    // git prints paths from the repository root; coverage paths are made relative to web/.
    .map((f) => relative(webRoot, resolve(top, f)))
    .filter(isMeasured);
  const coverage = JSON.parse(readFileSync(resolve(webRoot, "coverage/coverage-final.json"), "utf8")) as Record<string, FileCoverage>;
  const { ok, lines } = report(measure(coverage, changed, webRoot));
  console.log(lines.join("\n"));
  return ok ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exit(main());
