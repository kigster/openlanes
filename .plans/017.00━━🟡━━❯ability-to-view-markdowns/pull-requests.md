# Pull Requests

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
