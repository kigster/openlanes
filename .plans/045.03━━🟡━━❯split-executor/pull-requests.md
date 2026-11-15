# Pull Requests

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
