# Pull Requests

No pull request yet; the harness opens it once both halves sign.

## Back-end verification, round 1 (backend-coder, 2026-09-16)

Run from the plan worktree with the bundler variables unset (see the amendment in `implementation-plan.md`):

    bundle exec rspec        975 examples, 0 failures, 3 pending (worktree seeding, skipped by design)
    bundle exec standardrb   clean
    git status --short       nothing uncommitted beyond the plan documents

frontend-coder's mailbox held no message at the time of signing, so the integration proof and the end-to-end run are frontend-coder's to record when frontend-coder signs last.


## Back-end verification, backend-coder, round 1 resumed on 2026-09-16

Every unit in `plan-backend.md` (B1-B11) is on disk and already committed on the branch, so this round verified rather than rewrote. Run inside the worktree with `env -u RUBYOPT -u RUBYLIB BUNDLE_GEMFILE=$PWD/Gemfile`:

| Command                   | Result                                                       |
| :------------------------ | :----------------------------------------------------------- |
| `bundle exec rspec`       | 975 examples, 0 failures, 3 pending (worktree seeding), 96.96% |
| `bundle exec standardrb`  | exit 0, no offenses                                          |
| `git status --short`      | clean at 08:38; see the note below                           |

The integration proof named in `implementation-plan.md` (`spec/agentilda/dispatcher_spec.rb` and `spec/agentilda/cli/run_spec.rb`) is green inside that run.

Notes for staff-reviewer:

- The harness was relaunched five times between 08:38 and 08:43 from the parent checkout (branch `kig/salvage-ratatui-tui-dashboard`, not this branch), and each launch left its backend-coder and frontend-coder pair alive. At 08:45 a concurrent backend-coder was adding a test to `spec/agentilda/child_spec.rb` asserting `Child.spawn` strips `BUNDLE_GEMFILE` and `RUBYOPT`; the figures above were measured before that edit. If `lib/agentilda/child.rb` did not follow, that one example is red and is that sibling's, not the branch's.
- `spec.md` asked for a `jabba-briefer` agent; `plan.md` Task 12 kept the haiku, fifty-second drafter inline in `Brief`. See the amendment in `implementation-plan.md`.
- `alo` prints nothing and exits 0 in this environment, so no lock was ever held. Every write this round was append-only.




## Front-end verification, frontend-coder, round 2 on 2026-09-16

Every unit in `plan-frontend.md` (F1-F4) is on disk and committed on the branch, so this round verified rather than rewrote. Run inside the worktree with `RUBYOPT`, `RUBYLIB`, `BUNDLE_BIN_PATH` and `BUNDLER_SETUP` unset and `BUNDLE_GEMFILE=$PWD/Gemfile`:

