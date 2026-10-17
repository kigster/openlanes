# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 79 | [\[017.00\](A) Ability to View Markdowns](https://github.com/kigster/openlanes/pull/79) | Open 🟡 |

## Integration proof, luke-backend, round 1 (2026-10-15)

```bash
bundle exec rspec        # 3046 examples, 0 failures, 9 pending (baseline: 3013, 0 failures, 9 pending)
bundle exec rubocop      # 427 files inspected, no offenses detected
just web-build           # ✓ built (web/dist was absent; without it every page is 503 UNBUILT)
just web-e2e             # All specs passed! 25/25 — actions 5, board 6, chat 4, keyboard 5, needs-you 3, plan-files 2
```

`plan-files.cy.ts` ran against `openlanes web --demo --dir <temp copy of web/cypress/fixtures/plans>`, nothing stubbed. `git status` afterwards shows the fixture tree unchanged.

## rey-frontend integration proof (round 1)

- `cd web && npx vitest run` → 37 files, 378 tests passed; `npm run lint` and `npm run typecheck` clean.
- `bundle exec rspec` → 0 failures; `bundle exec rubocop` → no offenses.
- `just web-e2e` → 25/25 passed, `plan-files.cy.ts` 2/2.
- Two count assertions (`StatusBar.test.tsx`, `App.test.tsx`) moved from 2 to 3 blocked, because the 002.00 carless fixture was added to `board.json`.

## Integration proof re-run, luke-backend, round 1 (2026-10-16)

The previous round was flagged for a push to `origin/kig/collapse-agent-transcript`, a branch this plan never touches; worktrees share `refs/remotes`, so that ref moved under another session. Nothing was pushed from here. Re-verified on the same tree:

```bash
bundle exec rspec        # 3046 examples, 0 failures
bundle exec rubocop      # 427 files inspected, no offenses detected
just web-e2e             # All specs passed! 25/25, plan-files.cy.ts 2/2
```

## Re-verification, luke-backend, round 1 (2026-10-16, second pass)

Full runs here flaked while another session's `rspec` ran on the same machine:

- `spec/openlanes/apps/supervisor_spec.rb:122` (`--silent` fixture "answered"): every suite scanned app ports up from 11100, so a concurrent suite's server took the same port. Fixed, test-only: `spec/support/port_window.rb` gives each suite process its own 100-port window of 11100..11999 (by pid), used by the `Ports` registries in `apps/supervisor_spec.rb`, `apps/restart_spec.rb`, `apps/runner_spec.rb`. `spec/openlanes/apps` then 101/101 green, three runs in a row.
- `spec/integration/restart_spec.rb:43,63` (Redis event within 10 s) failed once under the same load and passed on the run before it. Not touched by this plan; left for a human, not chased.

```bash
bundle exec rspec        # 3046 examples, 0 failures (exit 0); the next run: 2 failures, the restart_spec pair above
bundle exec rubocop      # 428 files inspected, no offenses detected
```

## Final integration proof, luke-backend, round 1 (2026-10-16, after rey's done mail #10)

The previous pass was flagged for pushes to `origin/kig/transpose-last-known-table` and `origin/main`. This plan touches neither, and nothing was pushed from here. Worktrees share `refs/remotes`, so those refs moved under other sessions.

```bash
bundle exec rspec                                   # 3046 examples, 0 failures (exit 0), with another session's rspec running at the same time
bundle exec rspec spec/integration/restart_spec.rb  # 2 examples, 0 failures, twice in a row
bundle exec rubocop                                 # 428 files inspected, no offenses detected
just web-e2e                                        # 3 of 6 failed: "Port 11100 is taken", ECONNREFUSED; another session held the default port
E2E_PORT=11870 E2E_PEER_PORT=11871 just web-e2e     # All specs passed! 25/25, plan-files.cy.ts 2/2
```

`git status` afterwards shows the `web/cypress/fixtures/plans` tree unchanged. When several sessions share the machine, `just web-e2e` needs free ports set through `E2E_PORT` and `E2E_PEER_PORT`. The script already prints that advice when it finds a port taken.

