# Pull Requests

None yet: U1 (Desk) built in round 1; U2 to U8 remain.

## Round 3 full suite (after U1, U2 and the architecture regen)

`bundle exec rspec`: 6157 examples, 0 failures, 9 pending, coverage 98.41%, 9 min 56 s. The process was killed by a 10-minute background limit after rspec printed its summary, so its exit code was not captured.

## Round 4 full suite (after U3)

`bundle exec rspec`: 6563 examples, 1 failure, 9 pending, coverage 99.23%, exit 1. The failure was `architecture_doc_spec.rb:13` (docs stale after the new `assign/` classes); `just update-architecture` was rerun and that spec now passes (2 examples, 0 failures). `bundle exec rubocop`: exit 0.

## Round 5 full suite (after U4)

`bundle exec rspec`: 6569 examples, 0 failures, 9 pending, coverage 99.25%, exit 0, 9 min 2 s. `bundle exec rubocop`: 1012 files, no offenses, exit 0.

## Round 6 (U5)

`bundle exec rubocop`: 1023 files, no offenses, exit 0. Dispatcher-area specs: 994 examples, 0 failures. `rg "public_send|method_missing|send\(" lib/openlanes/engine/dispatcher*` prints nothing. Two hits remain elsewhere in `lib/openlanes/engine` (`rebase.rb:188`, `run_workflow.rb:782`), outside this plan's files. Full suite started; summary in `/tmp/045.02-r6-full.txt`, no EXIT line.

## Round 7 (U6)

Round 6 full suite: 6574 examples, 0 failures, 9 pending, coverage 99.25%. After U6: dispatcher, live, runner and integration specs 1071 examples, 0 failures; `bundle exec rubocop` 1035 files, exit 0. Full suite running into `/tmp/045.02-r7-full.txt`.

Round 7 full suite: 6580 examples, 1 failure, 9 pending, coverage 99.26%, exit 1. The failure was `dependencies_spec.rb:335`, a 5-second wall-clock assertion on a 50,000-plan chain in a file this plan does not touch; rerun alone it passes in 2.51 s, so it was machine load (files took 7.79 s to load in that run).

## Round 8 (U7, part of U8)

U7 split done: `poll/{sighting,mail,journal}.rb`, `lanes/{discards,copilot}.rb`, `rows/active.rb`, `rulings.rb` helpers, plus `settle/account.rb` and `start.rb` fixes that the todo entries had hidden. New specs for those classes: 21 examples, 0 failures. Removed from `.rubocop_todo.yml`, every `lib/openlanes/engine/dispatcher*` entry: Metrics/AbcSize (10: dispatcher.rb, assign, desk, lanes, poll, rename, rows, rulings, settle, start), Metrics/ClassLength (6: dispatcher.rb, assign, desk, rename, settle, start), Metrics/MethodLength (10, same files as AbcSize), Metrics/ParameterLists (2: dispatcher.rb, desk). `rubocop` on the dispatcher: 69 files, 0 offenses. `public_send` removed from `rebase.rb` (literal token readers) and `run_workflow.rb` (literal info/warn); `rg "method_missing|public_send|send\(" lib/openlanes/engine` prints nothing; rebase and run specs 126 examples, 0 failures.

Round 8 full suite (started after U7 code, before the U7 specs and the public_send fixes): 6580 examples, 0 failures, 9 pending, coverage 99.26%, exit 0.

## Round 9 (U8 integration spec)

`spec/openlanes/engine/dispatcher_split_integration_spec.rb` drives a real `Runner` through the real `Dispatcher` under `--isolation shared` with a scripted executor: plan 001.00 is planned and moves 📋 → ⭐ → 🟡 (planner Completed, then backend-coder started), plan 002.00 blocks (planner writes `blocked.md` and signs Blocked). It records the folder names before each tick, the `state.json` signatures, `blocked.md`, the attempts and the board text, and compares them with `spec/fixtures/dispatcher_split/run.yml`. That fixture was captured by running the same spec with `OPENLANES_CAPTURE_FIXTURE=1` in a detached worktree at this branch's HEAD (6a60b1f0, the pre-split main tip; `origin/main` in this checkout was stale at c9514793), then removed. On the split the spec passes against it: 1 example, 0 failures.