| Command                                                                                                                                  | Result                                                        |
| :--------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------ |
| `bundle exec rspec`                                                                                                                      | 975 examples, 0 failures, 3 pending (worktree seeding), 96.86% |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` (the integration proof)                             | 55 examples, 0 failures                                       |
| `bundle exec rspec spec/agentilda/{screen,console,keyboard,tally}_spec.rb spec/agentilda/cli/run_spec.rb`                                | 77 examples, 0 failures                                       |
| `bundle exec standardrb` on F1-F3's lib and spec files plus `runner.rb`                                                                 | exit 0, no offenses                                           |
| `./exe/agentilda docs -o /tmp/x.md` then `diff /tmp/x.md docs/WORKFLOW.md`                                                             | identical, 299 lines (F4)                                     |
| `./exe/agentilda run` from the branch root, dry run (the end-to-end run; this repo has no browser suite)                                  | 2 invocations, 0 advanced; lists 001.00 under `backend-coder` and `frontend-coder`; `.plans/` unchanged, no `.plans/tmp` |
| `./exe/agentilda resync dirs` (dry run)                                                                                                  | `001.00-⚪️ → 001.00-⭐️`, "contents now justify Planned"; nothing renamed |

Which test proves which acceptance criterion:

- F1, the screen draws a board: `spec/agentilda/screen_spec.rb`.
- F2, the keys select, kill, extend, wrap up and quit: `spec/agentilda/keyboard_spec.rb` ("the console keys") and `spec/agentilda/console_spec.rb`.
- F3, `agentilda run` drives the dispatcher, exits non-zero on a failed attempt and zero when the folder moves: `spec/agentilda/cli/run_spec.rb` ("exits zero when the agent signs Completed and the folder moves", "adds .plans/tmp/ to .gitignore once and says so"); invocation counts: `spec/agentilda/tally_spec.rb`.
- F4, the conventions document is derived: `docs/WORKFLOW.md` equals `agentilda docs` output byte for byte.

Notes for staff-reviewer:

- `plan-frontend.md` "Done when" expected `run` to list 001.00 under `researcher`; that held while the tracked folder had only `spec.md`. Since b7cb430 recorded `plan.md` and both half-plans into it, the contents justify ⭐️ Planned and the pair starts at once. The line and `implementation-plan.md` are amended; the code was not touched.
- `lib/agentilda/screen.rb` diverges from the plan.md Task 9 text in column widths and two formatting helpers; the plan's literal code fails the plan's own examples, and the disk version passes. Recorded as an amendment.
- Three harness launches (pids 14595, 17151, 22310) ran a frontend-coder each against this plan at once. This section is from the 17151 frontend-coder. Every write this round was an append or a one-line edit under an `alo` lock taken from the parent checkout (`alo` needs `RUBYOPT` and `BUNDLE_GEMFILE` unset to load, and refuses paths outside its tree, so it must run from the parent checkout for `.plans`).

Final run before signing, with a sibling backend-coder's uncommitted `lib/agentilda/child.rb` and `spec/agentilda/child_spec.rb` edit in the tree (`Child.spawn` strips `BUNDLE_GEMFILE` and `RUBYOPT`; not a front-end file): `bundle exec rspec` 976 examples, 0 failures, 3 pending.



## Back-end verification, backend-coder (harness 36367), final measurement, 2026-09-16

frontend-coder signed Completed at 08:47:29, so this backend-coder is last. Measured after a sibling backend-coder landed the `Child.environment` change (`lib/agentilda/child.rb` and `spec/agentilda/child_spec.rb`, uncommitted on the tree, both back-end files). Run inside the worktree with `BUNDLE_GEMFILE=$PWD/Gemfile`:

| Command                                                                            | Result                                                 |
| :--------------------------------------------------------------------------------- | :----------------------------------------------------- |
| `bundle exec rspec`                                                                | 976 examples, 0 failures, 3 pending (worktree seeding) |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` | 55 examples, 0 failures (the integration proof)        |
| `bundle exec standardrb`                                                           | exit 0, no offenses                                    |
| `git status --short`                                                               | only `child.rb` and `child_spec.rb` modified          |

The end-to-end dry run of `./exe/agentilda run` is recorded in frontend-coder's section above and was not repeated. The `implementation-plan.md` amendment that said the bundler leak was "not fixed in code" is corrected in place: it is fixed, in `Child.environment`.


## Back-end verification and integration proof, backend-coder from harness 17151, round 1 on 2026-09-16

This is the backend-coder the live harness (pid 17151) started; the sections above are from its orphaned predecessors. frontend-coder's mailbox message 3 says the front end is done, so this backend-coder is last and ran the proof. Every unit in `plan-backend.md` was already on the branch; this round adds one code change in unit B5, the Bundler-environment fix described below. Commands ran inside the worktree with `BUNDLE_GEMFILE=$PWD/Gemfile` and `RUBYOPT`, `RUBYLIB`, `BUNDLE_BIN_PATH`, `BUNDLER_SETUP` unset:

