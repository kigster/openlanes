---
execution: concurrent
---

Refactor share: about 24 of 2376 tracked files (1.0%), about 3600 of 282392 tracked lines (1.3%); threshold 50%, so `concurrent`.

# Plan: Split Executor (045.03)

Cut `Execution::Executor` (`lib/openlanes/execution/executor.rb`, 1370 lines, one class of 505 counted lines) to the A8 limits `.rubocop.yml` already sets (ClassLength 100, MethodLength 10, ParameterLists 4, AbcSize 20), with no change in behaviour. `045.01` (`Container`, `Deps[...]`) and `045.02` (split dispatcher) are merged, so collaborators the container provides are taken through `include Deps[...]` as each seam is cut.

## Starting point

`executor.rb` sits in `.rubocop_todo.yml` under AbcSize, ClassLength, MethodLength, ParameterLists, Naming/MethodParameterName and Style/StringConcatenation. Linted at the real limits it reports 43 offenses. The worst:

- `call`: 48 lines, AbcSize 54, 9 parameters
- `verdict`: 29 lines, AbcSize 34, 9 parameters
- `supervise` and `carry_on`: 20 lines each, 12 and 8 parameters
- `prompt_for`: 10 parameters
- `initialize`: 14 parameters

No A8 metaprogramming hit: `rg "public_send|method_missing|send\(" lib/openlanes/execution/executor.rb` prints nothing today. Keep it that way.

The parameter counts come from one bundle passed everywhere: `agent, subject, root:, profile:, trace:, handle:, sessions:, clock:`. Grouping that bundle in a value is the cut that makes every other unit fit.

## Rules every unit follows

- **The public surface is the contract.** Every name below stays reachable under the same name, with the same keywords and return values. A body may move into a collaborator; the name may not go.
  - Construction: `Executor.new(**)`, through `Execution.executor`.
  - Instance methods: `#call`, `#reattach`, `#invocation`, `#profile_for`, `#timeout_for`, `#replace`, `#replacing?`, `#end_replacements`, `#prefer_model`, `#preferred_model`, `#denied_for`, `#allowed_for`, `#denied_commands`, `#granted_to`, `#root`, `#model`.
  - Class methods: `.foreign_credentials`, `.deadline`.
  - Constants: `Executor::Result`, `::Handle`, `::Compaction`, `::Sessions`, `::TRACE_DIR`, `::FORBIDDEN_COMMANDS`, `::UNGRANTABLE`, `::CREDENTIAL_VARS`, `::DEFAULT_TIMEOUT`.
- **Constant paths do not change.** A nested type moves to `lib/openlanes/execution/executor/<name>.rb` and stays `Execution::Executor::<Name>`. Zeitwerk, the container key and every `Executor::Handle` reference outside then agree without edits.
- **Existing spec assertions do not change (A9).** `spec/openlanes/execution/executor_*_spec.rb` and `spec/openlanes/execution/executor/*_spec.rb` pass unedited after every unit. New classes get new spec files under `spec/openlanes/execution/executor/`.
- The `Thread.new` in `Handle#stop_after` stays a `Thread.new` (`045.13`, `concurrent-ruby-threads`, moves it). The `@memory_lock` mutex keeps guarding the lessons library.
- **`Deps[...]` only for what the container already provides:** `clock` (`Clock::System`) and `process` (`Spawner::System`). A unit wires one in only where the container's component returns the same reading the code takes today. Otherwise the call stays as it is, and the unit says so in its pull request notes.
- No unit but U7 edits `.rubocop_todo.yml` or `docs/architecture/`.
- No unit touches a caller outside `lib/openlanes/execution/executor*`: `engine/`, `live/`, `evals/`, `memory/`, `agents/agent.rb` and `execution.rb` stay as they are.

## Order and dependency graph

```mermaid
flowchart LR
  U0[U0 Baseline fixture] --> U1[U1 Value types]
  U1 --> U2[U2 Grants and preferences]
  U2 --> U3[U3 Invocation]
  U3 --> U4[U4 Supervision]
  U4 --> U5[U5 Compaction]
  U5 --> U6[U6 Verdict and entry points]
  U6 --> U7[U7 Integration]
```

