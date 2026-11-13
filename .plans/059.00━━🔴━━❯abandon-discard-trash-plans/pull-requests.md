# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 213 | [\[059.00\](A) Abandon Discard Trash Plans](https://github.com/kigster/openlanes/pull/213) | Open 🟡 |

## Building, round 1 (backend-coder)

Tasks 1 to 6 of `plan.md` were already on `main` when this round started (`3e74922e Add abandoned and trashed plan states` and the work that followed): states, `Lifecycle::Rewiring`, `Lifecycle::Removal`, `Plans::RemovedReadme`, `resync dirs` placement, the `plans abandon|discard|trash` commands with `ReasonInterview`, and the PR watcher changes, each with its specs. This round verified them against `plan.md` and closed the gaps:

- `skills/openlanes/SKILL.md`: the stale sentence that still put discarded plans in `abandoned/` now names `abandoned/`, `discarded/` and `trashed/`.
- `.openlanes.yml`: a `coverage:` section (`bundle exec rspec`, minimum 95, `report_command` reading `.total.lines.percent` from `coverage/coverage.json`; the full run reported 99.14%).
- `plan.md`: `## Frontend` (no units) and `## Backend` sections.

No frontend: the plan is CLI and library work only, so there is no integration proof across halves.
- `spec/openlanes/agents/routing_spec.rb`: the baseline full run had 1 failure (`routing_spec.rb:32`, 3 in that file alone). Those examples read this repository's own `.openlanes.yml`, which says `frontend: true`, through `Config.current`. The spec now runs from the fixture's root.

## Verification

- `bundle exec rspec` (full suite, before the routing fix): 1 failure, `spec/openlanes/agents/routing_spec.rb:32`; coverage 99.14%.
- `bundle exec rspec spec/openlanes/agents/routing_spec.rb` after the fix: 22 examples, 0 failures.
- `bundle exec rubocop`: 847 files, no offenses.
- Not re-run: the full suite after the routing fix (it takes about 10 minutes, longer than this round had left).

## Building, round 1, continued (backend-coder)

- The repository's `.openlanes.yml` (recreated in `4fcb6eb2`) now says `frontend: true` and `desired_codebase_quality: high`, and `Config.current` read it from the suite's working directory. Besides `routing_spec.rb`, it also broke `dispatcher_spec.rb:523` (expected backend-coder alone) and 3 examples in `run_workflow_spec.rb`. Both specs now `chdir` to the fixture root, as `routing_spec.rb` does.
- `bundle exec rspec` (full, after the routing fix): 5936 examples, 7 failures: the 4 above, now fixed, plus 3 Redis outage specs (see `blocked.md` B1).
- `bundle exec rspec spec/openlanes/engine/dispatcher_spec.rb spec/openlanes/engine/run_workflow_spec.rb spec/openlanes/agents/routing_spec.rb`: 157 examples, 0 failures.
- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb`: 4 examples, 2 failures (`can't modify string; temporarily locked` in `Live::Store#call`).
- `bundle exec rubocop`: 847 files, no offenses.

## Building, round 1, B1 answered (backend-coder)

B1 was answered `b)`: fix the Redis outage failures inside this plan.

- Cause: one `Live::Store` (one `RedisClient`) is shared by threads. The engine's `Outage` pings from the dispatcher tick while agent threads publish, and `RedisClient` is not thread-safe, so a call found the other thread's write buffer mid-use and raised `can't modify string; temporarily locked`.
- Fix: `lib/openlanes/live/store.rb` holds a `Monitor` around every command (`guarded`) and around `close`. A blocking `xread` holds it for the whole wait; the class comment says so.
- Spec: `spec/openlanes/live/store_spec.rb`, "answers callers on several threads at once" (8 threads × 200 set/ping). Failed before the fix with the same error, passes after.
- `bundle exec rspec spec/openlanes/live/store_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/redis_outage_integration_spec.rb`: 34 examples, 0 failures.
- `bundle exec rspec` (full, after the Store fix): 5937 examples, 1 failure, 9 pending (Redis or tool skips); coverage 99.17%. The failure was `spec/openlanes/thread_safety_inventory_spec.rb:18`: the new `Monitor` in `live/store.rb` was not listed in `docs/thread-safety.md`. Added its row (guarded).
- `bundle exec rspec spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/live/store_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/redis_outage_integration_spec.rb`: 38 examples, 0 failures. The only change since the full run is that one docs row, which only the inventory spec reads; the full suite was not re-run after it (about 10 minutes, longer than this round had left).
- `bundle exec rubocop`: 847 files, no offenses.

