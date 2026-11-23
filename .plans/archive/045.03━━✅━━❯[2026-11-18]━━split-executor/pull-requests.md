# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 267 | [\[045.03\](A) Split Executor](https://github.com/kigster/openlanes/pull/267) | Merged 🟣 |

## backend-coder, round 1

Baseline before any edit: `bundle exec rubocop` no offenses; `bundle exec rspec spec/openlanes/execution` 565 examples, 0 failures.

### Done

- U0 (partial): `spec/openlanes/execution/executor_split_integration_spec.rb` and `spec/fixtures/executor_split/runs.yml`, recorded on the uncut `executor.rb` with `OPENLANES_CAPTURE_FIXTURE=1`. Scenarios: success, dry run, throttled wait and start again, CLI exit failure, token budget kill. The prompt is recorded as the list of `##` sections after `## This invocation`, not its text, so edits to `agents/*.md` do not break the fixture.
- U1 (mostly): `Result`, `Compaction`, `Handle`, `Sessions` moved to `lib/openlanes/execution/executor/*.rb`, constant paths unchanged. `Result#initialize` merges `RESULT_DEFAULTS`; `Handle#compact!` is 10 lines (`request_compaction` and `TOO_LATE` extracted). New `Attempt`, `Request`, `Options` defined, not yet adopted. Specs: `spec/openlanes/execution/executor/value_types_spec.rb` (11 examples).

### Not done

- [ ] U0: timeout kill, confinement refusal, compaction, reattach scenarios.
- [ ] U1: `handle.rb` is 220 lines (wc -l), over the plan's 100-line file limit; ClassLength (code lines) passes. Needs a split or a ruling.
- [ ] U1: per-type spec files (`result_spec.rb` etc.) instead of the one `value_types_spec.rb`.
- [ ] U2 to U7.

### Checks, run after the last edit

```
bundle exec rubocop                       1129 files inspected, no offenses detected
bundle exec rspec                         6970 examples, 1 failure, 10 pending (coverage 99.2%)
  failure: spec/openlanes/thread_safety_inventory_spec.rb:18, Handle's mutex now lives in executor/handle.rb
  fixed: docs/thread-safety.md gains a handle.rb row; executor.rb's row now names @memory_lock
bundle exec rspec spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/execution
                                          580 examples, 0 failures
```

The whole suite was not run again after the docs fix: one run takes over 10 minutes. Next round starts with `bundle exec rspec`.

## backend-coder, round 2

### Done

- U2: `Executor::Grants` (`DENIED_TOOLS`, `FORBIDDEN_COMMANDS`, `UNGRANTABLE`, `denied_for`, `denied_commands`, `granted_to`) and `Executor::Preferences` (`profile_for`, `diff_lines`, `prefer_model`, `preferred_model`, `timeout_for`). `Executor::DENIED_TOOLS`, `::FORBIDDEN_COMMANDS` and `::UNGRANTABLE` are the same frozen objects as in `Grants`. The public methods stay on `Executor` and delegate.
- Two more cuts than the plan named, to keep each file under 100 lines (wc -l) and to one job each:
  - `Executor::Confinement` (`CONFINED_TOOLS`, `CONFINED_COMMANDS`, `CONFINED_CLI`, `allowed_for`), split out of `Grants`.
  - `Executor::Replacements` (the per-plan reviewer replacements behind `replace`, `replacing?`, `end_replacements`), split out of `Preferences`.
- Specs: `spec/openlanes/execution/executor/{grants,confinement,preferences,replacements}_spec.rb`.
- `executor.rb` is now 857 lines, down from 1008 after round 1 and 1370 at the start.

### Not done

- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U3 to U7.

- `docs/architecture/` regenerated with `just update-architecture`, ahead of U7: `architecture_doc_spec.rb` failed on the new classes, and this round must end with `bundle exec rspec` at exit 0. `docs/architecture/before/` untouched. U7 regenerates it again.

### Checks, run after the last edit

```
bundle exec rubocop    1137 files inspected, no offenses detected
bundle exec rspec      6989 examples, 0 failures, 10 pending (coverage 99.2%)
```

## backend-coder, round 3

### Done

