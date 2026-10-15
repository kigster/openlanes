# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 38 | [\[012.00\] App Runner and Preview](https://github.com/kigster/openlanes/pull/38) | Merged 🟣 |

## Round 1 rejection fixes (luke-backend, 2026-10-15)

Correction to the 2026-10-14 claim below: it quoted only the whole-library figure. CI's changed-file gate failed on that head: `start.rb` 92.16%, `stop.rb` 90.48% (`ci/circleci: test`), `useApps.ts` 75.0% (`ci/circleci: web`). PR #38 was merged into `main` (8165d25) at 2026-10-15T15:56Z with those two jobs red.

What the uncovered lines were, and the specs now in `spec/openlanes/cli/app_spec.rb` that run them (in process):

- `start.rb` `definition_in` rescue: a plan worktree whose own `.openlanes.yml` has an unreadable `app:` while the root's is sound, exit 65.
- `start.rb` `board` with Redis answering, `--demo` filing under `demo/<repo>`, the supervisor's output lambda, and the TERM trap raising the runner's stop flag.
- `stop.rb` `Errno::ESRCH` (owner gone between registry read and TERM, staged) and `Errno::EPERM` (pid 1, exit 77).
- `useApps.ts`: rey-frontend, `skipToken` in place of the dead `queryFn`, plus `useApps.test.tsx`.

```
$ bundle exec rspec
2348 examples, 0 failures
Coverage: 98.65%

$ bundle exec rubocop
330 files inspected, no offenses detected

$ ruby bin/coverage-changed --files <PR #38's lib/ files>   # main's script; this branch predates it
100.00%  lib/openlanes/cli/app/subcommands/start.rb
100.00%  lib/openlanes/cli/app/subcommands/status.rb
100.00%  lib/openlanes/cli/app/subcommands/stop.rb
 95.00%  lib/openlanes/apps/watcher.rb      (lowest of the 21)
coverage-changed: 21 file(s), all at or above 95%
```

Not yet published: see `blocked.md` B1.

## Verification (luke-backend and rey-frontend, 2026-10-14)

```
$ just lint
330 files inspected, no offenses detected

$ just test
2344 examples, 0 failures        (baseline: 2214 examples, 0 failures)
Coverage: 98.57%

$ cd web && npx vitest run && npx eslint . && npm run typecheck
Test Files  30 passed (30)
     Tests  316 passed (316)
(eslint and tsc clean)

$ just web-build && just preview-e2e      # openlanes web --demo on 11050, Redis db 13
  ✓ starts the API before the web page, shows the web page labelled with plan, branch and port, and restarts only the API
  ✓ opens an app that refuses framing in a window of its own
  2 passing

$ npx cypress run --config baseUrl=http://127.0.0.1:11051   # the existing demo suite, against this branch's build
  16 passing (actions, board, chat, needs-you)
```

What the Cypress run proves, with nothing intercepted (a real `openlanes app start --demo` on `spec/fixtures/apps/preview_project`):

- The web process found the API answering when it started (`#sibling` reads `answered <port>`), so processes start in declared order, each once the previous is ready.
- The Preview tab is labelled `▶ 012 · <branch> · :<port>` and frames `http://127.0.0.1:<port>/`; the framed page reports that same port.
- Touching `api/handler.rb` shows `◐ restarting` then `● running`, and the framed web process keeps its pid: only the API restarted.
- An app sending `X-Frame-Options: DENY` gets no iframe, and its button calls `window.open(url, "_blank", "noopener")`.

Manual: `openlanes app start` / `status` / `stop` on the fixture project; `stop` ends the runner cleanly (it once died with "can't be called from trap context", fixed in 9a415c8).

Note: `just test` rewrites `docs/badges/coverage_badge.svg`; it was reverted before each commit.