This is a strict chain. U1 to U6 each delete methods from `executor.rb`, so no two of them may run at the same time, and each starts from the `executor.rb` the previous unit left. U0 runs first because its fixture must be recorded on code nobody has cut yet.

## Backend

### U0 Baseline fixture

- **Discipline:** back end.
- **Owns:** new `spec/openlanes/execution/executor_split_integration_spec.rb`; new `spec/fixtures/executor_split/` (the recorded expectation as YAML, and any scripted stream-json the fake agent replays).
- **Must not touch:** anything under `lib/`; every existing spec.
- **Depends on:** nothing.
- **Shape:**
  - The spec drives a real `Executor` through `Execution.executor(root:, spawn:, trace_dir:)` in a `PlansFixture` tree. `Boundary`, `Control`, `Clock`, `Prompt` and `Transcript` are the real ones. Only the agent CLI is replaced, by the scripted spawn the executor specs already use.
  - Scenarios: a plain success; a confined agent on an adapter that cannot confine; a dry run; a timeout kill; a throttled run that waits and starts again; a requested compaction that resumes; a `reattach` from a restart record.
  - Recorded for each scenario: the argv handed to the spawner, every `Result` field except `seconds` and `pid`, the `Handle#restart!` fields except timestamps, the trace file's line count, and the notes passed to `on_progress`.
- **Done when:** `spec/openlanes/execution/executor_split_integration_spec.rb` passes on the unchanged `executor.rb`, and the fixture is committed with it.

### U1 Value types

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/{result,compaction,handle,sessions,attempt,request,options}.rb`; new `spec/openlanes/execution/executor/{result,compaction,handle,sessions,attempt,request,options}_spec.rb`.
- **Must not touch:** `spec/fixtures/executor_split/`, the integration spec, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U0.
- **Shape:**
  - `Result`, `Compaction`, `Handle` and `Sessions` move out with their behaviour unchanged.
  - `Result#initialize` stops taking five explicit keywords; its defaults are merged from a constant instead.
  - `Handle#compact!` drops to 10 lines.
  - New `Executor::Attempt`, a `Data.define(:agent, :subject, :root, :profile, :trace, :handle, :sessions, :clock)`: the bundle every private method passes today. It uses `with(...)` for the clock that arrives after launch.
  - New `Executor::Request`, a `Data.define(:root, :control, :round, :successor, :partners, :rebase, :resume)`: the keywords `call` and `invocation` take.
  - New `Executor::Options`, a `Data.define` holding the 14 `initialize` keywords and their defaults.
  - This unit only defines `Attempt`, `Request` and `Options`. Later units adopt them.
- **Done when:** the new specs pass, every `executor_*_spec.rb` and the integration spec pass unedited, and each new file is ≤ 100 lines.

### U2 Grants and preferences

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/grants.rb` and `lib/openlanes/execution/executor/preferences.rb`; new `spec/openlanes/execution/executor/{grants,preferences}_spec.rb`.
- **Must not touch:** files U1 created, the integration spec and fixture, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U1.
- **Shape:**
  - `Executor::Grants` holds `DENIED_TOOLS`, `CONFINED_TOOLS`, `CONFINED_COMMANDS`, `CONFINED_CLI`, `FORBIDDEN_COMMANDS` and `UNGRANTABLE`, plus the bodies of `denied_for`, `allowed_for`, `denied_commands` and `granted_to`.
  - `Executor::FORBIDDEN_COMMANDS` and `::UNGRANTABLE` stay as references to the same frozen objects.
  - The autonomy boundary is unchanged: `UNGRANTABLE` is still subtracted from every grant.
  - `Executor::Preferences` holds the per-run tables (`@preferred`, `@replacing`) and the bodies of `replace`, `replacing?`, `end_replacements`, `prefer_model`, `preferred_model`, `profile_for`, `diff_lines` and `timeout_for`.
  - The public methods stay on `Executor` and delegate.
- **Done when:** the new specs pass; `executor_spec.rb` (grants, `profile_for`, `prefer_model`) and the integration spec pass unedited; each new file is ≤ 100 lines.

### U3 Invocation

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/invocation.rb` and `lib/openlanes/execution/executor/prompt_assembly.rb`; new `spec/openlanes/execution/executor/{invocation,prompt_assembly}_spec.rb`.
- **Must not touch:** files U1 and U2 created, the integration spec and fixture, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U2.
- **Shape:**
  - `invocation`, `resumption` and `trace_path` move to `Executor::Invocation`, which builds the argv from an agent, a subject and a `Request`.
  - `prompt_for`, `packet_for`, `lessons_for` and `lessons` move to `Executor::PromptAssembly`, which keeps the `@memory_lock` around the lessons library.
  - `Executor#invocation` keeps its keyword signature and builds the `Request` itself.
