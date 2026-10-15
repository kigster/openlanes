# Web Control Room

## Problem statement

`openlanes run` opens a browser page that shows the whole run live and lets a person steer it: the board of plans moving through the stations, the agents working on each, what they cost, what they are asking, and every control a person needs to answer, redirect, pause, compact, switch or stop them. Several machines sharing one Redis see each other's work read-only and never take the same plan.

The page replaces the terminal UI, which is gone (#55, W22). It is the only interactive view; a headless view keeps runs working without a browser (W2). What it looks like and how each control behaves is settled in `design/design.md` and `design/control-room.html`; the decisions behind it are W1–W30 in `docs/decisions/decisions-on-web-ui-and-review-labels.md`. This spec says what has to exist and how we know it works.

Research shows the feature is largely built: the page, engine, Redis seam, commands and CI exist, and rspec (2214 examples), rubocop, `npm run lint`, typecheck and Vitest pass. What remains is naming drift between the draft and the code, a build-order hazard for `web/dist`, and missing evidence for three acceptance criteria. This spec is therefore written as a **close-out**: it states what exists, corrects the draft to match the code, and names the work still owed.

## Framings considered

1. **Greenfield feature.** Spec every element as work to build. Rejected: it would plan work that `lib/openlanes/live/`, `lib/openlanes/web/` and `web/src/` already contain.
1. **Close-out of a built feature.** Reconcile the draft with the code, then close the evidence gaps. **Chosen:** the research (Observed runs, Answers by Done-when item) shows each criterion either met with a `file:line` or unproven, and the unproven ones are test work, not design work.

## Goal

After this ships, a person runs `openlanes run` in a repository with plans and gets one browser page on `127.0.0.1:11000` that shows every plan, agent, cost and question live, and carries every control to steer them. The claim "kill either process and lose nothing; two machines never take the same plan" is backed by automated tests rather than by reading code. Before, those three properties (restart, keyboard-only use, two real processes on one Redis) held in the design and in unit specs but were never exercised end to end.

## Non-Goals

- Authentication or remote exposure: the server binds to localhost and trusts its machine (W29).
- Linear integration, review labels (plan 005) and plain `NNN` numbering (W21): their own plans.
- Redesigning the page: the mockup `design/control-room.html` and `design/design.md` are settled.
- Reviving the terminal UI (#55, W22).
- Peer machines being controllable: peers are read-only by design (W26).
- Persisting history beyond what Redis streams and `.plans/openlanes-state.json` already hold.

## In scope

Each item names its check. Items marked **exists** are met per the research; the plan only keeps them green.

1. **Engine and API server as two processes over Redis** (W6, W7, W13). **Exists.** Check: `openlanes run` starts both; `--no-web` starts the engine only; `--no-open`, `--port`, `--redis-url` are accepted (`README.md:283`, `README.md:334`).
1. **Redis seam with an in-memory fake**, keys `openlanes:<repo>` (`lib/openlanes/live/keys.rb:7`). **Exists.** Check: Ruby specs run with no Redis server.
1. **Node identity and plan claims** (W26): `SET NX EX`, compare-and-delete (`lib/openlanes/live/claims.rb:1-25`), dispatcher steps around held plans (`lib/openlanes/engine/dispatcher.rb:341`, `:398`). **Exists.** Check: `claims_spec.rb`, `chat_spec.rb`.
1. **All 15 commands**, idempotent by command id (`lib/openlanes/live/commands.rb:34-48`, `:130`). **Exists.** Check: `commands_spec.rb`, `command_spec.rb`.
1. **The page**, every element of the mockup, built into `web/dist` and shipped in the gem. **Exists.** Check: Vitest at 98.46% statements; Cypress flows `actions.cy.ts`, `needs-you.cy.ts`, `board.cy.ts`.
1. **Port `11000`** by default (W-note at decisions doc line 50; `lib/openlanes/web/server.rb:12`). Check: README, server and `vite.config.ts` agree; no `4747` outside the demo seed.
1. **Copilot panel backed by c3po-operator** (W17): `Live::Copilot::Operator` outside demo (`lib/openlanes/web/context.rb:38`), canned reply in demo (`web/demo.rb:24`). **Exists.** Check: its specs stay green. The draft called it a placeholder; the code ships it.
1. **Autocompact at 40%** (W28) and yes/no prompts (W30). Check: specs on the executor argv and the agent prompts.
1. **Draft corrected to the code**: `contract.md` uses `openlanes`, port `11000`, `.openlanes.yml`, prefix `openlanes:`. Check: `rg -n "tilda|4747|agentilda:" .plans/004.00*/contract.md .plans/004.00*/spec.md` finds only historical mentions in `## Research`.
1. **`web/dist` build order.** Not tracked and not gitignored (`openlanes.gemspec:31-47` aborts without it). Check: add `/web/dist` to `.gitignore`; `just` build target and CI build it before `gem build`; a fresh clone running `gem build` after `just web-build` succeeds.
1. **Restart evidence.** Check: an automated test starts engine and API server against a real Redis, kills each in turn, restarts, and asserts the board and pending commands are intact and the SSE client reconnects.
1. **Two-checkout evidence.** Check: an automated test runs two engines (two checkouts, one Redis) and asserts each shows the other as a read-only tab and no plan is run by both.
1. **Keyboard-only evidence.** Check: a Cypress spec drives answer, hold blocked, stop all local with confirm and the Action menu with the keyboard only, no pointer events.
1. **Per-new-code coverage reported.** Check: CI prints Ruby coverage for files changed against `main`, and the gate is at least 95% for them.

## Out of scope

| Item | Reason |
| --- | --- |
| Authentication | Localhost-only, W29 |
| Linear export, review labels | Plans 005 and the Linear work own them |
| Plain `NNN` numbering | W21, own plan |
| Cypress against real agents | Needs paid model calls; the demo engine covers the UI contract |
| A TUI fallback | Removed on purpose, W22 |

## Back end / front end

`luke-backend` and `rey-frontend` build these as a pair; the contract is `web/src/api/types.ts` and `contract.md`.

| Item | Back end (`luke-backend`) | Front end (`rey-frontend`) |
| --- | --- | --- |
| Draft corrected to code | `contract.md`, `README` check | spec wording only |
| `web/dist` build order | `.gitignore`, `justfile`, CI, gemspec | `npm run build` output path |
| Restart evidence | Ruby/integration test, process kill harness | Reconnect banner asserted ("reconnecting") |
| Two-checkout evidence | two-engine test, claims, peer tab data in `Snapshot` | read-only peer tab asserted in page |
| Keyboard-only evidence | none | Cypress spec, focus-order fixes found by it |
| Per-new-code coverage | SimpleCov diff step in CI | Vitest diff step in CI |

## Done when

- [ ] `openlanes run` starts the engine and API server, prints the URL, opens the browser (unless `--no-open` or no display), and `--no-web` runs headless. Met per research; keep green.
- [ ] The board updates within a second of a change in the engine, over SSE, and a reloaded or reconnected page shows the same state. SSE exists; add a test that measures the delay.
- [ ] Every command reaches the engine, is applied once even if delivered twice, and its reply shows on the page. Met.
- [ ] Killing the API server or the engine mid-run loses nothing: each picks up from Redis and the page reconnects by itself. **Owed:** restart test.
- [ ] Two engines on two checkouts against one Redis each show the other read-only, and neither takes a plan the other has claimed. **Owed:** two-process test.
- [ ] The page passes axe with no serious violations in both themes (met), works by keyboard alone (**owed**), and respects `prefers-reduced-motion` (`web/src/index.css:12`).
- [ ] Ruby: `just lint` and `just test` green; line coverage of changed code at least 95%.
- [ ] Front end: `npm run lint`, `npm run typecheck`, Vitest green, statements at least 95%; Cypress runs the flows (answer, hold blocked, add existing plan, stop all local with confirm, switch model) against `openlanes web --demo`, in CI.
- [ ] CircleCI builds the front end, runs Vitest and Cypress, and the gem package contains `web/dist`; `web/dist` is gitignored and built before packaging.
- [ ] Spec, contract and README name the same binary, port, config file and Redis prefix.

## How to verify

1. `redis-server` running, then `openlanes run` in a repository with plans. The browser opens on the board at `127.0.0.1:11000`.
1. Answer a blocked agent's question from Needs you; the row moves on and the transcript shows the answer.
1. Start a second checkout of the same repository with `openlanes run`; each page shows the other machine's tab, read-only.
1. `kill -9` the API server; the page shows "reconnecting", then catches up when the server is restarted. Repeat for the engine.

## Open questions

Answered from the code or the decisions document, so they do not block:

- **Port.** `11000`, per the decisions doc (line 50) and `lib/openlanes/web/server.rb:12`; `4747` is retired.
- **Redis prefix.** `openlanes:`, per `lib/openlanes/live/keys.rb:7` and W13/W26; `contract.md` is corrected.
- **Binary and config file.** `openlanes` (aliases `depot`, `lanes`) and `.openlanes.yml`; `tilda` appears in no code.
- **Copilot.** In: W17 settles that it exists and the code ships it; this spec's earlier "Out" was stale.
- **`web/dist`.** Built in CI and by `just` before packaging, never committed (the gemspec's own abort message and the justfile comment say it is a build product).

Still assumed, for the owner to confirm; none stops planning:

1. Restart and two-checkout evidence is automated, not manual. If a real-Redis integration test is too heavy for CI, accept manual verification and say so in Done when.
1. "Within a second" is measured on the demo engine on a developer machine, not on CI hardware.
1. Per-new-code coverage means files changed against `main`, not the whole library.
1. `leah-researcher`'s round was interrupted ("harness died"); the Research chapter is complete but its figures (2214 examples, 98.46%) are from one run on 2026-10-13. Cypress and `npm run build` were not run.

## Risks to planning or execution

- **Process-kill tests are flaky by nature.** Mitigation: poll with a deadline, not sleeps; run against a throwaway Redis database.
- **No Redis in CI sandbox.** The `e2e` job already uses a real Redis (`.circleci/config.yml:114`); the new tests reuse it.
- **Cypress and the build were not run by research.** The first real run may fail for reasons unrelated to this plan; budget one fix cycle.
- **Keyboard-only test may expose focus-trap bugs in Radix dialogs**, widening front-end work.
- **Naming drift can return.** Docs and code were edited by different plans; the `rg` check in In scope item 9 should run in CI.

## Conclusion

When this ships, `openlanes run` serves a tested control room on `127.0.0.1:11000`, backed by Redis and shipped inside the gem with a build order that cannot silently produce an empty package. The draft, contract and README agree with the code. Restart recovery, two-machine claim exclusion and keyboard-only operation are each covered by an automated test, and CI reports coverage of the changed code.

> [!NOTE]
>
> [2026-10-13 07:04:16 PM PDT] [ agent: leah-researcher   status: **Interrupted, round 1 (harness died)** ]

## Research

Input gap: this spec has no `## What research needs to settle` list. I answered the questions the **Done when** list implies. Yoda, confirm they are the right ones.

Evidence: repo at `openlanes.worktrees/004.00-web-control-room`, clean, on `kig/004.00-web-control-room`. Runs on 2026-10-13, Ruby 4.0.6, Node from `web/`.

### Observed runs

- `bundle exec rspec`: 2214 examples, 0 failures; SimpleCov line coverage 98.63% (whole library, not new code only).
- `bundle exec rubocop`: 301 files, no offenses.
- `npm run lint`, `npm run typecheck`: exit 0.
- `npm run coverage` (Vitest): statements 98.46%, lines 99.71%, branches 94.18%.
- Not run: Cypress (`CYPRESS_INSTALL_BINARY=0`, no binary), `npm run build`.

### Answers, by Done-when item

- **`tilda run` starts engine and API server, prints URL, opens browser, `--no-web` headless.** Binary is `openlanes` (`exe/openlanes`; aliases `depot`, `lanes`). `openlanes run` serves the page when Redis answers, takes `--no-web`, `--no-open`, `--port`, `--redis-url` (`README.md:283`, `README.md:334`). `tilda` appears in no code. Met under the name `openlanes`.
- **Board updates within a second over SSE; reconnect shows same state.** SSE and reconnect exist: `web/src/api/events.ts`, `web/src/api/useBoard.ts`, `web/src/api/events.test.ts`. Not measured end to end.
- **Every command reaches the engine, applied once.** All 15 kinds in the spec are dispatched at `lib/openlanes/live/commands.rb:34-48`. Idempotency: a command id already in `done` gets its first reply (`commands.rb:130`). Ruby coverage: `commands_spec.rb`, `command_spec.rb`.
- **Kill API server or engine, lose nothing.** Run state is mirrored to `.plans/openlanes-state.json` (`lib/openlanes/live/run_state.rb:10`). No test kills and restarts either process. Unsettled.
- **Two checkouts, read-only peers, no shared claim.** Claims are `SET NX EX`, compare-and-delete (`lib/openlanes/live/claims.rb:1-25`). The dispatcher steps around plans another node holds (`lib/openlanes/engine/dispatcher.rb:341`, `:398`). Covered by `claims_spec.rb`, `chat_spec.rb` with two hubs on one Redis. No two-process test.
- **Axe, keyboard, reduced motion, both themes.** Axe runs in both themes: `web/cypress/e2e/board.cy.ts:21-23`, and `chat.cy.ts` imports axe. `prefers-reduced-motion` is in `web/src/index.css:12` and in several CSS and TS files. No keyboard-only test found. Unsettled.
- **Ruby `just lint` and `just test` green, coverage ≥ 95%.** Lint and rspec pass (above). The 95% figure is whole-library; per-new-code coverage was not measured.
- **Front end lint, typecheck, Vitest green, coverage ≥ 95% statements.** Met (above, 98.46%).
- **Cypress flows on a fake engine, in CI.** All five flows exist: `actions.cy.ts:7` (add existing plan), `:15` (stop all local, confirm), `:23` (cancel), `:30` (switch model); `needs-you.cy.ts:5` (answer), `:14` (yes/no one click), `:22` (hold blocked). They run against `openlanes web --demo` (`justfile:61`, `web/cypress.config.ts:7`). CI `e2e` job in `.circleci/config.yml`. Not run here.
- **CircleCI builds front end, Vitest, Cypress; gem contains `web/dist`.** `.circleci/config.yml` has `linter`, `test`, `web`, `e2e` jobs. The gemspec globs `web/dist/**/*` and aborts if `web/dist/index.html` is missing (`openlanes.gemspec:31-47`). `web/dist` is absent from this checkout and `.gitignore` does not list it, so a fresh build fails until `npm run build` runs first.

### Contradictions: draft vs code (production runs the code)

| Topic | Spec / contract says | Code runs |
| --- | --- | --- |
| Binary | `tilda run`, `bin/tilda`, `tilda web` | `openlanes`, `exe/openlanes`; no `tilda` anywhere |
| Port | `127.0.0.1:4747` (spec, `contract.md`) | `11000` (`lib/openlanes/web/server.rb:12`, `cli/web/web.rb:30`, `vite.config.ts:9`, `README.md:283`). `4747` is only a demo RNG seed (`demo_board.rb:40`) |
| Config file | `.tilda.yml` `redis_url:` | `.openlanes.yml` (`skills/openlanes/SKILL.md:44`) |
| Redis keys | `agentilda:<repo>` (`contract.md`) | `openlanes:<repo>` (`lib/openlanes/live/keys.rb:7,18,127`), matching W13 and W26 |
| Copilot | "wired to nothing but a placeholder" (Scope, Out) | `Live::Copilot::Operator` runs c3po-operator outside demo (`lib/openlanes/web/context.rb:38`, `lib/openlanes/live/copilot/operator.rb:30`); `agents/c3po-operator.md` exists. Demo answers with a canned line (`web/demo.rb:24`) |

### Open questions for yoda

1. Is the copilot in plan 004? The spec says out; the code ships it. Owner decides.
2. Port: spec says 4747, code says 11000. Recommend 11000, since the code and README agree.
3. Redis prefix: `openlanes:` in code and W13/W26; `contract.md` says `agentilda:`. Recommend `openlanes:` and fix `contract.md`.
4. `web/dist` is not gitignored and not in the checkout. Is it committed, or built in CI before packaging? Owner decides; CI and gemspec both assume it exists.
5. No automated check for keyboard-only operation, kill-and-restart of either process, or the two-checkout case end to end. Add tests, or accept manual verification and say so in Done when.
6. Per-new-code coverage: the 95% gate measures whole libraries today. Decide whether to measure the diff.

### Findings, Conclusion & References

The spec is mostly built: the page, engine, Redis seam, commands and CI exist and pass locally. What is missing is evidence for the restart, keyboard and two-machine criteria, and the contradictions above need fixing before yoda writes the spec. No web sources were used; everything is from this repository, its test output and `docs/decisions/decisions-on-web-ui-and-review-labels.md`.