- U3: `Executor::Invocation` builds every argv (first start, carried-on session, `/compact`) from an `Attempt` and writes the trace path. `Executor::PromptAssembly` assembles the prompt from an `Attempt` and a `Request`, and holds the reviewer packet and the lessons library, still behind `@memory_lock`. `Executor#invocation` keeps its keyword signature and builds the `Request` and `Attempt` itself. The private `resumption` stays on `Executor` as a thin shim for its three callers, until U4 and U5 pass an `Attempt`.
- `Executor#initialize` now builds an `Options` and hands it to `PromptAssembly` (the rest of the `Options` adoption is U6).
- `docs/thread-safety.md`: the `@memory_lock` row now names `executor/prompt_assembly.rb`.
- `docs/architecture/` regenerated again, `before/` untouched.
- Specs: `spec/openlanes/execution/executor/{invocation,prompt_assembly}_spec.rb`. The integration fixture's recorded argv passes unedited.
- `executor.rb`: 773 lines.

### Not done

- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U4 to U7.

### Checks, run after the last edit

```
bundle exec rubocop    1141 files inspected, no offenses detected
bundle exec rspec      7001 examples, 0 failures, 10 pending (coverage 99.2%)
```

## backend-coder, round 4

### Done

- U4, first half:
  - `Executor::JournalHold` (`forget`, `hold`): `hold` takes an `Attempt`.
  - `Executor::Launcher` (`launch`, `follow`, `start_clock`, `rearm`): it takes the spawner and reads an `Attempt`. `rearm` is given the agent's budget rather than reaching back for `timeout_for`.
- `call` and `reattach` now build one `Attempt` and pass it to the launcher and the journal hold. `start_again`, `carry_on` and `compact` still start sessions through a private `launch` shim with the old keywords, which builds an `Attempt` without agent or subject; it goes when `Supervision` and `Compactor` take an `Attempt` of their own.
- `Deps[...]` not wired: the container's `clock` is `Clock::System` (the time of day), while the launcher arms an `Execution::Clock` (the agent's countdown). They are different readings, so under the plan's rule the call stays as it is. The container's `process` (`Spawner::System`) is not what `AgentProcess.spawner` returns either, so the spawner stays injected through `spawn:`.
- Specs: `spec/openlanes/execution/executor/{journal_hold,launcher}_spec.rb`.
- `docs/architecture/` regenerated, `before/` untouched. `executor.rb`: 692 lines.

### Not done

- [ ] U4, second half: `ThrottleWait` (`ride_out`, `wait_out`, `standing_order`, `announce_wait`, `start_again`) and `Supervision` (`supervise`, `drain`, `lost_session`, `abort_if_over`) over an `Attempt`.
- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U5 to U7.

### Checks, run after the last edit

```
bundle exec rubocop    1145 files inspected, no offenses detected
bundle exec rspec      7010 examples, 0 failures, 10 pending (coverage 99.2%)
```

## backend-coder, round 5

### Done

- U4, second half, except `supervise` itself:
  - `Executor::ThrottleWait` (`ride_out` over an `Attempt`; the wait, the announcement and the pause loop are private).
  - The start after a wait is `Executor::StartAgain`.
  - The control-file word that outlasts a wait is `Executor::StandingOrder`.
  - One wait's limit, waits and seconds travel as `Executor::Wait`. That keeps every method at 4 parameters or fewer.
  - `Executor::Supervision` holds `drain`, `abort_if_over` and `lost_session`.
- `supervise` stays on `Executor` for now. Its loop calls `carry_on` and `settling`, which are U5's `Compactor`, so it moves into `Supervision` once that exists. It already builds one `Attempt` and passes it to `ride_out`.
- Specs: `spec/openlanes/execution/executor/{supervision,standing_order,start_again}_spec.rb`. `ThrottleWait` runs end to end under the unedited `executor_throttle_spec.rb` and the integration fixture's throttled scenario.
- `docs/architecture/` regenerated, `before/` untouched. `executor.rb`: 535 lines.

### Not done

- [ ] U5: `Compactor` (`carry_on`, `settling`, `uncompactable`, `compact`, `compacted_note`), then move `supervise` into `Supervision` and drop the private `launch` and `resumption` shims.
- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U6, U7.

### Checks, run after the last edit

```
bundle exec rubocop    1153 files inspected, no offenses detected
bundle exec rspec      7023 examples, 0 failures, 10 pending (coverage 99.21%)
```

## backend-coder, round 6

### Done

