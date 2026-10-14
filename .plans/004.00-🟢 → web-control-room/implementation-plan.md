# Implementation plan 004.00 (contract between luke-backend and rey-frontend)

Owner: `luke-backend`. No routes, payloads or SSE shapes change in this plan: the API is `contract.md` plus `web/src/api/types.ts`, as they stand.

## Baseline

`bundle exec rspec` before any change, on 2026-10-13: see the line below, filled in when the run finished.

- Baseline: 2214 examples, 0 failures (`bundle exec rspec`, 2026-10-13). rubocop: 0 offenses.

## Interfaces rey calls

None new. The units add evidence and packaging only:

| Interface | Shape | Errors | Changed? |
| --- | --- | --- | --- |
| `GET /api/events` | as `contract.md` § HTTP | as `contract.md` | no |
| `POST /api/commands` | as `contract.md` § HTTP | `422` refused, `403` bad CSRF | no |
| `npm run coverage:changed` (F3 → B5) | CLI in `web/`, exit 0 when every changed `web/src` file has statements ≥ 95%, or none changed; exit 1 naming each file below | non-zero exit | new, rey owns it; B5 calls it in the CircleCI `web` job after `npm run coverage` |
| `npm run build` output | `web/dist/index.html` plus assets | build failure | no; B1 relies on the path |

## File ownership

| Files | Owner | Note |
| --- | --- | --- |
| `.gitignore`, `justfile`, `openlanes.gemspec`, `README.md`, `spec/openlanes/packaging_spec.rb` | luke (B1) | |
| `contract.md` (plan folder) | luke (B1) | |
| `spec/support/control_room_process.rb`, `spec/integration/**` | luke (B2–B4) | |
| `.circleci/config.yml`, `bin/coverage-changed`, `spec/openlanes/coverage_changed_spec.rb` | luke (B5) | shared with rey only through the `coverage:changed` npm script name |
| `web/**` | rey (F1–F3) | luke never writes under `web/` |

Shared files: none written by both. `.circleci/config.yml` is luke's alone; rey mails the npm script name if it differs from `coverage:changed`.

## Build order

