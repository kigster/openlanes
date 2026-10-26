# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 23 | [\[008.00\](A) Plan Dependencies](https://github.com/kigster/openlanes/pull/23) | Merged 🟣 |

## Integration proof (backend-coder, last of the pair, 2026-10-13)

The repo has no separate end-to-end suite. The integration proof spawns the real `exe/openlanes` against a `PlansFixture` tree with nothing stubbed.

```
$ RBENV_VERSION=4.0.6 bundle exec rspec spec/openlanes/integration/plan_dependencies_spec.rb
3 examples, 0 failures

$ RBENV_VERSION=4.0.6 bundle exec rspec
2248 examples, 0 failures        (baseline: 2214 examples, 0 failures)

$ RBENV_VERSION=4.0.6 bundle exec rubocop
304 files inspected, no offenses detected
```

What the integration spec asserts, under `NO_COLOR=1`:

- `list-plans`: the 034 row reads `blocks 050.00`; `034.00/spec.md` is byte-identical before and after.
- `run --dry-run --isolation shared`: 034 is assigned (`would invoke`), 050 is not, and the report prints `050.00 waiting on 034.00`.
- With 034 and 050 depending on each other: nothing is assigned, and the report prints `034.00 cycle: 034.00 → 050.00 → 034.00` and `050.00 cycle: 050.00 → 034.00 → 050.00`.

Note: running the suite rewrites `docs/badges/coverage_badge.svg` (the spec helper does this), so the file shows as modified in the worktree.
