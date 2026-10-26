# Pull Requests

## Back end, rounds 1 and 2 (backend-coder)

Every unit under `## Backend` is built. There is no front end, so no contract and no mailbox (plan.md, `## Frontend`).

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 107 | [\[038.00\](A) Solid Seams and Thread Safety](https://github.com/kigster/openlanes/pull/107) | Merged 🟣 |

The stress spec found a real race: eight overlapping `Dispatcher#tick` calls started one plan eight times. `#tick` now runs under `@tick_lock`, a `Monitor`, and the inventory has a row for it.

### Checks from the spec

All the `rg` checks print nothing:

- `rg "store\.(publish|subscriber|xadd)|tx\.xadd" lib`: only `live/event_bus/base.rb`
- `rg "Time\.now" lib/openlanes/engine`
- `rg "Process\.spawn" lib`: only `support/spawner.rb`
- `rg "Adapters::Claude" lib`: nothing outside `adapters/`
- `rg "adapter.*\.name ==|case .*adapter" lib/openlanes/{execution,engine}`

### "Runs alone under the global lock (034)"

034 is not built. Following plan.md's decision (open question 4), this plan does not wait for it, and the criterion is met by the operator running no other plan while 038 builds. A human may still overturn that.

### Suite

- `bundle exec rubocop`: 544 files inspected, no offenses detected, exit 0
- `bundle exec rspec`: 4039 examples, 0 failures, 9 pending, coverage 98.83%, exit 0 (baseline: 3984 examples, 0 failures, 9 pending)
- A first full run failed `spec/openlanes/live/unblock_spec.rb:59`: it asserted before the agent thread had recorded its call. It passes alone, and `drain` now waits through `start_agents`.

## Answers, round 1

staff-reviewer's review round 1 (PR conversation comment, no inline review comments) had one finding.

| Comment | Answer |
| :------ | :----- |
| Finding 1: `lib/openlanes/execution/child.rb` below 95% in CI run 1208 (94.52%) | fix |

**Fix.** The uncovered lines were the `rescue` branches of `Child` (`wait` on `ECHILD`, `kill` on `ESRCH`/`EPERM`, `alive?` on `ESRCH`, `group?` on `ESRCH`/`EPERM`, `terminate` called a second time). The real-process specs reach them only when a process group empties at the right moment, so the figure moved between machines (94.52% on CI, 95.89% here). `spec/openlanes/execution/child_spawner_spec.rb` now raises each errno on purpose, against a `Child` built on a pid that was never started, so the figure no longer depends on timing. No library code changed.

- `bundle exec rspec spec/openlanes/execution/child_spawner_spec.rb spec/openlanes/execution/child_spec.rb`: 11 examples, 0 failures; `child.rb` at 98.63% from these two files alone
- `bundle exec rubocop`: 544 files inspected, no offenses detected, exit 0
- `bundle exec rspec`: 4045 examples, 0 failures, 9 pending, coverage 98.84%, exit 0
- `bin/coverage-changed --base origin/main`: `100.00%  lib/openlanes/execution/child.rb`, then `coverage-changed: 36 file(s), all at or above 95%`, exit 0
