# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 39 | [\[009\] Plan aging and bombs](https://github.com/kigster/openlanes/pull/39) | Merged 🟣 |
| 44 | [\[009.00\] Plan Aging and Bombs (salvage of #39)](https://github.com/kigster/openlanes/pull/44) | Merged 🟣 |

#39 merged into its stacked base `kig/008.00-plan-dependencies` after #23 had already merged, so none of it reached `main`. #44 carries the same commits onto `main`.

## Verification (backend-coder, last of the pair, 2026-10-15)

Stacked on #23. The integration proof spawns the real `exe/openlanes` against a `PlansFixture` tree, with `claude`, `codex` and `pi` on PATH replaced by scripts that fail if called, and drives the control-room app over HTTP.

```
$ just lint
308 files inspected, no offenses detected

$ PATH=<guard stubs>:$PATH REDIS_URL=redis://127.0.0.1:1 just test
2310 examples, 0 failures        (baseline, #23 alone: 2248 examples, 0 failures)

$ bundle exec rspec spec/openlanes/integration/plan_aging_spec.rb
1 example, 0 failures

$ cd web && npm run lint && npm run typecheck && npm test
eslint: clean; tsc: clean; 28 test files, 300 tests passed
```

What the integration spec asserts:

1. `run --isolation shared --no-web` over two plans blocked 8 days, each with a dependent: exit 1, STDERR names `001.00 Feed` and `003.00 Ports`, both folders are 💣, no agent CLI ran.
2. `snapshot.bombs` lists both with their `blocked.md`.
3. `POST /api/commands` `respond` writes `## A1` into 001's `blocked.md`.
4. The dispatcher drains 001 (unblocker handles 💣); 001 leaves 💣 and `snapshot.bombs`, while 003 still halts the run.
5. `POST /api/commands` `resume_anyway` on 003 lifts the halt for 24 h, with no `.openlanes.yml` edit.

## Front end re-check (frontend-coder, 2026-10-15, after staff-reviewer's red-CI finding)

The only finding is the CircleCI `test` job (Ruby suite, not the web half). `web` and `e2e` pass in CI. Re-run on the 009 branch tip `94a3c4e`; nothing in the front end changed:

```
$ bundle exec rspec
2310 examples, 0 failures
$ bundle exec rubocop
308 files inspected, no offenses detected
$ cd web && npm run lint && npm run typecheck && npm test
eslint: clean; tsc: clean; 28 test files, 300 tests passed
```

The `test` failure on #44's head `a6e0c27` does not reproduce here, and I cannot read CircleCI job 409's log from this sandbox. It sits outside the front end; the failing example needs the job log.

## Front end re-check, round 2 (frontend-coder, 2026-10-15)

No front-end file changed; staff-reviewer's only finding is the CircleCI `test` job (Ruby suite). Not reproducible locally and job 409's log is unreachable from this sandbox. Working tree adds four examples to `spec/openlanes/lifecycle/aging_spec.rb` (uncommitted, for the harness to commit):

```
$ bundle exec rspec
2314 examples, 0 failures
$ bundle exec rubocop
308 files inspected, no offenses detected
```

Needed from a human: the failing example from CircleCI job 409.

## CI fix (backend-coder, 2026-10-15, after staff-reviewer's red-CI finding)

CircleCI job 409 failed in the `Coverage of changed files` step, not in rspec: `bin/coverage-changed --base origin/main` reported `lib/openlanes/lifecycle/aging.rb` at 90.91%, below its 95% floor. The uncovered lines were three fallbacks: an unparseable signature time (falls back to `blocked.md`'s mtime), a 💣 the machine refuses, and a deferral the machine refuses (the sweep removes the `delayed.md` it wrote, and keeps one that was there before). `spec/openlanes/lifecycle/aging_spec.rb` now covers all three, on real files; only the state machine is stubbed in the refused-deferral case.

```
$ bundle exec rspec
2314 examples, 0 failures
aging.rb: 66 / 66 lines covered (100%)

$ bundle exec rubocop
308 files inspected, no offenses detected
```

#44 is already merged into `main`, and the branch is 198 commits behind it, so this spec change needs a fresh pull request against `main`, not a push to the merged branch. On `main` the deferred state's emoji is 💤 rather than ☢️; the new spec names ☢️ only in a `context` string, so it applies there with the same behaviour.
