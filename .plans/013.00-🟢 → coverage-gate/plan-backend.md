# Back-end units, plan 013.00

## B1 `Coverage::Config` (spec item 1)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/coverage.rb` (new, the facade), `lib/openlanes/coverage/config.rb` (new), `spec/openlanes/coverage/config_spec.rb` (new).
- **Must not touch:** `lib/openlanes/support/config.rb` (`.openlanes.yml` stays its own file), anything B2–B6 own.
- **Depends on:** nothing.
- **Builds:** `Coverage::Config = Data.define(:path, :command, :report, :format, :minimum)`, `Coverage::Config.load(root)` reading `<root>/.openlanes.coverage.yml`, `nil` when the file is absent. `FORMATS = %i[lcov cobertura istanbul simplecov]`. `Coverage::Invalid < OpenLanes::Error`, message `"<path>: <what is wrong>"` in the style of `Config.fail_with`. Facade: `Coverage.config(root)`.
- **Done when:** `spec/openlanes/coverage/config_spec.rb` loads a valid file, returns `nil` for an absent one, and raises `Coverage::Invalid` naming the key for: a missing key (each of the four), an unknown key, an unknown `format`, a `minimum` of `-1`, `100.5` and `"95"`, an empty `command`, and invalid YAML.

## B2 `Coverage::Report` (spec items 2–7)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/coverage/report.rb`, `lib/openlanes/coverage/{lcov,cobertura,istanbul,simplecov}.rb` (new), `lib/openlanes/coverage.rb` (adds `read`, after B1), `spec/openlanes/coverage/report_spec.rb`, `spec/openlanes/coverage/{lcov,cobertura,istanbul,simplecov}_spec.rb`, `spec/fixtures/coverage/**` (new).
- **Must not touch:** `engine/`, `cli/`.
- **Depends on:** B1 (shares the facade file).
- **Builds:** `Coverage::Report = Data.define(:covered, :relevant, :problem)` with `percent` (`0.0` when `relevant` is 0 or `problem` is set) and `Report.read(format:, path:)`. Each format module answers `parse(text) -> [covered, relevant]` and raises `Coverage::Malformed` on input it cannot read; `Report.read` turns a missing file, an unreadable one, `Malformed` and zero relevant lines into a `Report` with a `problem` and 0%. `Coverage::Simplecov.lines_by_file(json)` is public: the merged per-file line counts, so `bin/coverage-changed` (PR #27) can share it.
- **Done when:**
  - lcov: two `SF` blocks of different size yield the summed ratio, not the mean of per-file percentages.
  - cobertura: one fixture with `lines-covered`/`lines-valid`, one with only `line-rate`.
  - istanbul: `total.lines.covered / total.lines.total`; `pct: "Unknown"` with `total: 0` is the empty rule.
  - simplecov: a two-command `.resultset.json` yields `covered / (covered + missed)` over the merged lines, and both the `{"lines": [...]}` and the legacy array entry shapes read.
  - one spec each for missing, unreadable, malformed and empty, per format for empty.

## B3 `Engine::CoverageGate` (spec items 8, 9)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine/coverage_gate.rb` (new), `lib/openlanes/engine.rb` (adds `coverage_gate`), `spec/openlanes/engine/coverage_gate_spec.rb` (new).
- **Must not touch:** `dispatcher.rb`, `runner.rb`, `execution/child.rb` (used, not changed), `coverage/` (B1, B2).
- **Depends on:** B2.
- **Builds:** `CoverageGate.new(timeout: 1800, spawner: Execution::Child)`, `#call(checkout:) -> Verdict`. Order: refuse a dirty checkout; load the config from `checkout.path` (absent: withheld, M15 named); spawn `sh -c command` with `chdir: checkout.path` in the unbundled environment; kill the group on timeout; a non-zero exit, a timeout or a report older than the run is 0%; otherwise `Coverage.read`. `Verdict = Data.define(:passed, :percent, :minimum, :reason, :config, :output)` with `passed?` and `to_s`; `output` keeps the command's last 20 lines.
- **Done when:** `spec/openlanes/engine/coverage_gate_spec.rb`, with a `Vcs::Worktree::Checkout` double over a real temp directory and real `sh` commands: 94.99 is withheld and 95.0 passes at `minimum: 95`, and the message carries both numbers; the command's working directory is the checkout (it writes `pwd` to a file); a non-zero exit with a passing report, a timeout, a stale report, a dirty checkout and an absent config each withhold.

## B4 `openlanes coverage` (spec "Surfacing the figure")

- **Discipline:** back end.
- **Owns:** `lib/openlanes/cli/coverage/coverage.rb` (new), `lib/openlanes/cli.rb` (require, register, help group), `spec/openlanes/cli/coverage_spec.rb` (new).
- **Must not touch:** `presentation/reporter.rb`, every other command.
- **Depends on:** B3.
- **Builds:** `openlanes coverage PLAN [-n]`: resolves the plan, gets its checkout through `Vcs.worktree(root:).checkout_for`, runs the gate, prints `Verdict#to_s` on STDOUT, exits 1 when withheld. `-n` prints the declaration and where it would run, runs nothing.
- **Done when:** `spec/openlanes/cli/coverage_spec.rb` covers pass (exit 0), withheld (exit 1, figure and minimum on STDOUT), an unknown plan (refused), and `-n` running nothing; `spec/openlanes/cli/help_spec.rb` stays green with the command listed.

## B5 hansolo never lets `minimum` drop (spec item 10)

- **Discipline:** back end.
- **Owns:** `agents/hansolo-reviewer.md` (one line), `evals/cases/hansolo-reviewer/coverage-minimum.yml` and `evals/cases/hansolo-reviewer/coverage-minimum/{pass,fail}/**` (new).
- **Must not touch:** `lib/`.
- **Depends on:** nothing.
- **Builds:** a case whose fixture PR lowers `minimum` in `.openlanes.coverage.yml` from 95 to 90; hansolo must sign rejected and name the file. A pass recording (rejected, finding names `.openlanes.coverage.yml`) and a fail recording (approved).
- **Done when:** `spec/openlanes/evals/corpus_spec.rb` scores the pass recording as passing and the fail recording as failing.

## B6 Integration check

- **Discipline:** back end.
- **Owns:** `spec/openlanes/integration/coverage_gate_spec.rb` (new). Nothing else.
- **Must not touch:** every file B1–B5 own. A failure here is fixed in the owning unit.
- **Depends on:** B4.
- **Builds:** a temp git repository with a `PlansFixture` plan `001`, a committed `.openlanes.coverage.yml` whose `command` writes an lcov file, and `exe/openlanes coverage 001` spawned for real, with `OPENLANES_SETUP_WORKTREE` pointing at `true`.
- **Done when:** the spec shows exit 0 at 95.00%, exit 1 at 94.99% with both numbers on STDOUT, exit 1 when the command writes no report, and the report inside the plan's worktree and absent from the main tree.
