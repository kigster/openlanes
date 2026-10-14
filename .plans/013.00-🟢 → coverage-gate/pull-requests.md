# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |

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

> [!NOTE]
>
> [2026-10-14 11:51:04 AM PDT] [ agent: luke-backend   status: Started, round 1 ]
> [2026-10-14 12:01:20 PM PDT] [ agent: luke-backend   status: Completed, round 1 ]