## Building, round 1, How to test (backend-coder)

- Added `## How to test` to `plan.md`, as the operator's mail asked. Nothing else in `plan.md` changed.
- `bundle exec rspec` (full, with the Store fix and the `docs/thread-safety.md` row): 5937 examples, 0 failures, 9 pending (Redis or tool skips); coverage 99.17%; exit 0.
- `bundle exec rubocop`: 847 files, no offenses.

## Findings: design-reviewer

### F201 [minor] spec/openlanes/engine/dispatcher_spec.rb:6

The same fix (`Dir.chdir(File.dirname(plans_root))`, with a near-identical comment about this repository's `.openlanes.yml`) is pasted into three specs (`dispatcher_spec.rb`, `run_workflow_spec.rb`, `routing_spec.rb`). The rule "a `:tree` spec must not read the host repo's `.openlanes.yml`" is written down three times, and the next spec that builds a tree will hit the same failure. Scenario: a new `:tree` spec routes a plan; `Config.current` reads the checkout's `frontend: true`; it expects backend-coder alone and gets both coders. Suggest doing it once in the `:tree` hook (`spec/support/git_repo.rb` / `plans_fixture.rb`); `spec_helper.rb:165` already restores the cwd.

### F202 [minor] lib/openlanes/live/store.rb:26

Serialising on one `Monitor` that a blocking `xread` holds for its whole wait makes the "give a blocking caller its own store" rule a convention only the comment enforces. No caller in `lib/` passes `block:` today (only `Live.replies` forwards it), so nothing is wrong yet. Scenario: a future caller passes `block: 5000` on the shared store; the tick's outage `ping` then waits up to 5 s behind it. Consider noting it on `#xread` as well, or rejecting `block:` on a shared instance.

## Findings: security-reviewer

no findings

Checked: `Live::Store` Monitor (no new input, no secret, no path/shell/SQL built; lock released on exception via `synchronize`), `.openlanes.yml` coverage commands (repo-owned config, fixed strings), SKILL.md/doc text, spec `chdir` changes (test-only), no dependency changes.

## Findings: staff-reviewer

### F1 [minor] lib/openlanes/live/store.rb:281

One `Monitor` now serialises every command, so the per-command `TIMEOUT` (2 s) adds up across queued callers when Redis stops answering. Scenario: Redis accepts the TCP connection but stops replying (paused, swapping) while 6 agent threads are each in a `publish`/`xadd`. Expected: the tick's outage `ping` reports `Unavailable` within about `TIMEOUT`. Actual: it waits behind each queued caller's own 2 s timeout (plus `reconnect_attempts: 1`), so 12 s or more before the engine notices. Not a correctness bug, and the old unserialised code was broken outright; worth a note, or a short-lived "unavailable" flag that fails queued callers fast once one call has timed out.

Checked and holding: scope matches D1 (Redis fix sanctioned) plus the SKILL.md sentence and spec isolation; `coverage:` added at 95, not lowered; `guarded` still maps `RedisClient::Error` to `Unavailable` with the lock released by `synchronize`; `Monitor` is re-entrant, and no path inside `guarded` re-enters it anyway; no `lib/` caller passes `block:` to a shared store; the thread spec fails without the lock (reported by the builder). Re-ran `store_spec`, `routing_spec`, `redis_outage_spec`, `redis_outage_integration_spec`, `thread_safety_inventory_spec` with Redis up: 60 examples, 0 failures. `rubocop` on the touched files: no offenses.

## Changes requested, round 1 (backend-coder)

PR #213 has no inline review comments, so there is no `## Answers` list; the three findings above are each fixed:

- F201 fix: the `:tree` hook in `spec/spec_helper.rb` now `chdir`s into the fixture's temp root, with the one comment saying why (`Config.current` reads `.openlanes.yml` from the working directory). The three copies in `dispatcher_spec.rb`, `run_workflow_spec.rb` and `routing_spec.rb` are gone; the existing around hook still restores the cwd.
- F1 fix: `lib/openlanes/live/store.rb` records when a call last failed with a connection error (`@failed_at`, monotonic, written inside the lock). A caller that queued before that failure is failed with `Unavailable` as soon as it gets the lock, without touching the connection; a caller that arrives later asks Redis again. Queued callers no longer each wait out `TIMEOUT`. Spec: `spec/openlanes/live/store_fail_fast_spec.rb` (no Redis needed: a stand-in client that hangs, then times out); it fails without the fix, since the queued ping reaches the client and gets `PONG`.
- F202 fix: `#xread` now says on itself that `block:` holds the lock for the whole wait, outage ping included, and belongs only on a store of its own.
- `docs/thread-safety.md`: the `live/store.rb` row names `@failed_at` and that it lives inside the lock.
- `bundle exec rspec` on the affected files (fail-fast, store, both outage specs, routing, dispatcher, run_workflow): 193 examples, 0 failures. `thread_safety_inventory_spec.rb` after its row changed: 4 examples, 0 failures.
- `bundle exec rspec` (full, with every change above except the `docs/thread-safety.md` row): `Finished in 9 minutes 54 seconds`, 5300 examples, 0 failures, 9 pending. The shell hit its 10-minute limit during SimpleCov's report at exit, after the summary printed, so the exit status and coverage figure were not captured. Round 4 counted 5937 examples, and this round did not track down why the count is lower.
- `bundle exec rubocop`: 848 files, no offenses.

## Changes requested, round 2 (backend-coder)

- The harness stopped round 1 as "agent pushed (origin/kig/improve-architecture-doc-pages)". That ref's reflog shows `update by push` at 21:31:05 and 21:32:46. That branch is not this plan's, and no worktree has it checked out, so the pushes came from the main checkout, which shares `refs/remotes` with this worktree. backend-coder ran no `git push` (it is withheld), and `HEAD` is still `8a6b5a71`. This is the blind spot `Boundary` names: a push by another session in the same repository reads as this agent's.
- No new findings and no inline PR comments since round 1; this round reruns the full suite to get an exit status and coverage figure.
- `bundle exec rspec --dry-run`: 5939 examples (round 4's 5937 plus the 2 in `store_fail_fast_spec.rb`), so the 5300 from round 1's killed run was a run cut short, not missing specs.
- The full `bundle exec rspec` was still running when this round got STOP, so there is still no exit status or coverage figure. Not signed Completed.

## Changes requested, round 3 (backend-coder)

- `bundle exec rspec` (full, with all round 1 fixes): 10 min 14 s, 5939 examples, 6 failures, 9 pending, coverage 99.16%, exit 1.
  - `executor_spec.rb:594`, `:601`: the F201 hook moved `:tree` examples into a temp root, and this group reads `agents/` relative to the repository on purpose. Fix: the hook skips the `chdir` for groups tagged `:host_cwd`, and this group is tagged.
  - `web_spec.rb:255`, `:277`, `engine_command_spec.rb:289`, `:317`: not caused by this plan's code. The harness shell exports `OPENLANES_ADMIN_CREDENTIALS`, so the server under test got a login. They pass with it unset (194 examples, 0 failures). Fix: `spec_helper.rb` removes that variable around every example and puts it back afterwards, as it already does for `OPENLANES_LOG*`.
- After the fixes, with the variable still exported: `bundle exec rspec spec/openlanes/cli/web_spec.rb spec/openlanes/cli/engine_command_spec.rb spec/openlanes/web`: 355 examples, 0 failures. Without it, the three formerly failing files plus routing, dispatcher, run_workflow and store_fail_fast: 353 examples, 0 failures.
- `bundle exec rubocop`: 848 files, no offenses.
- The full suite was not re-run after these two spec-helper fixes (it takes 10 minutes; this round had 20). The fixes touch only `spec/spec_helper.rb` and one `describe` tag.

## Changes requested, round 4 (backend-coder)

- No new findings and no inline comments on PR #213 (`gh api .../pulls/213/comments`: 0). Code unchanged this round.
- `bundle exec rspec` (full, with every fix through round 3, `OPENLANES_ADMIN_CREDENTIALS` still exported by the harness shell): `Finished in 12 minutes 12 seconds`, 5939 examples, 0 failures, 9 pending, coverage 99.17%, exit 0.
- `bundle exec rubocop`: 848 files, no offenses.