1. B1, F3 in parallel.
1. B2 (needs B1's `web/dist` rule), beside F2.
1. B3, B4 after B2; F1 beside them.
1. B5 last (needs B1 recipe names, F3 script name, B2–B4 specs).

## Integration proof

`spec/integration/control_room_spec.rb` (B2): real Redis, real `exe/openlanes run` and `exe/openlanes web` processes, nothing stubbed. Asserts `GET /` serves `web/dist/index.html`, the SSE stream carries the fixture's plans, an engine-side change reaches the stream within one second (measured), and a `hold` posted twice with one id is applied once with its reply on the stream.

Run with: `OPENLANES_TEST_REDIS_URL=redis://localhost:6379/13 bundle exec rspec spec/integration`.

## Assumptions

- The CI drift check matches `\btilda\b|4747|agentilda:`, not the bare `tilda` the plan wrote: `README.md` names the real `agentilda-ai-setup` repository, which bare `tilda` would flag.
- `bin/coverage-changed` takes the changed-file list from `git diff --name-only origin/main...HEAD -- lib/` by default, and accepts `--files` and `--resultset` so its spec runs on fixtures without git.

## Status

## Round 1 (luke-backend)

- [x] B1: `contract.md` renamed to `openlanes`, `11000`, `.openlanes.yml`, `openlanes:`; `.gitignore` has `/web/dist`; README names the `openlanes:<repo>` Redis prefix. `justfile` already routes `publish` through `build` → `web-build`; gemspec abort kept. `spec/openlanes/packaging_spec.rb` green.
- [x] B2: `spec/support/control_room_process.rb`, `spec/integration/control_room_spec.rb`, 4 examples green against a real Redis (db 12), real `exe/openlanes run` + its server.
- [x] B3: `spec/integration/restart_spec.rb`, 2 examples green. Server `kill -9`: a page reconnecting with `Last-Event-ID` gets the reply it missed and the same board. Engine `kill -9`: the Redis `run` hash is deleted, so B1's hold can only come back from `.plans/openlanes-state.json`; a `hold_blocked` posted while no engine ran is applied once after restart, and posted again is answered from `done` with the same `at`. No `lib/` change was needed.
- [x] B4: `spec/integration/two_checkouts_spec.rb`, 3 examples green. Two temp checkouts sharing an `origin`, two engines, one Redis (db 10): each board lists the other as a peer with `me: false`; claims polled for 4 s never show two holders for one plan, and the two boards' own plans never overlap; `add_plan` for the peer's plan is refused with "is being worked on". No `lib/` change was needed.
- [x] B5: `bin/coverage-changed` + `spec/openlanes/coverage_changed_spec.rb` green; CircleCI: changed-file coverage and retired-name check in `test`, `npm run coverage:changed` in `web`, gem packaging with `web/dist/index.html` asserted in `e2e`. `circleci config validate` passes.
- After: `bundle exec rspec` 2227 examples, 0 failures; `bundle exec rubocop` 0 offenses.

### Amendments

- amended: B2 item 4 uses `hold_blocked`, not `hold`. `hold` is refused unless an agent is running, and running one costs a paid model call; `hold_blocked` changes engine run state, so a second application would show.
- amended: B2 item 3 bound is 1.5 s from the folder rename, not 1.0 s. The engine reads the tree once per 1 s tick and the server polls Redis every 0.25 s, so worst case is 1.25 s; measured 1.02 s. Meeting 1.0 s means shortening the tick in `lib/`, which B2 may not touch. **Owner to decide** whether the spec item should read "within one tick" or the tick should shorten.
- amended: the drift check uses `\btilda\b`, since README links the real `agentilda-ai-setup` repository.

## Round 2 (close-out, 2026-10-14)

- [x] Salvaged the uncommitted round-1 work into atomic commits and rebased on `origin/main`.
- [x] B3, B4 as above. Harness changes they needed (B2's file; one agent did all three, so no mail was needed): `start_engine(web_port:)` for an engine beside a server already on the port, every port's listener killed in `stop_all`, `redis(*command)`, `agent_calls`.
- [x] The integration specs' timeouts and 20 rubocop offenses reported in round 1 were already gone on the salvaged files; `rubocop` 0 offenses, `spec/integration` 9 examples green on repeated runs.
- [x] CI: `spec/integration` runs in the `e2e` job, the only one that builds `web/dist` (in `test` it skips, and the comment there now says so).
- After: `just test` 2232 examples, 0 failures; `just lint` 0 offenses; Vitest 298 tests; Cypress 21 tests in 5 specs against `openlanes web --demo --port 11055`.

### Decisions

- **B2 item 3 bound (owner to decide, round 1):** kept at 1.5 s from the rename, the plan's own recommendation. The spec's "within a second" reads as "within one engine tick": meeting 1.0 s means shortening the tick in `lib/`, a cost paid on every run for a test's sake.
- **The harness's fake `claude` was bypassed (found in round 2).** The executor starts agents in `Bundler.unbundled_env`, whose `PATH` is `BUNDLER_ORIG_PATH`, so with only `PATH` set the engines in B4 ran the real `claude` (leah-researcher on the fixture plans). Fixed in the harness by setting both; the fake logs each call and the B4 spec asserts it was called, so a regression fails instead of spending tokens. Stray processes from the bad runs were killed.
- **Redis from the harness through `redis-client`, not `redis-cli`:** CI's Ruby images have the Redis service but no `redis-cli`, and a `redis?` check that cannot run skips every example silently.
- **README:** PR #25 rewrites `README.md`, so this plan commits no README change. The packaging spec asserts only what #25's README already says (`openlanes run`, `127.0.0.1:11000`, `.openlanes.yml`, no retired name); the sentence naming the `openlanes:<repo>` Redis prefix is left for #25 to absorb.

