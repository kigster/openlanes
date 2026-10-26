---
depends_on: []
---

# Coverage Gate

## What we are trying to achieve

The engine runs the test command from `.openlanes.coverage.yml`, reads the coverage report in one of four formats, and withholds `ok-to-merge` below the minimum.

## Why it matters

Every project keeps about 95% unit test coverage, in any language, and a prompt cannot guarantee that.

## What already exists

- Decision M15 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.

## What research needs to settle

- Parsers for `lcov`, `cobertura`, `istanbul` and `simplecov`, and which figure each reports (lines or statements).

## How to tell it's working?

- Fixture reports in all four formats yield the right percentage.
- A missing report counts as 0% and blocks `ok-to-merge`.

## Framings

1. **Parser library.** A pure function `(format, report path) -> percentage`. The engine decides what to do with the number.
1. **Merge gate.** An engine step that runs the command in a clean checkout, parses, compares, and withholds `ok-to-merge`.

The gate (2) is the deliverable, and the parser (1) is its first work unit. Reason: M15 (`docs/decisions/decisions-on-merge-modes-and-verification.md:136-148`) defines behaviour at the merge boundary, and a parser alone enforces nothing.

## Goal

A project declares its test command, report path, format and minimum in `.openlanes.coverage.yml`. The engine runs the command, reads the report in `lcov`, `cobertura`, `istanbul` or `simplecov` format, and withholds `ok-to-merge` when line coverage is below the minimum or the report is missing. Today a prompt asks for 95% and nothing checks it.

## Non-Goals

- Not a coverage tool: the gate never instruments code or generates reports itself.
- Not a branch, function or statement gate. Lines only (open question 1).
- Not a trend tracker or badge: `Coverage::Badge` in `spec/spec_helper.rb` stays as is.
- Not a per-file or per-diff threshold: one project-wide figure.
- Not a change to the web project's own vitest thresholds (`web/vite.config.ts:21`).
- Not a replacement for CI: `ok-to-merge` still requires green CI (decisions doc line 37).

## In scope

Each item has its check.

1. A loader for `.openlanes.coverage.yml` with keys `command`, `report`, `format`, `minimum`. Check: a spec feeds a missing key, an unknown `format`, and a `minimum` outside 0-100, and each raises a named error, in the style of `Config` (`lib/openlanes/support/config.rb:148`).
1. An `lcov` parser: sum `LH` and `LF` over every `SF` block. Check: a fixture with two files of different size yields the summed ratio, not the mean of per-file percentages.
1. A `cobertura` parser: `lines-covered / lines-valid`, falling back to `line-rate * 100`. Check: one fixture per attribute set.
1. An `istanbul` parser: `total.lines.covered / total.lines.total`. Check: a fixture with `pct: "Unknown"` and `total: 0` is handled by the empty-report rule.
1. A `simplecov` parser. Check: a fixture yields the same figure as `covered / (covered + missed)` (open question 3 fixes the file).
1. A missing, unreadable or malformed report counts as 0%. Check: a spec per case.
1. An empty report (zero instrumented lines) counts as 0% (open question 2). Check: a fixture per format.
1. The gate withholds `ok-to-merge` below `minimum` and reports the figure and the minimum in its message. Check: a spec at 94.99 and 95.0 with `minimum: 95`.
1. The command runs in a clean checkout of the PR, never in the main tree. Check: a spec with a `Vcs::Worktree` double asserts the working directory.
1. A decision-level fixture for `staff-reviewer`: a diff that lowers `minimum` is rejected. Check: an eval case under `evals/cases/staff-reviewer/`.

## Out of scope

- Languages' own coverage runners: the project owns `command`.
- Writing `.openlanes.coverage.yml` for a project: backend-coder writes it per M15. This plan reads it.
- Adding `json-summary` to the web project: a web project change, tracked by open question 4.
- Branch coverage: M15 has one `minimum`.

## Back end / front end

| Item | Half |
| --- | --- |
| Config loader, four parsers, empty/missing rules | `backend-coder` |
| Gate step in the engine, wiring into the `ok-to-merge` decision | `backend-coder` |
| staff-reviewer eval case, agent text for "never lower `minimum`" | `backend-coder` |
| Surfacing the figure in `openlanes` output (Reporter) | `backend-coder` |
| Web dashboard display, if any | `frontend-coder`, only if open question 6 is answered yes |

## Open questions

Defaults below are what the plan builds unless the owner says otherwise.