- U5: `Executor::Compactor` (`carry_on` and `settling` public; `uncompactable`, `compact`, the continuation and the refusal private) over an `Attempt`. It starts `/compact` and the continuation through `Invocation` and `Launcher`, on the attempt's profile with the requested model swapped in.
- `/compact`'s failure wording and the success reply are `Executor::CompactReply`, which keeps `compactor.rb` at 100 lines.
- `said` is now `Executor::Said.of`, shared by the compactor and the verdict. `Executor#said` stays public and delegates to it.
- The private `launch` and `resumption` shims are gone: nothing in `executor.rb` starts a session except through the launcher with a real `Attempt`.
- Specs: `spec/openlanes/execution/executor/{compactor,compact_reply,said}_spec.rb`. `executor_compaction_spec.rb` and `executor_resume_spec.rb` pass unedited.
- `docs/architecture/` regenerated, `before/` untouched. `executor.rb`: 428 lines.

### Not done

- [ ] Move `supervise` into `Supervision`. `ThrottleWait` drains through `Supervision`, so `drain` and `abort_if_over` must first move to a class of their own, or the two would depend on each other.
- [ ] U6: `Verdict`, `Options` adopted in `initialize`, short `call` and `reattach`.
- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U7.

### Checks, run after the last edit

```
bundle exec rubocop    1159 files inspected, no offenses detected
bundle exec rspec      7038 examples, 0 failures, 10 pending (coverage 99.21%)
```

## backend-coder, round 7

### Done

- U4 finished: `supervise` moved into `Executor::Supervision`, over an `Attempt` that now carries its clock.
  - A first start's three ways to start again (the resumed session id, a fresh relaunch, and the start a throttled one is started with again) travel as one `Executor::Restarts` value. `reattach` passes none.
  - The lost-session restart and the compaction loop are private steps of `Supervision`.
- `drain` and `abort_if_over` moved out of `Supervision` into `Executor::Drain`, which `ThrottleWait`, `Compactor` and `Supervision` each take. Without that, `Supervision` and `ThrottleWait` would depend on each other.
- `Executor` no longer has a private `supervise`. `call` and `reattach` hand `Supervision` the attempt, with the clock added once it is armed.
- Specs: new `spec/openlanes/execution/executor/drain_spec.rb`. `supervision_spec.rb` gains `#supervise` examples, and its budget examples moved to `drain_spec.rb`. Every existing `executor_*_spec.rb` passes unedited.
- `docs/architecture/` regenerated, `before/` untouched.
- Files over 100 lines (wc -l): `executor.rb` (397, U6 cuts it) and `handle.rb` (220).

### Not done

- [ ] U6: `Verdict` (`verdict`, `failure`, `spent`, `killed_note`), `Options` adopted in `initialize`, `call` and `reattach` as short sequences.
- [ ] U0: timeout kill, confinement refusal, compaction and reattach scenarios.
- [ ] `handle.rb` is 220 lines.
- [ ] U7.

### Checks, run after the last edit

```
bundle exec rubocop    1162 files inspected, no offenses detected
bundle exec rspec      7042 examples, 0 failures, 10 pending (coverage 99.22%)
```

## backend-coder, round 8

### Done

- U6:
  - `Executor::Verdict` holds the verdict, `failure`, `spent` and `killed_note`. The unused clock parameter is gone from `killed_note`; `Executor#killed_note` still accepts it.
  - `Executor#initialize(**)` collects its keywords into `Options`. `call` and `invocation` take `handle:` plus `**` keywords that become a `Request`, so callers pass exactly the keywords they passed before, and an unknown one still raises `ArgumentError`.
  - `call` is the dry-run and confinement refusals (`Executor::Refusal`), then one `Attempt` handed to `Executor::FirstStart`.
  - `reattach` builds the `Attempt` and hands it to `Executor::Retake`.
  - Both of those take one `Executor::Crew` value holding the launcher, invocations, supervision, verdict, preferences and trace directory, which `Crew.build` wires from `Options`.
  - The first start's argv is `Invocation#first`.
- Order kept: the journal record is still cleared after the prompt is built, because the prompt is cut to what the resumed session lacks.
- `Executor#failure`, `#spent`, `#said` and `#killed_note` stay public as one-line delegators. Nothing outside calls them, but they were public before.
- Specs: `spec/openlanes/execution/executor/{verdict,refusal}_spec.rb`. All 648 `spec/openlanes/execution` examples pass, the unedited integration fixture included.
- `docs/architecture/` regenerated, `before/` untouched.
- `executor.rb` is 259 lines by `wc -l`; most of it is the constants' and `initialize`'s documentation. Over 100 lines remain only `executor.rb` and `handle.rb` (220).

