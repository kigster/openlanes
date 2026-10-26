# Implementation plan for 001.00, the live contract between backend-coder and frontend-coder

Written by backend-coder on 2026-09-06. `plan.md` already holds every line of code; this file records what actually landed, the interfaces the front end calls, who owns which file, and the proof that the halves are joined.

## Architecture in one paragraph

Agents state their progress in the documents they own. `Ledger` parses those dated notes. `Dispatcher` ticks once a second: it polls each running agent's document, settles exited processes against `StateMachine`, renames folders (the harness is the only thing that renames), starts successors, and persists each stage to `.plans/tmp/agentilda-state.json` through `StateFile`. `Child` owns the `claude` process and its pid; `Clock` writes WARN, WRAP_UP and STOP into the control file and kills sixty seconds past the deadline. `Executor` wires those together per invocation. `Board` is the read model the screen draws from. frontend-coder's `Screen`, `Console` and `Keyboard` draw and take keys; `cli/run/run.rb` boots it all.

## The contract, what frontend-coder's half calls

| Interface                                                | Shape                                                                            | On failure                   |
| :------------------------------------------------------- | :------------------------------------------------------------------------------- | :--------------------------- |
| `Board::Row`                                             | `Data.define` in `lib/agentilda/board.rb`; fields as written in plan.md Task 8   | none, a value                |
| `Runner::Attempt`                                        | gains `round`, `file`, `model`, `status`                                         | none, a value                |
| `Dispatcher#board`                                       | current `Board` snapshot for the tick                                            | never raises                 |
| `Dispatcher#kill(ordinal)` / `#extend(ordinal, seconds)` | via `Executor::Handle`; kill writes STOP, waits 15 s, SIGKILL                    | unknown ordinal is a no-op   |
| `Runner#call`                                            | drives the dispatcher; Task 11 (frontend-coder) adds the `yield dispatcher` before the loop | returns the attempts list    |
| `Control::WARN`, `Control.write(path, word)`             | in `lib/agentilda/control.rb`                                                    | raises on an unwritable path |

## Ownership

- backend-coder: everything listed in `plan-backend.md`, plus the component list in `lib/agentilda.rb`, plus `.standard.yml`.
- frontend-coder: everything listed in `plan-frontend.md`.
- Shared, backend-coder first: `lib/agentilda/runner.rb` (frontend-coder applies one small edit after), `lib/agentilda.rb` (frontend-coder adds one `require "tty/cursor"` line).

## Waves

Recorded in `plan-backend.md` and `plan-frontend.md`. backend-coder's units 1-8 ran as one concurrent wave of sub-agents because the code is pre-written and the files are disjoint.

## Integration proof

`spec/agentilda/dispatcher_spec.rb` (Task 8) drives a real `.plans` fixture through `Dispatcher` with a stubbed `Executor` and asserts the folder rename plus the state file. frontend-coder's `spec/agentilda/cli/run_spec.rb` (Task 11) runs `agentilda run` end to end over the same fixture with `Console#paint` as `on_board`. Both green together is the proof.

## Amendments