1. **Lines or statements?** Default: lines for all four. Changes what 95% means in the web project (research, "Could not settle" 1).
1. **Empty report: 0% or pass?** Default: 0%, fail closed (research 2).
1. **Which simplecov file?** Default: `.resultset.json` with relevant lines computed, because `.last_run.json` is truncated and absent after failed runs. Alternative: add a JSON formatter to `spec_helper.rb` (research 3).
1. **Web report.** `web/vite.config.ts:22` writes `lcov.info`, not `coverage-summary.json`. Default: the web project's file declares `format: lcov` and no change to vite (research 4).
1. **Does the branch figure join the gate?** Default: no (research 5).
1. **Is a display in the web UI wanted?** Default: no.
1. **Where in the engine does the gate sit?** `rg "ok-to-merge" lib` finds nothing, so the verdict has no code home yet. Default: a new `Engine`-side class with a facade method, called by whichever component applies verdicts. Planning must locate it.
1. **Cobertura variants.** Only the gcovr 7.0 sample was seen (research 6). Default: support `lines-covered/lines-valid` and `line-rate` only.
1. **Command timeout and failure.** If `command` exits non-zero, does the gate still read a stale report? Default: no, a non-zero exit counts as 0%.

## Risks to planning or execution

- No code applies `ok-to-merge` today (open question 7), so the wiring may need a plan of its own. This is the largest risk.
- A stale report from an earlier run could pass the gate. Mitigation: a clean checkout, and a non-zero exit counts as 0%.
- Running a project's test command is arbitrary code execution. It must stay inside the autonomy boundary (`CLAUDE.md`, "The autonomy boundary") and use the worktree.
- The simplecov truncation to two decimals can flip a 94.995 into a pass. Mitigation: compute from counts.
- Spec runs print a whole-library SimpleCov figure even on a single file (`CLAUDE.md`), so tests of the gate must not read the repo's own `coverage/`.

## Conclusion

When this ships, a project with `.openlanes.coverage.yml` has its test command run in a clean PR checkout, its report parsed in one of four formats into a line percentage, and `ok-to-merge` withheld below the minimum or when the report is missing, empty, or malformed. Fixtures for each format and failure case prove it.

## Research

Researched 2026-10-13 by researcher. Repository facts were read from the worktree and by running `bundle exec rspec spec/openlanes/linear/fuzzy_spec.rb` (8 examples, 0 failures; the full suite was not run). External facts were fetched from the URLs below on 2026-10-13.

### Parsers and the figure each reports

| Format | Where the figure is | Figure | Parser notes |
| --- | --- | --- | --- |
| `lcov` (`lcov.info`) | Per `SF:` block: `LF:` (instrumented lines) and `LH:` (lines hit, count > 0) | Lines | No total record. Sum `LH` and `LF` over every `SF`…`end_of_record` block. Do not average per-file percentages. `BRF`/`BRH` and `FNF`/`FNH` are branch and function totals. |
| `cobertura` (XML) | Root `<coverage>`: `line-rate` (0–1 decimal) | Lines | Root also carries `lines-covered`, `lines-valid`, `branch-rate`, `branches-covered`, `branches-valid` (gcovr 7.0 sample). Prefer covered/valid counts when present, since `line-rate` is a rounded decimal. Multiply by 100. |
| `istanbul` (`coverage-summary.json`) | `total.lines.pct`; `total.statements.pct` is a separate figure | Lines (statements exists too) | Each metric has `total`, `covered`, `skipped`, `pct`. `pct` is a string `"Unknown"` when the total is 0. Compute from `covered / total`. |
| `simplecov` | `.last_run.json`: `result.line` (0–100). Raw counts in `coverage.json` `total.lines` and in `.resultset.json` | Lines (`branch` is separate) | `result.line` is written with two decimals, truncated: the same run gives `2.5573…` in `coverage.json` and `2.55` in `.last_run.json`. Exists only after a fully successful run. |

Evidence:

- `simplecov` percentage is `covered / (covered + missed)`, with never-relevant (`nil`) lines excluded. `coverage/coverage.json`: `lines` covered 205, missed 7811, omitted 16638, percent 2.5573852295409183. 205 / 8016 = 2.5574 (`simplecov-1.3.2/lib/simplecov/source_file.rb:77-78`, `source_file/statistics.rb:25-33`).
- `coverage/.last_run.json` and `coverage/coverage.json` share the mtime 19:23:05 and hold `line: 2.55`, `branch: 0.1`. Branch 3 / 2807 = 0.1069, stored as 0.1, so truncation applies to both figures. This is an artifact of a single-file run, not a suite figure.
- `simplecov-1.3.2/lib/simplecov/report_deferral.rb:19-20`: `.last_run.json` only exists after fully successful runs.
- `spec/spec_helper.rb:28-30`: the configured formatters are HTML and `Coverage::Badge`. Nothing in the first 30 lines writes `coverage.json`, so its origin is unknown. Do not depend on it.
- Istanbul `lines` is keyed by line, and each line takes the highest hit count of the statements starting on it. `statements` counts each statement (`istanbul-lib-coverage/lib/file-coverage.js`, fetched 2026-10-13).
- `istanbul-reports/lib/lcovonly/index.js` writes `LF`/`LH` from `summary.lines`, `DA` from `getLineCoverage()`, and `BRF`/`BRH`/`FNF`/`FNH` from the matching summary keys. So a vitest `lcov` file reports lines (fetched 2026-10-13).
- `istanbul-lib-coverage/lib/percent.js` returns `100.0` when total is 0, and floors to two decimals. The blank summary uses `pct: 'Unknown'`. An empty report is therefore not 0% in istanbul's own arithmetic (fetched 2026-10-13).
- LLVM's exporter comment defines the lcov record layout: `SF`, `FN`, `FNDA`, `FNF`, `FNH`, `DA`, `BRDA`, `BRF`, `BRH`, `LH` ("lines with non-zero execution count"), `LF` ("instrumented lines"), `end_of_record` (fetched 2026-10-13).