### Not done

- [x] U7: the six `lib/openlanes/execution/executor.rb` entries are gone from `.rubocop_todo.yml`, under Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName and Style/StringConcatenation. No Exclude list was left empty. `executor.rb` lints clean at the real limits.
- [x] `executor.rb` is 100 lines by `wc -l`. The constants' documentation moved to where each constant is now defined, and the old names stay as aliases:
  - `Grants::DENIED_TOOLS`, `FORBIDDEN_COMMANDS` and `UNGRANTABLE`
  - `Traces::DIR` (`TRACE_DIR`)
  - `Credentials::VARS` (`CREDENTIAL_VARS`) and `Credentials.foreign` (`.foreign_credentials`)
  - `Said::LIMIT` (`REASON_LIMIT`)
  - `Preferences::DEFAULT_TIMEOUT`
  - `Supervision::SESSION_MISSING`
  - `Deadline.of` (`.deadline`)
- [x] Each keyword `initialize` takes is now documented on `Options`, and the ones `call` takes on `Request`.
- [x] The public delegators moved into three mixins in `executor/`:
  - `Choices`: `profile_for`, `timeout_for`, `prefer_model`, `preferred_model`, `diff_lines` and the replacements.
  - `Permissions`: `denied_for`, `allowed_for`, `denied_commands` and `granted_to`.
  - `Reporting`: `failure`, `spent`, `said` and `killed_note`.
- [x] `handle.rb` (220 lines) is split. `Handle` keeps its state, clock and extension. `Handle::Stopping` holds the control file, `request_stop!`, `stopping?` and `kill!`. `Handle::Compacting` holds `compact!`, `take_compaction`, `close!` and `TOO_LATE`. The one `Mutex` is still created in `handle.rb`, where `docs/thread-safety.md` names it.
- [x] Every file under `lib/openlanes/execution/executor*` is now 100 lines or fewer, and `rg "method_missing|public_send|send\(" lib/openlanes/execution` finds nothing.
- [x] `docs/architecture/` is regenerated; `before/` is untouched.
- [x] Specs of their own for `FirstStart`, `Retake`, `Crew`, `Choices`, `Permissions`, `Reporting`, `Deadline` and `Handle::Compacting` (45 examples, added after the interruption below). `Handle::Stopping` was already covered by `handle_stop_spec.rb`.
  - `first_start_spec.rb` and `retake_spec.rb` run the two entry points over a `Crew` of doubles and assert what each arranges around the launch: the control file, the handle's label and trace, the restart record and its deadline, the journal record cleared only after the prompt is built and held back only when the round is not a rebase, the session dropped on a CLI that cannot resume one, and the three ways a session is started again.
  - `handle/compacting_spec.rb` covers the request handed out once, the same request while under way, the grace-period kill aimed at the first process only, and the refusal once the invocation is closed.
- [x] U0: a `unconfinable` scenario is in the fixture: `backend-coder` confined to `spec.md` on `codex`, which cannot confine, with the probe told codex is usable so it is not swapped for a CLI that could. It was recorded on the uncut `executor.rb` in a temporary detached checkout of this branch's `HEAD`, since removed, and the split code matches it.
- [x] U0: the timeout kill, compaction and reattach scenarios are not in the fixture. Ruled on in `plan.md` (D1, 2026-11-15): the six recorded scenarios are the fixture, and those three stay covered by the existing executor unit specs (`timeout_kill_spec.rb`, `executor_compaction_spec.rb`, `executor_reattach_spec.rb`) plus the new `first_start_spec.rb` and `retake_spec.rb`. Why they could not be recorded, for the record:
  - A timeout kill fires `Clock::GRACE` (60 seconds) after STOP, and `Launcher#start_clock` builds the clock itself, so a fast scenario needs an injected `now:` on the launcher, which is a change under `lib/` U0 forbids.
  - A reattach attaches to a recorded process (`AgentProcess.attach`), which a scripted spawn does not produce.
  - A compaction runs on a thread that terminates the first process after a grace period; with scripted processes the second start and the kill race, so the recording would not be the same twice.

### Checks, run after the last edit

