# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 36 | [\[013.00\] Coverage Gate](https://github.com/kigster/openlanes/pull/36) | Merged 🟣 |

## Verification (luke-backend, 2026-10-14)

The repo has no separate end-to-end suite. The integration proof spawns the real `exe/openlanes coverage` against a real git repository and plan, with a real test command; only the worktree seeder is pointed at `true`.

```
$ bundle exec rspec spec/openlanes/integration/coverage_gate_spec.rb
3 examples, 0 failures

$ bundle exec rspec spec/openlanes/coverage spec/openlanes/engine/coverage_gate_spec.rb spec/openlanes/cli/coverage_spec.rb
71 examples, 0 failures

$ bundle exec rspec spec/openlanes/evals/corpus_spec.rb -e coverage-minimum
4 examples, 0 failures

$ bundle exec rspec
2292 examples, 0 failures        (baseline: 2214 examples, 0 failures)

$ bundle exec rubocop
320 files inspected, no offenses detected
```

What the integration spec asserts:

- 95.00% against `minimum: 95`: exit 0, `coverage 95.00% meets the 95% minimum (lcov: coverage/lcov.info)`, and the report exists in the plan's worktree and not in the main tree.
- 94.99%: exit 1, `ok-to-merge withheld: coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)`.
- A command that writes no report: exit 1, `coverage counts as 0%: …/coverage/lcov.info is missing`.

Dogfood: `Coverage.read(format: :simplecov, path: "coverage/.resultset.json")` on this repository after the full suite reads 98.99%. Every new file under `lib/` is at 100% line coverage.

Note: running the suite rewrites `docs/badges/coverage_badge.svg`; it is reverted before each commit.


## Round 1 fix (luke-backend, 2026-10-15)

hansolo finding 1, `CoverageGate.figure` misprinting 10.03 as 10.02%: fixed. `.to_r` alone would not have done it, since the Float 10.03 is already 10.0299…; the figure now comes from the counts.

- `Coverage::Report#ratio` (new) is the exact `Rational` percentage; `percent` is `ratio.to_f`.
- `CoverageGate#judge` floors and compares `report.ratio`, not the Float.
- `CoverageGate.figure` floors a `Rational` exactly; a Float is read back as the shortest decimal it prints as.
- Specs: `Report#ratio` for 1003/10000 and for an unread report; every two-decimal figure 0.00..100.00 prints as itself, from the counts and from a Float (was 573 misprints); the gate's message says `10.03%` for LH 1003 of 10000.

```
$ bundle exec rspec spec/openlanes/engine/coverage_gate_spec.rb spec/openlanes/coverage
67 examples, 0 failures

$ bundle exec rspec
2296 examples, 0 failures

$ bundle exec rubocop
320 files inspected, no offenses detected
```

Re-verified 2026-10-15 09:12 PDT on the worktree diff, before signing: `bundle exec rspec` 2296 examples, 0 failures (exit 0); `bundle exec rubocop` 320 files, no offenses.
