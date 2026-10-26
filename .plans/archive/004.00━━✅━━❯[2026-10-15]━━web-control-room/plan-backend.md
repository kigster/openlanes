# Plan 004.00, back end (`backend-coder`)

The feature exists. Every unit here is evidence, packaging or drift repair. Fix production code only where a new test proves it wrong, and only inside the files the unit lists. Routes, payloads and the SSE shape are the ones in `contract.md` and `web/src/api/types.ts`; none of these units changes them.

Real-Redis specs carry the existing `:redis` tag and read `OPENLANES_TEST_REDIS_URL` (as `spec/openlanes/live/store_spec.rb:11` does), each on its own database number so they never share keys with the store examples on `/15`.

## B1 Naming and `web/dist` build order

- **Discipline:** back end.
- **Owns:** `.plans/004.00-*/contract.md` (in the plan folder, not the snapshot), `README.md`, `.gitignore`, `justfile`, `openlanes.gemspec`, `spec/openlanes/packaging_spec.rb`.
- **Must not touch:** `.circleci/config.yml` (B5), anything under `web/` (F1–F3), `spec/integration/**` (B2–B4).
- **Depends on:** nothing.
- **Work:**
  - `contract.md`: `tilda` → `openlanes`, `4747` → `11000`, `.tilda.yml` → `.openlanes.yml`, `agentilda:` → `openlanes:`.
  - `.gitignore`: add `/web/dist`.
  - `justfile`: `build` already depends on `web-build`; make `publish` and any other `gem build` path go through it too.
  - `openlanes.gemspec`: keep the abort when `web/dist/index.html` is missing; its message names `just web-build`.
- **Done when:** `spec/openlanes/packaging_spec.rb` passes. It asserts `.gitignore` lists `/web/dist`; every justfile recipe that runs `gem build` depends on `web-build`; loading the gemspec without `web/dist/index.html` aborts with that message; and `README.md` names `openlanes`, `11000`, `.openlanes.yml` and `openlanes:` with no `tilda`, `4747` or `agentilda:` in it.

## B2 Process harness and the integration check

- **Discipline:** back end.
- **Owns:** `spec/support/control_room_process.rb`, `spec/integration/control_room_spec.rb`.
- **Must not touch:** `lib/**`; files owned by B1, B3, B4, B5.
- **Depends on:** B1 (the spec needs a built `web/dist`; it skips with a message naming `just web-build` when absent, never fails silently into a pass).
- **Work:** `ControlRoomProcess` spawns `exe/openlanes run --no-open --port <free> --redis-url <url>` (and `--no-web` / `openlanes web` for one side only), in a temp repository built with `PlansFixture`. Methods, no more: `start_engine`, `start_server`, `kill(:engine | :server, signal: "KILL")`, `wait_until(deadline:) { }`, `get(path)`, `post(path, json)`, `sse(path) { |event| }`, `stop_all`. Polls with a deadline, never `sleep`. Flushes its Redis database in `after`.
- **Integration check:** a real request through engine, Redis and API server into what the page reads, nothing stubbed. `control_room_spec.rb` must show:
  1. `GET /` returns the built `web/dist/index.html`.
  2. The SSE stream delivers a board snapshot that lists the fixture's plans.
  3. A change in the engine (a plan's folder moves state) reaches the SSE stream within one second, measured.
  4. A command (`hold`) posted twice with one command id is applied once, and its reply arrives on the stream.
- **Done when:** `spec/integration/control_room_spec.rb` passes against a real Redis.

## B3 Restart evidence

- **Discipline:** back end.
- **Owns:** `spec/integration/restart_spec.rb`; fixes, if the spec proves them needed, in `lib/openlanes/live/run_state.rb`, `lib/openlanes/live/commands.rb`, `lib/openlanes/web/server.rb`, `lib/openlanes/web/events.rb`.
- **Must not touch:** `spec/support/control_room_process.rb` (B2; ask through mail for a harness change); files owned by B4.
- **Depends on:** B2.
- **Done when:** `spec/integration/restart_spec.rb` passes. With both processes up and a command pending: `kill -9` the API server, restart it, and the SSE client reconnects and sees the same board and the same pending command; then `kill -9` the engine, restart it, and the board, pending command and run state from `.plans/openlanes-state.json` are intact and the command is applied once.

## B4 Two-checkout evidence

- **Discipline:** back end.
- **Owns:** `spec/integration/two_checkouts_spec.rb`; fixes, if the spec proves them needed, in `lib/openlanes/live/claims.rb`, `lib/openlanes/live/node.rb`, `lib/openlanes/live/snapshot.rb`, `lib/openlanes/engine/dispatcher.rb`.
- **Must not touch:** `spec/support/control_room_process.rb` (B2); files owned by B3.
- **Depends on:** B2. Runs beside B3: no shared file.
- **Done when:** `spec/integration/two_checkouts_spec.rb` passes. Two clones of one fixture repository, two engines, one Redis: each snapshot lists the other node as a peer marked read-only, a command addressed to the peer's plan is refused, and across the run no plan is ever claimed by both nodes (asserted from the claims keys, polled, plus each engine's run record).

## B5 CI: build order, drift check, coverage of changed code

- **Discipline:** back end.
- **Owns:** `.circleci/config.yml`, `bin/coverage-changed`, `spec/openlanes/coverage_changed_spec.rb`.
- **Must not touch:** `web/**` (F3 owns the Vitest side), files owned by B1–B4.
- **Depends on:** B1 (recipe names), F3 (the npm script CI calls), B2–B4 (CI must run `spec/integration` with Redis up).
- **Work:**
  - The `test` job runs `spec/integration` against its Redis service.
  - Packaging runs `just web-build` before `gem build`, and lists `web/dist/index.html` inside the built `.gem`.
  - A step runs `rg -n "tilda|4747|agentilda:"` over `README.md`, `lib/`, `web/src/` and fails on a hit (the demo RNG seed in `demo_board.rb` is excluded by path).
  - `bin/coverage-changed` reads `coverage/.resultset.json`, takes files from `git diff --name-only origin/main...HEAD -- lib/`, prints each file's line coverage and exits non-zero below 95%. CI runs it after rspec, and runs F3's `npm run coverage:changed` in the `web` job.
- **Done when:** `spec/openlanes/coverage_changed_spec.rb` passes (a fixture resultset and a fixture file list: one file under 95% exits 1 and names it, all at or above exits 0, no changed files exits 0), and `circleci config validate` accepts the config.
