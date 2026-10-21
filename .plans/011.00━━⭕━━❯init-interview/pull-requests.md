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

Re-verified after the harness flagged a push (2026-10-16, 18:28), no code changed. Both flagged refs were pushed from the separate `openlanes.worktrees/transpose-last-known-table` checkout, which shares `refs/remotes` with this one: `origin/kig/transpose-last-known-table` at 18:22:53 (`76e8833`, that worktree's HEAD) and `origin/main` at 18:28:19 (`7186635`). This plan's `HEAD` is still `ce65c43`.

The first full run hit `Errno::EADDRINUSE` on port 11103 in three `spec/openlanes/apps/runner_spec.rb` examples, a fixed fixture port another checkout's suite was holding at the time. That file then passed twice alone (9 examples, 0 failures), and the full rerun is clean:

```
$ bundle exec rspec        # ANTHROPIC_API_KEY and OPENAI_API_KEY unset
3107 examples, 0 failures, 9 pending

$ bundle exec rubocop
440 files inspected, no offenses detected

$ bundle exec rspec spec/openlanes/cli/init_integration_spec.rb
2 examples, 0 failures
```

## Build, round 2 (luke-backend)

No code changed under `lib/` or `spec/`. Added `.openlanes.coverage.yml` (M15). This branch's base predates the `coverage:` section in `.openlanes.yml`: its `Config::KEYS` does not include `coverage`, so adding that section would make `Config.load` refuse the file. The gate on this base reads `.openlanes.coverage.yml`:

```
command: bundle exec rspec
report: coverage/.resultset.json
format: simplecov
minimum: 95
```

The gate's figure, read with `Coverage::Simplecov.parse` over the resultset: 98.14% against a minimum of 95. When the branch is rebased onto `origin/main`, this should move into `.openlanes.yml` as `coverage:` with the same four values.

Checks, run outside the sandbox with both API keys unset:

```
$ bundle exec rspec
3107 examples, 30 failures, 9 pending    # all in spec/openlanes/apps/** and spec/openlanes/cli/app_spec.rb

$ bundle exec rspec --exclude-pattern "spec/openlanes/{apps/**/*,cli/app}_spec.rb"
2995 examples, 0 failures, 9 pending

$ bundle exec rspec spec/openlanes/setup spec/openlanes/config_spec.rb spec/openlanes/cli/init_spec.rb spec/openlanes/cli/init_integration_spec.rb
146 examples, 0 failures

$ bundle exec rubocop
440 files inspected, no offenses detected
```

The 30 failures come from the host, not this plan. `Socket.tcp("127.0.0.1", <closed port>, connect_timeout: 0.2)` connects on Darwin 27 with Ruby 4.0.6, while plain `Socket.tcp` and `TCPSocket.new` get `ECONNREFUSED`. Blocked (technical): see `blocked.md` B1.

## Build, round 3 (luke-backend)

B1 was answered a): the probe fix landed on `origin/main` as `ff03ca48` (PR #72). This branch is still at `ce65c43` and does not have it. No code changed.

```
$ bundle exec rspec        # this branch, ANTHROPIC_API_KEY and OPENAI_API_KEY unset
3107 examples, 30 failures, 9 pending    # the same spec/openlanes/apps/** and cli/app_spec.rb examples

$ bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb    # a detached origin/main checkout, same host
115 examples, 0 failures
```

The suite goes green here only once the branch is rebased onto `origin/main`, which I cannot do. Blocked (technical): see `blocked.md` B2.