| Command                                                                                          | Result                                                                                        |
| :----------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------- |
| `bundle exec rspec`                                                                              | 976 examples, 0 failures, 3 pending (worktree seeding, skipped by design), coverage 96.86%    |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` (the proof) | 55 examples, 0 failures                                                                       |
| `bundle exec rspec spec/agentilda/child_spec.rb`                                                 | 4 examples, 0 failures; the new example was red before `child.rb` changed                     |
| `bundle exec standardrb` (whole repository)                                                      | exit 0, no offenses                                                                           |
| `./exe/agentilda run` from the branch root, dry run (this repo has no browser suite)             | exit 0; `.plans/001.00-⚪️--…` unchanged, nothing renamed, no `.plans/tmp` created              |
| `git status --short`                                                                             | `M lib/agentilda/child.rb`, `M spec/agentilda/child_spec.rb`, nothing else                    |

The change, for staff-reviewer:

- `Child.spawn` starts the child with `Bundler.unbundled_env` and `unsetenv_others: true`. Every earlier note in this file and in `implementation-plan.md` about unsetting `BUNDLE_GEMFILE`, `RUBYOPT` and `RUBYLIB` by hand describes the bug this fixes: the harness's own Bundler variables leaked into each agent, so `bundle exec`, `standardrb` and `alo` inside a worktree resolved against the parent checkout and reported gems "not currently included in the bundle". The agents of this round still saw the leak because the harness that spawned them runs the parent branch's code. The plan is "clean agent boundaries"; this is one of them.
- No interface frontend-coder calls changed. No file frontend-coder owns changed.

## Front-end verification, frontend-coder (harness pid 36367), round 1 on 2026-09-16

Independent re-measurement by a second frontend-coder launched at 08:42; it concurs with the 17151 frontend-coder's section above. F1-F4 were already on disk and committed, so nothing was rebuilt and no source file was touched. Run inside the worktree in a subshell with `RUBYOPT`, `RUBYLIB`, `BUNDLER_SETUP`, `BUNDLE_BIN_PATH`, `BUNDLER_VERSION` and `BUNDLE_LOCKFILE` unset and `BUNDLE_GEMFILE=$PWD/Gemfile` (note: `env -u` prints nothing in this sandbox shell, so use `unset` in a subshell):

| Command                                                                                                   | Result                                                                                                  |
| :-------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------ |
| `bundle exec rspec`                                                                                       | 976 examples, 0 failures, 3 pending (worktree seeding), no VERSION warning                              |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` (integration proof)  | 55 examples, 0 failures                                                                                 |
| `bundle exec rspec spec/agentilda/{screen,console,keyboard,tally}_spec.rb spec/agentilda/cli/run_spec.rb` | 77 examples, 0 failures                                                                                 |
| `just lint` (`bundle exec standardrb`, whole repo)                                                        | exit 0, no offenses                                                                                     |
| `./exe/agentilda docs -o /tmp/frontend-coder-docs.md && diff /tmp/frontend-coder-docs.md docs/WORKFLOW.md`                       | identical, 299 lines (F4)                                                                               |
| `./exe/agentilda run` from the branch root, dry run (the end-to-end run; no browser suite in this repo)   | 2 invocations, 0 advanced; 001.00 under `backend-coder` and `frontend-coder`; `.plans/` unchanged, no `.plans/tmp` |
| `./exe/agentilda resync dirs` (dry run)                                                                   | `001.00-⚪️ → 001.00-⭐️`, "contents now justify Planned"; nothing renamed                                 |
| `git rev-parse --short HEAD` before and after                                                             | `030518c` both times; 12 commits over `main`                                                            |
| `git status --short`                                                                                      | only a sibling backend-coder's uncommitted `lib/agentilda/child.rb` and `spec/agentilda/child_spec.rb`; included in the suite figure above |

Locks for this section were taken from the parent checkout as `frontend-coder-36367` and released after writing. Mailbox message #5 to backend-coder names the test behind each criterion.


The dry run's own words, from `./exe/agentilda run` at 08:49 with the Bundler variables unset in a subshell (`env -u` swallows all output in this sandbox, which is also why `alo` looked silent; no lock was ever held, so every write this round was an append):

    Dry run — no agent was invoked.
    2 invocations · 0 advanced · 12 at a time, one worktree each
    attempts
      001.00  backend-coder  [R:1]  no change  dry run - would invoke backend-coder
      001.00  frontend-coder  [R:1]  no change  dry run - would invoke frontend-coder

