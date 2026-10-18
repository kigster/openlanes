# Pull Requests

## Verification, luke-backend, round 1

Integration proof:

```text
$ bundle exec rspec spec/integration/runtime_state_spec.rb
4 examples, 0 failures
```

Full suite and lint:

```text
$ bundle exec rspec
3148 examples, 0 failures, 9 pending
$ bundle exec rubocop
438 files inspected, no offenses detected
```

End-to-end suite:

```text
$ just web-build && just web-e2e
All specs passed!  00:21  23 tests, 23 passing, 0 failing
```

## Verification, luke-backend, round 1 (resumed 2026-10-17)

`web/dist` is built now, so `spec/integration/restart_spec.rb` runs instead of skipping. It read `.plans/openlanes-state.json` and failed. Fixed: it reads `OpenLanes::Runtime.state_file(root:)`.

```text
$ bundle exec rspec spec/integration/restart_spec.rb
2 examples, 0 failures
$ bundle exec rspec
30 failures, all in spec/openlanes/apps/ and spec/openlanes/cli/app_spec.rb
$ bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb   # clean HEAD 0d0d99c, detached worktree
112 examples, 30 failures
$ bundle exec rubocop
438 files inspected, no offenses detected
```

Those 30 are environmental: a connect to a closed localhost port succeeds on this machine (see blocked.md B1).

## Verification, rey-frontend, round 1

F1 (reporter) and F2 (web board) are in the tree. Tests: `reporter_spec.rb` (🔑 for state-dir and legacy lock, "held on" for foreign only), `model.test.ts` and `Board.test.tsx` (no lock, local, foreign).

```text
$ cd web && npx vitest run
Test Files  34 passed (34)   Tests  358 passed (358)
$ cd web && npx tsc --noEmit
(no output)
$ bundle exec rubocop
438 files inspected, no offenses detected
$ bundle exec rspec
3148 examples, 30 failures
```

The 30 failures are all in `spec/openlanes/apps/*` and `cli/app_spec.rb`, files this plan does not touch. In this sandbox a TCP probe of a closed port reports ready (`probe_spec.rb:42`), which breaks the port-registry specs. Luke's run of the same suite elsewhere was 0 failures.