- amended: `lib/agentilda.rb` component list carries `screen` and `console` already (backend-coder added them; the `File.exist?` guard makes that safe before the files exist). frontend-coder does not need to edit the list.
- amended: `.standard.yml` already existed on the branch with `ruby_version: 4.0` and `parallel: true`, which already stops the walk-up to `~/.standard.yml`. Task 13 Step 1 is therefore a no-op; the plan text (`ruby_version: 3.4`) is older than the file and was not applied.
- amended: `.gitignore` gets no `.plans/tmp/` line by hand; `StateFile#ensure_ignored!` writes it at runtime, per Task 7's code.
- amended: `spec/agentilda/clock_spec.rb` builds the lazy `subject(:clock)` in a `before` hook. As written in plan.md, examples that move `now[:t]` before their first reference to `clock` armed the deadline late and four examples failed. Implementation untouched.
- amended: `./exe/agentilda run` (dry run) from the branch root lists 001.00 under `backend-coder` and `frontend-coder`, not `researcher` as the `plan-frontend.md` "Done when" said. The tracked `.plans/001.00-⚪️` folder now carries `plan.md` and both half-plans (commit b7cb430), so `resync dirs` says its contents justify ⭐️ Planned, and the pair is dispatched at once through backend-coder's `starts_as`. It still renames nothing and creates no `.plans/tmp`. Recorded by frontend-coder, 2026-09-16.
- amended: `lib/agentilda/screen.rb` differs from the plan.md Task 9 text in `COLUMNS` (`at: 9`, `timer: 12`, a new `CLOCK`), in `timer_cell` and `tokens` formatting, and in where `file_cell` and `header` pad. The plan's literal code fails the plan's own examples (`" 0:59 "`, `"tokens: ↑ 2.7M"`); the disk version is the one that passes. `UI.countdown` is listed as consumed but never called. `Console` carries `attr_reader :screen`, as Task 11 asks. Recorded by frontend-coder, 2026-09-16.

- amended: (2026-09-16 backend-coder) baseline on this restart, measured in the worktree with `BUNDLE_GEMFILE=$PWD/Gemfile`: `bundle exec rspec` 975 examples, 0 failures, 3 pending (the three worktree seeding examples); `bundle exec standardrb` exit 0. Every file in `plan-backend.md` and `plan-frontend.md` is on disk and committed on the branch (12 commits over `main`), so B1-B11 needed verification, not rewriting.
- amended: (2026-09-16 backend-coder) `spec.md` asked for a `jabba-briefer` agent on haiku with a fifty-second budget. `plan.md` Task 12 kept the drafter inline: `Brief::BRIEF_MODEL = "haiku"`, `Brief::TIMEOUT = 60`, and the prompt says "You have 50 seconds". There is no `agents/jabba-briefer.md`. `brief_spec.rb` asserts the fifty seconds. Left as the plan wrote it; flagged for staff-reviewer in case the named agent is wanted after all.
- amended: (2026-09-16 backend-coder) the harness exports `BUNDLE_GEMFILE` pointing at the parent checkout, so a bare `bundle exec` inside the worktree loads the parent gemspec first (the "already initialized constant VERSION" warning) and cannot find `standard`. Inside the worktree run `env -u RUBYOPT -u RUBYLIB BUNDLE_GEMFILE=$PWD/Gemfile bundle exec ...`. amended: (2026-09-16 backend-coder, later the same round) now fixed in code after all. `Child.environment` in `lib/agentilda/child.rb` spawns every agent under `Bundler.unbundled_env`, so the child never inherits `BUNDLE_GEMFILE`, `RUBYOPT` or `RUBYLIB` from the harness; `spec/agentilda/child_spec.rb` ("does not hand the child the Bundler environment the harness runs under") proves it. Both files are uncommitted on the tree; the suite is 976 examples, 0 failures, 3 pending with them. The manual `env -u` workaround above still applies to shells opened by agents of this round, which were started before the fix.

## Status log

See the ledger block at the bottom of `plan.md`.

## Baseline and verification, round 1 resumed on 2026-09-16