- `bundle exec rubocop`: 1177 files inspected, no offenses detected
- `bundle exec rspec`: 7052 examples, 0 failures, 10 pending; Coverage: 99.22%
- `wc -l lib/openlanes/execution/executor.rb lib/openlanes/execution/executor/*.rb lib/openlanes/execution/executor/handle/*.rb | gawk '$1>100'`: only the total line
- `rg "method_missing|public_send|send\(" lib/openlanes/execution`: nothing
- `rg "lib/openlanes/execution/executor" .rubocop_todo.yml`: nothing

### Round 8, continued after the interruption

The round was interrupted after `blocked.md` was written; the question was answered (D1 in `plan.md`) and the round resumed from its record. What this continuation added is the unit specs listed above; nothing under `lib/` changed.

### Checks, run after the last edit of the continuation

- `bundle exec rubocop`: 1185 files inspected, no offenses detected
- `bundle exec rspec`: 7097 examples, 0 failures, 10 pending; Coverage: 99.22%
  - An earlier full run this round, started before the new spec files existed, had one failure: `spec/openlanes/engine/dispatcher_event_journal_spec.rb:108` (records the session id once the stream names it) saw `s-002.00` twice. It passed in the run above and in three runs of the file alone, and the dispatcher is not touched by this plan; it looks order- or timing-dependent and is worth a look of its own.
- `wc -l lib/openlanes/execution/executor.rb lib/openlanes/execution/executor/*.rb lib/openlanes/execution/executor/handle/*.rb | gawk '$1>100'`: only the total line
- `rg "method_missing|public_send|send\(" lib/openlanes/execution`: nothing
- `rg "lib/openlanes/execution/executor" .rubocop_todo.yml`: nothing
- `just update-architecture`: no further change to `docs/architecture/`; `before/` untouched

## Findings: staff-reviewer

Round 2 (head `f6248d14`). CI is red, so per the review rules the diff was not reviewed further.

### F1 [critical] .circleci/config.yml:1

`ci/circleci: test` failed on the pull request head: https://app.circleci.com/workflow/a1ac1459-a638-4b2c-9643-db5e36eb760d/job/c14ee1ed-6bbf-46e1-884f-1618c72b95cb (`circleci run get e7f9c414-82fa-4162-b631-329a9e2262cd --failure-report`). `linter`, `web` and `e2e` passed.

- Input: PR #267 at `f6248d14`, `bundle exec rspec` on CircleCI.
- Expected: 0 failures, as `pull-requests.md` round 8 reports (7097 examples, 0 failures).
- Actual: the `test` job fails. Locally `bundle exec rspec spec/openlanes/execution spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/docs/architecture_doc_spec.rb` passes (731 examples, 0 failures), so the failure is elsewhere in the suite or order/timing dependent. Round 8 already saw `spec/openlanes/engine/dispatcher_event_journal_spec.rb:108` fail once in a full run; check it first.

## backend-coder, round 9 (🔴 Changes Requested)

### F1: `ci/circleci: test` red on `f6248d14`

Root cause, from the job's step log (job 3275): `Run tests` passed. The step that failed is `Coverage of changed files`, which runs `bin/coverage-changed --base origin/main` and gates every changed `lib/` file at 95% line coverage. It named one file:

```
 85.71%  lib/openlanes/execution/executor/journal_hold.rb
coverage-changed: below 95%: lib/openlanes/execution/executor/journal_hold.rb
```

The two uncovered lines were the `rescue` bodies of `JournalHold.forget` and `JournalHold.hold`, which warn through `UI.log` when `state.json` cannot be cleared or written. No spec drove either. The whole-library figure (99.22%) hid it, which is exactly the case the per-file gate exists for.

Fix: `spec/openlanes/execution/executor/journal_hold_spec.rb` gains a context where `Plans::PlanState.for` raises `OpenLanes::Error`, with one example per method asserting the round does not fail and the warning is logged with the plan and agent. Nothing under `lib/` changed. `bin/coverage-changed --files lib/openlanes/execution/executor/journal_hold.rb` now prints 100.00%.

The earlier suspicion in round 8's notes (`dispatcher_event_journal_spec.rb:108`) was not the cause: that example passed in CI.

## Answers, round 9

- staff-reviewer's summary comment on PR #267 (issue comment 6898897333, F1): **fix**. See above. There are no review-thread comments on the pull request to reply to.

### Checks, run after the last edit (round 9)

```
bundle exec rubocop                      1235 files inspected, no offenses detected
bundle exec rspec                        7557 examples, 0 failures, 10 pending; Coverage: 99.26%
git fetch --no-tags origin main && bin/coverage-changed --base origin/main
                                         41 file(s), all at or above 95% (journal_hold.rb 100.00%)
```

