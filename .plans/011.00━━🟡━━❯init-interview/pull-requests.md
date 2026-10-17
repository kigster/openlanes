# Pull Requests

## Build, round 1 (luke-backend)

No front end in this plan (`## Frontend` has no units), so luke-backend built every unit, U1 to U8.

Baseline before any change: `bundle exec rspec` → 3013 examples, 0 failures, 9 pending.

Integration proof (U8), the real `exe/openlanes` as a subprocess in temp folders, both API keys removed, nothing stubbed:

```
$ bundle exec rspec spec/openlanes/cli/init_integration_spec.rb
2 examples, 0 failures
```

Full checks after the last unit:

```
$ bundle exec rspec
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected
```

The repo has no separate end-to-end suite for terminal commands; the integration spec above is it.

Re-verified after the harness died, round 1 resumed (2026-10-15), no code changed:

```
$ bundle exec rspec
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected

$ bundle exec rspec spec/openlanes/setup spec/openlanes/cli/init_spec.rb spec/openlanes/cli/init_integration_spec.rb spec/openlanes/config_spec.rb
146 examples, 0 failures
```

Re-verified again after a further harness death (2026-10-15, 10:0x), no code changed:

```
$ bundle exec rspec
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected
```

Re-verified after the harness flagged a push (2026-10-16), no code changed. The flagged ref, `origin/kig/collapse-agent-transcript`, was pushed at 2026-10-15 20:04 from the separate `openlanes.worktrees/collapse-agent-transcript` checkout, which shares `refs/remotes` with this worktree; this plan's branch was not pushed and `HEAD` is still `ce65c43`.

```
$ bundle exec rspec
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected

$ bundle exec rspec spec/openlanes/cli/init_integration_spec.rb
2 examples, 0 failures
```

Publish was refused on 2026-10-16 because `plan.md` had no `## How to test` section. Added it. Every step was run by hand against `exe/openlanes` in temp folders, with both API keys unset, and each one holds: the Rails folder gets its `.openlanes.yml`, `stack.md` and `ci.yml`; `--reconfigure -n` shows the diff and writes nothing; `--reconfigure -y` writes `high` and leaves `ci.yml` byte-identical; the mixed Ruby and Go folder gets no `stack:`; `--merge-by agent` exits 1. No code changed.

```
$ bundle exec rspec
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected
```