## Front-end proof, rey-frontend, round 1 (2026-10-16)

```bash
cd web && npx vitest run     # 37 files, 378 tests passed
cd web && npm run lint       # clean
cd web && npx tsc --noEmit   # clean
E2E_PORT=11880 E2E_PEER_PORT=11881 just web-e2e   # All specs passed! 25/25, plan-files.cy.ts 2/2
```

## Final integration proof, luke-backend, round 1 (2026-10-17)

The previous pass was flagged for pushes to `origin/kig/keep-tests-on-local-redis` and `origin/main`. This plan touches neither, and nothing was pushed from here; worktrees share `refs/remotes`.

On this machine, now macOS 27.0.1, Ruby 4.0.6's `Socket.tcp(..., connect_timeout:)` returns a socket for a refused connect, with SO_ERROR set to ECONNREFUSED, so closed ports read as listening: 26 failures in `spec/openlanes/apps`. Fixed: `Apps::Probe.listening?` now calls `remote_address` on the socket, which raises on such a socket. `Ports#answering?` and the `connectable?` helpers in `apps/supervisor_spec.rb` and `cli/app_spec.rb` go through it, and `spec/fixtures/apps/servers/server.rb` makes the same check.

```bash
bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb  # 112 examples, 0 failures (26 failures before the fix)
bundle exec rspec        # 3046 examples, 0 failures (exit 0); the run before it: 1 failure, spec/integration/restart_spec.rb:43, passing alone twice in a row
bundle exec rubocop      # 428 files inspected, no offenses detected
E2E_PORT=11890 E2E_PEER_PORT=11891 just web-e2e   # All specs passed! 25/25, plan-files.cy.ts 2/2
```

## Front-end proof, rey-frontend, round 1 (2026-10-17)

```bash
cd web && npx vitest run   # 37 files, 378 tests passed
cd web && npm run lint     # clean
cd web && npm run typecheck # clean
E2E_PORT=11900 E2E_PEER_PORT=11901 just web-e2e   # All specs passed! 25/25, plan-files.cy.ts 2/2
```

## Changes Requested, luke-backend, round 1 (2026-10-17)

hansolo's three findings are all in `web/src/panels/PlanFilePopup.tsx`, rey-frontend's half; none names the back end. Finding 3's cause, from CircleCI job 833:

```bash
npm run coverage:changed   # step "Coverage of changed files": FAIL 93.8% 45/48 src/panels/PlanFilePopup.tsx, under 95%; every other changed file ok
```

Mailed to rey (#18). Back end re-verified on the rebased tree, no code changed:

```bash
bundle exec rspec     # 3577 examples, 0 failures (exit 0)
bundle exec rubocop   # 487 files inspected, no offenses detected
```

## Review round 1 fixes, rey-frontend (2026-10-17)

- Finding 1: closing (Close, Esc, click outside) over a changed draft now asks "You have unsaved changes. Save them before closing?" with Yes (save, then close; a refused save keeps the popup open) and No (discard). Tests in `PlanFilePopup.test.tsx`.
- Finding 2: the edit button reads "Save Changes"; tests find it by that name.
- Finding 3: the red `ci/circleci: web` step was `npm run coverage:changed`: `PlanFilePopup.tsx` was at 93.8%, under the 95% floor. Reproduced locally; the new tests lift it to 95.2%.

```bash
cd web && npm run lint && npm run typecheck      # clean
cd web && npm run coverage                       # 39 files, 419 tests passed
cd web && npm run coverage:changed               # every changed file ok; PlanFilePopup.tsx 95.2%
cd web && npm run build                          # built
bundle exec rubocop                              # 487 files, no offenses
bundle exec rspec                                # 3577 examples, 0 failures
E2E_PORT=11910 E2E_PEER_PORT=11911 just web-e2e  # All specs passed! 25/25, plan-files.cy.ts 2/2
```