- **Done when:** the new specs pass; the 18 `executor.invocation` assertions in the existing specs and the integration spec's recorded argv pass unedited; each new file is ≤ 100 lines.

### U4 Supervision

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/{launcher,supervision,throttle_wait,journal_hold}.rb`; new specs with the same names under `spec/openlanes/execution/executor/`.
- **Must not touch:** files U1 to U3 created, the integration spec and fixture, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U3.
- **Shape:**
  - `Launcher`: `launch`, `follow`, `start_clock`, `rearm`.
  - `Supervision`: `supervise`, `drain`, `lost_session`, `abort_if_over`, each taking an `Attempt`.
  - `ThrottleWait`: `ride_out`, `wait_out`, `standing_order`, `announce_wait`, `start_again`.
  - `JournalHold`: `forget_journal`, `hold_journal`.
  - `clock` and `process` come through `Deps[...]` here, where the `Deps[...]` rule above allows it.
- **Done when:** the new specs pass; `executor_throttle_spec.rb`, `executor_journal_held_spec.rb`, `executor_reattach_spec.rb`, `timeout_kill_spec.rb`, `live_controls_spec.rb` and the integration spec pass unedited; each new file is ≤ 100 lines.

### U5 Compaction

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/compactor.rb`; new `spec/openlanes/execution/executor/compactor_spec.rb`.
- **Must not touch:** files U1 to U4 created, the integration spec and fixture, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U4.
- **Shape:** `carry_on`, `settling`, `uncompactable`, `compact` and `compacted_note` move to `Executor::Compactor`. It takes an `Attempt` and uses `Invocation` (from U3) for the resumed argv.
- **Done when:** `compactor_spec.rb` passes; `executor_compaction_spec.rb`, `executor_resume_spec.rb` and the integration spec's compaction scenario pass unedited; `compactor.rb` is ≤ 100 lines.

### U6 Verdict and entry points

- **Discipline:** back end.
- **Owns:** `lib/openlanes/execution/executor.rb` (in sequence); new `lib/openlanes/execution/executor/verdict.rb`; new `spec/openlanes/execution/executor/verdict_spec.rb`.
- **Must not touch:** files U1 to U5 created, the integration spec and fixture, `.rubocop_todo.yml`, `docs/architecture/`.
- **Depends on:** U5.
- **Shape:**
  - `Executor::Verdict` holds `verdict`, `failure`, `spent`, `said` and `killed_note`. The one-letter parameter name goes.
  - `initialize(**)` collects its keywords into `Options`.
  - `call` and `reattach` become short sequences over `Attempt`, `Request`, `Launcher`, `Supervision` and `Verdict`: the dry-run and confinement refusals first, then launch, supervise and judge.
  - Any string concatenation left becomes interpolation.
  - After this unit, `executor.rb` holds the class, the remaining constants, the delegators and the two entry points.
- **Done when:** `verdict_spec.rb` passes; every `executor_*_spec.rb`, every `executor/*_spec.rb` and the integration spec pass unedited; `wc -l` shows `lib/openlanes/execution/executor.rb` and `verdict.rb` each ≤ 100.

### U7 Integration check: the executor behaves as before and the limits hold

- **Discipline:** back end.
- **Owns:**
  - `.rubocop_todo.yml`: delete every `lib/openlanes/execution/executor.rb` entry (AbcSize, ClassLength, MethodLength, ParameterLists, Naming/MethodParameterName, Style/StringConcatenation).
  - `docs/architecture/`: regenerate with `just update-architecture`, leaving `docs/architecture/before/` untouched.