### Contradictions

1. M15 example (`docs/decisions/decisions-on-merge-modes-and-verification.md:138-144`) reads `coverage/coverage-summary.json` as `istanbul`. `web/vite.config.ts:22` enables `text-summary`, `html` and `lcov` only, so the web project does not produce that file. It produces `coverage/lcov.info`. Production today: the web project writes lcov.
2. M15 sets one `minimum: 95`. `web/vite.config.ts:21` sets vitest thresholds of statements 95, branches 90, functions 95, lines 95. The web project already gates on a different set of figures than M15 describes.
3. M15 names `.openlanes.coverage.yml`. It does not exist in this repository (checked: `cat` fails). No gate runs today.
4. `CLAUDE.md:38` says the Ruby badge lands in `~/github/kigster/docs/badges/`. `spec/spec_helper.rb:14` computes `REPO_ROOT` as the repository root, so the badge lands in `docs/badges/` inside the repo. The code is what runs.

### Could not settle

1. Gate on lines or on statements? All four formats report lines. Statements exists only in istanbul's JSON. Recommendation: lines, for all four. Owner to confirm, because it changes what 95% means in the web project.
2. Empty report (present, zero instrumented lines): 0% or pass? Istanbul's own arithmetic gives 100 for total 0. Recommendation: 0%, fail closed, matching the missing-report rule in the spec.
3. Which simplecov file to read. `.last_run.json` is absent after failed runs and truncated. `.resultset.json` needs recomputing. `coverage.json` is not written by the configured formatters. Recommendation: `.resultset.json`, with the relevant-line count computed, or a formatter added to `spec_helper.rb` that writes JSON.
4. Whether the web project adds the `json-summary` reporter so that `coverage-summary.json` exists, or M15 points at `lcov.info` instead. Not verified in the repo; `json-summary` is named from memory, not from a fetched source.
5. Branch gate: M15 has one minimum, the web project gates branches at 90. Owner decides whether branches join the gate.
6. Cobertura: the official DTD and the original Cobertura documentation were not retrieved. The attribute description comes from the gcovr 7.0 sample only. Other producers (for example coverage.py) were not checked.
7. lcov: the lcov project's own tracefile specification was not retrieved (the `geninfo` source was truncated before the summary code). LLVM's exporter and istanbul's writer agree, which is the basis for the table.

### Findings, Conclusion & References

Conclusion: all four formats can yield a line percentage with the parsers above. Three decisions block a correct gate: lines versus statements, empty-report handling, and which simplecov file is canonical. The repository has no `.openlanes.coverage.yml` and no json-summary reporter, so the M15 example path would not resolve today.

Sources (cited, not copied; all retrieved 2026-10-13):

- [LLVM `CoverageExporterLcov.cpp`](https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/tools/llvm-cov/CoverageExporterLcov.cpp). Licence: Apache-2.0 with LLVM exception, per the file header.
- [istanbuljs `istanbul-reports/lib/lcovonly/index.js`](https://raw.githubusercontent.com/istanbuljs/istanbuljs/master/packages/istanbul-reports/lib/lcovonly/index.js). Licence not checked.
- [istanbuljs `istanbul-lib-coverage/lib/percent.js`](https://raw.githubusercontent.com/istanbuljs/istanbuljs/master/packages/istanbul-lib-coverage/lib/percent.js) and [`file-coverage.js`](https://raw.githubusercontent.com/istanbuljs/istanbuljs/master/packages/istanbul-lib-coverage/lib/file-coverage.js). Licence not checked.
- [istanbul-lib-coverage 3.2.2 `coverage-summary.js`](https://unpkg.com/istanbul-lib-coverage@3.2.2/lib/coverage-summary.js). Licence not checked.
- [gcovr 7.0 Cobertura output](https://gcovr.com/en/7.0/output/cobertura.html). Licence not checked.
- [lcov `geninfo`](https://raw.githubusercontent.com/linux-test-project/lcov/master/bin/geninfo). Fetched, truncated, not used for facts.
- Local: `simplecov-1.3.2` gem source, installed under the Ruby 4.0.6 rbenv gem path. Licence not checked.