## Findings: staff-reviewer, round 3

Head `f4d52abe`. Written here from the pull request comment, since the plan folder was locked when the review ran.

### F1 [must fix] `lib/openlanes/execution/executor.rb`, `lib/openlanes/execution/executor/handle.rb`

`wc -l ... | gawk '$1>100'` at `f4d52abe` prints `103 executor.rb` and `114 executor/handle.rb`, not only `total`, as spec.md In scope item 1 and plan U7 require. `handle.rb` gained `hold!` from main, `executor.rb` gained `AUTH_FAILURE` and `.spent_nothing?`. Rubocop's ClassLength counts code lines only, so `just ci` stayed green.

### F2 [minor] `lib/openlanes/execution/executor.rb:35`

`Executor.spent_nothing?` changed from keywords (`up:, down:, tools:`) to one positional object. It was public on `main`, where `Executor.spent_nothing?(up: 0, down: 0, tools: 0)` returns `true`; here it raised `NoMethodError`.

Verdict: rejected 2/2. The arbitrator ruled `no_go` at the rejection cap; the person asked chose "close the pull request and replan" (D1 in `plan.md`, 2026-11-15, second block). The harness nevertheless moved the plan back to 🟡 Building and started this round, so the two findings are fixed below; closing the pull request and replanning are not a builder's to do.

## backend-coder, round 10 (🟡 Building, after the round-3 review)

### F1: both files at or under 100 lines

- `handle.rb` (114 → 56): the clock (`clock`, `clock=`, `remaining`, `phase`, `extend!`, `say!`, `hold!`) moved to a third `Handle` mixin, `Handle::Timekeeping`, beside `Stopping` and `Compacting`. Bodies unchanged. The one `Mutex` is still created in `handle.rb`, where `docs/thread-safety.md` names it; `Timekeeping` synchronises on it.
- `executor.rb` (103 → 97): the three class-method delegators (`foreign_credentials`, `deadline`, `spent_nothing?`) moved to `Executor::Shortcuts`, which `Executor` extends. Same names, same arguments, same answers.

### F2: `Executor.spent_nothing?` takes both forms

`Spending.nothing?(spent = nil, **counts)` reads the counts off the object when given one, and otherwise builds them from `up:`, `down:`, `tools:`, all three required as on `main` (a missing one raises `ArgumentError`, as the old keyword signature did). `Executor.spent_nothing?` forwards both forms.

### Specs added

- `spec/openlanes/execution/executor/spending_spec.rb`: object form, keyword form, missing keyword, and both through `Executor.spent_nothing?`.
- `spec/openlanes/execution/executor/shortcuts_spec.rb`: `Executor` extends it; `foreign_credentials` and `deadline` answer as their sources do.
- `handle_time_spec.rb` and `executor_reattach_spec.rb` already cover `Timekeeping` through `Handle`.

`docs/architecture/openlanes-execution.md` regenerated by `just update-architecture`; `before/` untouched. Nothing else under `lib/` changed.

## Answers, round 10

- staff-reviewer's summary comment on PR #267 (issue comment 6899215265): F1 **fix**, F2 **fix**, both above. There are no review-thread comments to reply to.

### Checks, round 10 (STOP arrived before the full suite finished)

```
bundle exec rubocop                                    1239 files inspected, no offenses detected (after the last edit)
bundle exec rspec spec/openlanes/execution spec/openlanes/thread_safety_inventory_spec.rb \
  spec/openlanes/docs/architecture_doc_spec.rb spec/integration/resume_across_rounds_spec.rb
                                                       746 examples, 0 failures after the shortcuts_spec fix (7 examples in the two new files pass)
wc -l lib/openlanes/execution/executor.rb lib/openlanes/execution/executor/*.rb lib/openlanes/execution/executor/handle/*.rb | gawk '$1>100'
                                                       2327 total   (executor.rb 97, handle.rb 56, handle/timekeeping.rb 76)
rg "method_missing|public_send|send\(" lib/openlanes/execution        nothing
rg "lib/openlanes/execution/executor" .rubocop_todo.yml              nothing
```

Not finished: the full `bundle exec rspec` and `bin/coverage-changed --base origin/main` were still running when the harness said STOP. Nothing was red; they are the first step of the next round, together with `just update-architecture` (already run, diff is the three new modules only).