`.plans/` afterwards: `001.00-⚪️--clean-agent-bondaries-and-transitions` only, no `.plans/tmp`.


## Front-end verification, frontend-coder (harness pid 38939), round 1 on 2026-09-16

Third independent measurement, from the frontend-coder launched at 08:43; it concurs with the 17151 and 36367 sections above. F1-F4 were on disk and committed, so no source or spec file was touched. Commands ran inside the worktree in a subshell with `RUBYOPT`, `RUBYLIB`, `BUNDLER_SETUP`, `BUNDLE_BIN_PATH`, `BUNDLER_VERSION` and `BUNDLE_LOCKFILE` unset and `BUNDLE_GEMFILE=$PWD/Gemfile`. Note for whoever runs next: `env` on this machine resolves to `~/.local/bin/env`, which swallows all output, so `env -u` looks like success and `alo` looks silent; use `unset` in a subshell and `/usr/bin/env`.

| Command                                                                                                   | Result                                                                                                         |
| :-------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------- |
| `bundle exec rspec` (worktree Gemfile; loaded `lib/agentilda/screen.rb` from this worktree, verified)     | 976 examples, 0 failures, 3 pending (worktree seeding); includes backend-coder's uncommitted `child.rb` fix              |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` (integration proof)  | 55 examples, 0 failures                                                                                        |
| `bundle exec rspec spec/agentilda/{screen,console,keyboard,tally}_spec.rb spec/agentilda/cli/run_spec.rb` | 77 examples, 0 failures                                                                                        |
| `bundle exec standardrb` (whole repo)                                                                     | exit 0, no offenses                                                                                            |
| `./exe/agentilda docs -o /tmp/x.md && diff /tmp/x.md docs/WORKFLOW.md`                                    | identical, 299 lines (F4)                                                                                      |
| `./exe/agentilda run --dir <parent>/.plans --isolation shared`, dry run, stdin from /dev/null             | exit 0; 3 invocations, 0 advanced; 001.00 under `backend-coder` and `frontend-coder`, 002.00 under `researcher`; nothing renamed; `.plans/tmp` pre-existed from the live harness and was left as found |
| `git rev-parse --short HEAD` before and after                                                             | `030518c` both times                                                                                           |
| `git status --short`                                                                                      | only backend-coder's `lib/agentilda/child.rb` and `spec/agentilda/child_spec.rb`                                        |

Mailbox message #9 to backend-coder names the test behind each criterion.


## Back-end verification, backend-coder, round 1 relaunch on 2026-10-13

Run in the worktree in a subshell with `RBENV_VERSION=4.0.6`, `RUBYOPT`, `RUBYLIB`, `BUNDLE_LOCKFILE`, `BUNDLER_SETUP`, `BUNDLE_BIN_PATH`, `BUNDLER_VERSION`, `GEM_HOME` unset and `BUNDLE_GEMFILE=$PWD/Gemfile`.

| Command                                                                                                  | Result                                     |
| :------------------------------------------------------------------------------------------------------- | :----------------------------------------- |
| `bundle exec rspec`                                                                                      | exit 0; 976 examples, 0 failures, 3 pending |
| `bundle exec rspec spec/agentilda/dispatcher_spec.rb spec/agentilda/cli/run_spec.rb` (integration proof) | 55 examples, 0 failures                    |
| `bundle exec rubocop`                                                                                    | exit 0; 147 files, no offenses             |
| `bundle exec standardrb`                                                                                 | exit 0                                     |
| `git rev-parse --short HEAD`                                                                             | `030518c`, unmoved                         |

Uncommitted on the tree for the harness: `.rubocop.yml` (new), `lib/agentilda/child.rb`, `spec/agentilda/child_spec.rb`, `lib/agentilda/ui.rb`, `exe/agentilda`. See the 2026-10-13 amendments in `implementation-plan.md`.

For the reviewer: this branch is 234 commits behind `origin/main`, which has since renamed the gem to `openlanes` and adopted its own `.rubocop.yml` with `rubocop-rspec`. Merging main will conflict broadly; that is outside this round.
