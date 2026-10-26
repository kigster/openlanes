# Implementation plan, 013.00 (back end only; `plan-frontend.md` has no units)

## Baseline

`bundle exec rspec` before any change (2026-10-14 11:52, Ruby 4.1.0-preview1): `2214 examples, 0 failures`. No baseline failures.

## Progress

| Unit | State | Proof |
| --- | --- | --- |
| B1 `Coverage::Config` | done | `spec/openlanes/coverage/config_spec.rb`, 16 examples |
| B2 `Coverage::Report` and four parsers | done | `spec/openlanes/coverage/{report,lcov,cobertura,istanbul,simplecov}_spec.rb`, 35 examples |
| B3 `Engine::CoverageGate` | done | `spec/openlanes/engine/coverage_gate_spec.rb`, 12 examples |
| B4 `openlanes coverage` | done | `spec/openlanes/cli/coverage_spec.rb`, 8 examples |
| B5 staff-reviewer text and eval case | done | `evals/cases/staff-reviewer/coverage-minimum.yml`, scored by `spec/openlanes/evals/corpus_spec.rb` |
| B6 integration check | done | `spec/openlanes/integration/coverage_gate_spec.rb`, 3 examples |

## Interfaces (what plan 014 and PR #26 call)

### `OpenLanes::Engine.coverage_gate(timeout: 1800, spawner: Execution::Child)` → `Engine::CoverageGate`

`#call(checkout:)` → `Engine::CoverageGate::Verdict`. `checkout` responds to `path` (absolute) and `dirty?`; a `Vcs::Worktree::Checkout` does. Never raises for anything the project wrote; every failure is a withheld verdict.

Order of checks, first match wins:

| Condition | `passed?` | `percent` | `reason` |
| --- | --- | --- | --- |
| `checkout.dirty?` | false | 0.0 | `<path> has uncommitted changes; coverage is measured only in a clean checkout` (nothing runs) |
| no `.openlanes.coverage.yml` in the checkout | false | 0.0 | `no .openlanes.coverage.yml in <path>; backend-coder declares command, report, format and minimum (M15)` |
| invalid declaration | false | 0.0 | the `Coverage::Invalid` message, `<file>: <what>` |
| command ran past `timeout` | false | 0.0 | ``coverage counts as 0%: `<command>` ran past <n>s and was stopped`` |
| command exited non-zero | false | 0.0 | ``coverage counts as 0%: `<command>` exited <status>`` |
| report mtime before the run started | false | 0.0 | `coverage counts as 0%: <report> is older than this run, so the command did not write it` |
| report missing, unreadable, malformed or empty | false | 0.0 | `coverage counts as 0%: <path> is missing` / `cannot be read (…)` / `is not a <format> report (…)` / `has no instrumented lines` |
| percent < minimum | false | the figure | `coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)` |
| otherwise | true | the figure | `coverage 95.00% meets the 95% minimum (lcov: coverage/lcov.info)` |

`Verdict = Data.define(:passed, :percent, :minimum, :reason, :config, :output)`:

- `passed?`, `withheld?`.
- `percent` → `Float`, unrounded; `CoverageGate.figure(percent)` floors to two decimals for display.
- `minimum` → `Float`, `nil` when there is no declaration.
- `config` → `Coverage::Config` or `nil`.
- `output` → the command's last 20 lines, `[]` when it never ran.
- `to_s` → `reason` when passed, `"ok-to-merge withheld: #{reason}"` otherwise.

The command runs as `sh -c <command>` with `chdir: checkout.path`, through `Execution::Child` (own process group, the environment Bundler was loaded under, killed on harness exit).

### Wiring `ok-to-merge` (not built here)

Nothing on `main` sets `ok-to-merge`. Whichever lands after this plan:

- **PR #26 (plan 005)**: `Vcs::Review#refusal(label, ci)` gains a third input. When `label.name == "ok-to-merge"`, it calls `Engine.coverage_gate.call(checkout:)` and returns `verdict.reason` unless `verdict.passed?`. `Review#call` then needs the PR's checkout, which plan 014 supplies.
- **Plan 014 (`verifier`)**: after a passing walk-through, the engine, not verifier, runs the gate (as it merges, M2: a label that gates a merge is not an agent's to grant) on the same clean checkout before applying `ok-to-merge`, and on a withheld verdict applies `review-rejected` with `verdict.to_s` and `verdict.output` as the comment.

### `OpenLanes::Coverage` (pure: no processes)

| Call | Returns | Errors |
| --- | --- | --- |
| `Coverage.config(root)` | `Coverage::Config` or `nil` | `Coverage::Invalid` |
| `Coverage.read(format:, path:)` | `Coverage::Report` (`covered`, `relevant`, `problem`, `percent`, `read?`) | none: problems are data |
| `Coverage::Simplecov.lines_by_file(text)` | `Hash{path => Array<Integer, nil>}`, every command's run merged | `Coverage::Malformed`, `JSON::ParserError` |

### `openlanes coverage PLAN [-n]`

STDOUT: `Verdict#to_s`, one line. STDERR: the command's tail when withheld. Exit 0 passed, 1 withheld, 65 invalid declaration under `-n`, 66 unknown plan or not a git repository. Runs in `Vcs.worktree(root:).checkout_for(feature)`, creating the worktree if needed. `-n` prints the worktree path and, if it exists, the declaration; creates and runs nothing.

## Shared logic with PR #27

`bin/coverage-changed` (PR #27) merges `.resultset.json` runs the same way: sum per line, `nil` only where every run says `nil`. `Coverage::Simplecov.lines_by_file` is that loop. Once both are on `main`, `bin/coverage-changed` can `require "openlanes"` and replace its loop with one call; its per-file rules (unloaded file 0%, loaded with no code 100%) stay in the script, since the gate judges the project, not files. The TypeScript checker reads istanbul's `coverage-final.json` statements per file and has no Ruby twin to share.

## File ownership

All files are backend-coder's (B1–B6). No shared files beyond `lib/openlanes/coverage.rb` (B1, then B2).

Amended: `spec/support/coverage_fixtures.rb` and one `require_relative` line in `spec/spec_helper.rb`, not in the plan's tables: the parser specs share fixture lookup. `lib/openlanes.rb` gained one `loader.collapse` line for `cli/coverage`, as every command directory has.