- **Must not touch:** any file under `lib/`, and the U0 fixture. A failing check goes back to the unit that owns the file.
- **Depends on:** U6.
- **Integration check, nothing stubbed but the agent CLI:** `spec/openlanes/execution/executor_split_integration_spec.rb`, unedited since U0, runs the real split `Executor` through `Execution.executor` against a `PlansFixture` tree. Across all seven scenarios (success, confinement refusal, dry run, timeout kill, throttle wait, compaction, reattach) it must produce the same argv, `Result` fields, restart record, trace line counts and progress notes as `spec/fixtures/executor_split/`, which was recorded before the cut.
- **Done when:**
  - `just ci` is green: rubocop with the executor entries gone from the todo, then the suite. Coverage in `coverage/.last_run.json` is not below the `main` figure recorded at the start of U0.
  - `spec/openlanes/execution/executor_split_integration_spec.rb` passes.
  - `spec/openlanes/docs/architecture_doc_spec.rb` passes.
  - `wc -l lib/openlanes/execution/executor.rb lib/openlanes/execution/executor/*.rb | gawk '$1>100'` prints only the `total` line.
  - `rg "method_missing|public_send|send\(" lib/openlanes/execution` has no computed-name hit.
  - `rg "lib/openlanes/execution/executor" .rubocop_todo.yml` prints nothing.
  - The pull request body lists every todo entry removed.

## Frontend

None: `spec.md` says `frontend: false`, and this is a back-end restructuring.

## HTTP surface

No. The plan adds and changes no HTTP API.

## How to test

From the checkout, with Ruby activated (`eval "$(rbenv init -)"`):

- `bundle exec rubocop`: no offenses, exit 0, with `executor.rb` no longer excused in `.rubocop_todo.yml`.
- `bundle exec rspec`: 0 failures, coverage not below the `main` figure.
- `bundle exec rspec spec/openlanes/execution/executor_split_integration_spec.rb`: passes against the fixture recorded before the split.
- `bundle exec rspec spec/openlanes/docs/architecture_doc_spec.rb`: passes.
- `wc -l lib/openlanes/execution/executor.rb lib/openlanes/execution/executor/*.rb | gawk '$1>100'`: prints only `total`.
- `./exe/openlanes run -n` in a project with a `.plans` folder shows the same board and assignments as before.

## Decisions

### B1 (answered) — Which comparison scenarios the split-executor fixture must hold

The recording holds six scenarios (success, confinement refusal, dry run, throttled wait and restart, CLI exit failure, token-budget kill). Timeout kill, reattach and compaction cannot be recorded within the fixture unit's limits: the timeout clock is built inside the launcher with no test hook, a reattach needs a real process, and a compaction stops the first process from a thread after a grace period, so recordings would not agree.

### D1 (decision) — Six scenarios are the fixture; the plan is complete

Answered:

- 2026-11-15
- By hermes

Accept the six recorded scenarios as the fixture and mark the plan complete. Timeout kill, reattach and compaction stay covered by the existing executor unit specs; no change under `lib/` for an injectable clock.

______________________________________________________________________

## Rebase decisions

- `lib/openlanes/execution/executor.rb`: kept the branch's 100-line facade and dropped the monolith that `origin/main` had edited. Main's three changes were ported into the split files instead: `Result#tools`, `#failed_start?`, `#auth_failure?`, `#auth_reason` (`result.rb`, with `Verdict#spent` filling `tools:`); `Handle#say!` and `#hold!` (`handle.rb`); `AUTH_FAILURE` (new `auth_failure.rb`, exposed as `Executor::AUTH_FAILURE`) and `Executor.spent_nothing?(spent)` (new `spending.rb`, used by `Result`, `StartAgain#unspent?` and `Supervision#quiet?`/`lost_session`, so the "spent nothing" test is still written once).
- `.plans/045.03…/state.json`: took the branch's version. The `HEAD` side was an older snapshot of the same plan state (round 7), and the branch's is the later record of rounds 8 and 9. Dropped the stale `held` marker with it.
- `.plans/045.03…/plan.md`, `pull-requests.md`: took the branch's version; the `HEAD` side of each conflict was empty or an earlier copy, so nothing from main is lost.