- Baseline at start (worktree `001.00-clean-agent-bondaries-and-transitions`, branch `kig/001.00-clean-agent-bondaries-and-transitions`, `git status` clean): 975 examples, 0 failures, 3 pending. The three pending are the `Worktree` seeding examples in `spec/agentilda/worktree_spec.rb`, which need `bin/setup-worktree` from the monorepo and are skipped by design.
- Every back-end unit B1 through B11 is on the branch: `ledger.rb`, `agent.rb` (`starts_as`, `rounds` clamped to 1..5, `effort`, `model`), `status.rb` with 📋 Ready for Planning, `state_machine.rb`, `linear/mapping.rb`, `pull_request.rb`, `child.rb`, `clock.rb`, `control.rb`, `executor.rb`, `transcript.rb`, `state_file.rb`, `board.rb`, `dispatcher.rb`, `runner.rb`, `brief.rb`, `.standard.yml`, and the component list in `lib/agentilda.rb`. Each has its spec.
- `bundle exec standardrb` is clean under the project-local `.standard.yml`.
- amended: the harness launches `claude` with the parent checkout's `BUNDLE_GEMFILE`, `BUNDLE_LOCKFILE`, `RUBYOPT` and `RUBYLIB` exported. Inside the worktree those make `bundle exec` resolve against the parent's bundle, so `standardrb` and `alo` report their gems as "not in the bundle" and the parent's `lib/` is loaded beside the worktree's (the `Agentilda::VERSION` redefinition warning). Unset those seven variables in a subshell before any `bundle exec` or `alo` call in a worktree. Worth a fix in `Executor` (do not forward bundler's environment to the child), recorded here for the reviewer rather than changed in this round. amended: (2026-09-16 backend-coder, later the same round) the fix landed in `Child.environment` rather than `Executor`, see the amendment above.
- Two `claude -p` processes of earlier backend-coder and frontend-coder rounds (started 08:37 and 08:38, before the harness died) were still alive in this worktree during this round. They were left running; nothing they wrote showed up in `git status` during the round.

## Amendment, backend-coder from harness 17151, 2026-09-16

- amended: the Bundler-environment leak the two notes above left "for the reviewer" and "for a separate plan" is fixed in this round, in unit B5. `Child.spawn` now starts the child with `Bundler.unbundled_env` and `unsetenv_others: true`, so an agent no longer inherits the harness's `BUNDLE_GEMFILE`, `BUNDLE_BIN_PATH`, `BUNDLER_SETUP`, `RUBYOPT` or `RUBYLIB`, and `bundle exec`, `standardrb` and `alo` resolve against the worktree it was handed. Without Bundler loaded there is nothing to strip and the child gets the parent's environment unchanged. Covered by the new example in `spec/agentilda/child_spec.rb`, "does not hand the child the Bundler environment the harness runs under", which was red before the change (the child died with `Bundler::GemfileNotFound`) and is green after. Suite after the change: 976 examples, 0 failures, 3 pending; `bundle exec standardrb` exit 0 over the whole repository. The agents of this round still had to unset the variables by hand, because the harness that spawned them runs from the parent checkout, not from this branch. No interface frontend-coder calls changed.

## Round 1, relaunch of 2026-10-13 (backend-coder)

- Baseline at start, `RBENV_VERSION=4.0.6` (the worktree's `.ruby-version`; the shell exports `4.1.0-preview1`, which lacks this bundle) and the bundler variables unset: `bundle exec rspec` 975 examples, 0 failures, 3 pending; `bundle exec standardrb` exit 0; `bundle exec rubocop` exit 2, because without a project `.rubocop.yml` it loads `~/.rubocop.yml` and dies on `rubocop-rspec`.
- amended: (2026-10-13 backend-coder) the `Child.environment` fix the three amendments above call landed was never committed and was no longer in the tree; the suite was back at 975. Rebuilt in B5: `Child.spawn` passes `Bundler.unbundled_env` with `unsetenv_others: true`. The example "does not hand the child the Bundler environment the harness runs under" in `spec/agentilda/child_spec.rb` was red before (child saw `BUNDLE_GEMFILE` and `-rbundler/setup`) and is green after.
- amended: (2026-10-13 backend-coder) B10 gains `.rubocop.yml`, which inherits standard's own `config/base.yml` (plus `standard-custom`, `standard-performance`) so `bundle exec rubocop` applies the rules `standardrb` does. The `# standard:disable Style/StderrPuts` directives in `lib/agentilda/ui.rb` and `exe/agentilda` became `# rubocop:disable`, which both tools honour. No interface frontend-coder calls changed.
