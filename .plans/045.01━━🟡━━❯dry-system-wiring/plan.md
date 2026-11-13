---
execution: concurrent
---

Refactor share: about 30 of 2072 tracked files (1.4%), about 9,000 of 194,324 tracked lines (4.6%), against the 50% default threshold, so `concurrent`.

# Plan 045.01: Dry System Wiring

## Starting point

`lib/openlanes/container.rb`, `lib/openlanes/deps.rb` and all seven providers (`clock`, `event_bus`, `github`, `linear`, `logger`, `process`, `redis`) already exist and resolve in `spec/openlanes/container_spec.rb`. Nothing under `lib/` includes `Deps[...]` yet, and `Adapters.registry` is still a hand-written hash. This plan wires the existing container into the code. It does not build the container. The OpenTelemetry provider is not part of this plan (it ships with `instrumentation-spans`).

Rules for every unit:

- No behaviour change (A9). CLI output, `.plans/` files and API responses stay byte-identical. Existing spec assertions stay as they are. Specs may move with their class and may gain examples.
- A collaborator default becomes `include OpenLanes::Deps["<key>"]`, which keeps the same keyword (`github:`, `clock:`), so callers that pass their own keep working.
- A client built with arguments the provider cannot know (for example `Vcs::GitHub.new(chdir: root)`) stays hand-built, with a one-line comment saying why. The spec's `rg "\.new\("` check allows this exception: construction from per-call arguments is a factory call, not an injectable default.

## Order and dependency graph

```
U1 adapters ─────────────────────┐
U2 github ──┬─> U4 local seams ──┼─> U5 container spec ─> U6 integration + ci
U3 linear ──┘                    │
                                 └───────────────────────────────┘
```

- U1, U2 and U3 can run in parallel because they own disjoint files.
- U4 runs after U2 and U3. Its `rg` sweep would otherwise pick up the files they own.
- U5 runs after U1 to U4, because it asserts the key set they leave behind.
- U6 is the integration check and runs last.

## Backend

### U1 Adapters resolved by name

- **Discipline:** back end.
- **Owns:** `lib/openlanes/adapters.rb`, `spec/openlanes/adapters_spec.rb` (examples added only).
- **Must not touch:** `lib/openlanes/adapters/*.rb` (except to make a file auto-register as `adapters.<name>`, if one does not), `container.rb`, `providers/`.
- **Depends on:** nothing.
- **Shape:** delete the `registry` hash. `names` stays a frozen list `%w[claude codex pi grok gemini]` because it sets the order of probes and messages. `for(name)` resolves `Container["adapters.#{key}"]`. `known?(name)` answers from that list. The error message for an unknown name stays byte-identical.
- **Done when:** `spec/openlanes/adapters_spec.rb` passes with its existing assertions plus one new example per adapter resolving `adapters.<name>` from `OpenLanes::Container`, and `rg "registry" lib/openlanes/adapters.rb` finds no hash literal.

### U2 GitHub seam through `Deps["github"]`

- **Discipline:** back end.
- **Owns:** `lib/openlanes/vcs.rb`, `lib/openlanes/vcs/review.rb`, `lib/openlanes/vcs/label_sync.rb`, `lib/openlanes/vcs/label_migration.rb`, `lib/openlanes/vcs/publisher.rb`, `lib/openlanes/execution.rb`, `lib/openlanes/lifecycle/adoption.rb`, `lib/openlanes/lifecycle/resync.rb`, and their specs under `spec/openlanes/vcs/`, `spec/openlanes/lifecycle/` and `spec/openlanes/execution_spec.rb` (examples added only).
- **Must not touch:** `providers/`, `container.rb`, the files U1, U3 and U4 own.
- **Depends on:** nothing.
- **Shape:** each `github: GitHub.new` default becomes `include Deps["github"]`. `Vcs.github` returns `Container["github"]`. Defaults that use `chdir: root` stay hand-built and get a comment.
- **Done when:** the existing specs for those classes pass unchanged, and `spec/openlanes/vcs/deps_wiring_spec.rb` (new) shows that a `Container.stub("github", fake)` reaches `Review`, `LabelSync`, `LabelMigration`, `Publisher`, `Adoption` and `Resync` when they are built without a `github:` argument.

### U3 Linear seam through the container

- **Discipline:** back end.
- **Owns:** `lib/openlanes/cli/linear/linear.rb`, and any `Linear::API.new(token: …token_from_env)` site under `lib/openlanes/linear/`; `spec/openlanes/cli/linear/` and `spec/openlanes/linear/` (examples added only).
- **Must not touch:** `providers/linear.rb`, the files U1, U2 and U4 own.
- **Depends on:** nothing.
- **Shape:** the shared `Team` base gets its API from `Container["linear"]` (or from `Deps["linear"]` where a class takes one) instead of building it from the environment itself.
- **Done when:** the existing Linear CLI specs pass unchanged, plus one new example in `spec/openlanes/cli/linear/linear_spec.rb` showing that a stubbed `linear` key is the API the command uses.

### U4 Local seams: clock, process, logger, redis, event_bus

- **Discipline:** back end.
- **Owns:** every file under `lib/openlanes/` that hand-builds or names `Clock::System`, `Spawner::System`, `Log.logger`, `Live.connect(...)` or `Live::EventBus.for(...)` as a default collaborator. Today that is about 26 files (find them with `rg -l "Clock::System|Spawner::System|Log\.logger|Live\.connect\(|EventBus\.for\(" lib | rg -v providers/`), minus the files U1, U2 and U3 own. Their specs gain examples only.
- **Must not touch:** `providers/`, `container.rb`, `deps.rb`, the files U1, U2 and U3 own.
- **Depends on:** U2, U3 (the `rg` sweep must not reach files they still hold).
- **Shape:** a collaborator default becomes `Deps["clock"]`, `Deps["process"]`, `Deps["logger"]`, `Deps["redis"]` or `Deps["event_bus"]`. These stay as they are: value types (`Data.define`), per-call objects built from arguments (`Execution::Clock.new(seconds:)`, `Plans::LockClock.new`), and module-function facades whose seam is already a writer (`Adapters.probe_runner=`).
- **Done when:** the whole suite passes with unchanged assertions, and `rg "\.new\(" lib` outside factories and value types finds no construction of a class that has a registered provider key. U4 records that `rg` result, with each remaining hit justified in one line, in `.plans/<this plan>/notes.md` for the reviewer.

### U5 Container keys, collapsed directories and every provider

- **Discipline:** back end.
- **Owns:** `spec/openlanes/container_spec.rb` (examples added only; existing ones untouched).
- **Must not touch:** anything under `lib/`.
- **Depends on:** U1, U2, U3, U4.
- **Shape:** new examples:
  - one key under `support/` (already present as `support.clock`) and one under a collapsed `cli/<command>/` directory (for example `cli.create` resolving to `OpenLanes::CLI::Create`);
  - each of the seven provider keys resolving, and `ls lib/openlanes/providers` matching exactly that set;
  - `adapters.claude`, `adapters.codex`, `adapters.pi`, `adapters.grok` and `adapters.gemini` resolving to their adapter classes.
- **Done when:** `bundle exec rspec spec/openlanes/container_spec.rb` is green.

### U6 Integration check and acceptance

- **Discipline:** back end.
- **Owns:** `spec/openlanes/integration/container_wiring_spec.rb` (new).
- **Must not touch:** anything under `lib/`.
- **Depends on:** U5.
- **What it must show:** a real `exe/openlanes` command path runs against a `PlansFixture` tree with nothing stubbed except the `github` key in the container, which is swapped for a recording fake through `Container.stub`. The commands are `resync prs --dry-run` and `adapters`/`agents` listing, which resolves `adapters.<name>`. The spec asserts that:
  1. the fake received the GitHub calls, which proves `Deps["github"]` carries the injected client down the real call chain;
  2. STDOUT is byte-identical to a golden file captured from `main` before U1 to U4 (A9).
- **Done when:** that spec is green, `just ci` is green (rubocop has zero offenses and the suite has zero failures), and line coverage (`jq '.result.line' coverage/.last_run.json`) is not below the figure on `main` when this plan started. Record that baseline figure in the PR description.

## Frontend

No front-end work: `spec.md` says `frontend: false`.

## HTTP surface

No. This plan adds or changes no HTTP API, so there is no `openapi.yaml`.

## Sequential writes

- U1, U2 and U3 own disjoint files and may run at the same time.
- U4 writes only after U2 and U3 finish, because its ownership is defined by an `rg` sweep that would otherwise overlap theirs.
- U5 and U6 write only spec files nobody else owns, and they run last.

## How to test

From the repository root, with Ruby activated (`eval "$(rbenv init -)"`):

1. `bundle exec rspec` — the whole suite. Expect 0 failures (6427 examples, 9 pending at the time of writing) and `Coverage:` not below 99.22%, the figure on `main` at `bca5b1b0`.
1. `bundle exec rubocop` — expect `no offenses detected`.
1. `bundle exec rspec spec/openlanes/integration/container_wiring_spec.rb` — the integration proof: `resync prs --dry-run` and `agents list` run through the real CLI classes with only the `github` key stubbed. Expect 4 examples, 0 failures; a failure here means STDOUT drifted from the goldens captured from `main` in `spec/fixtures/golden/container_wiring/`.
1. `bundle exec rspec spec/openlanes/container_spec.rb spec/openlanes/adapters_spec.rb spec/openlanes/vcs/deps_wiring_spec.rb spec/openlanes/local_seams_wiring_spec.rb` — every provider key, every `adapters.<name>`, and the `github`, `clock`, `process` and `logger` keys reaching their classes. Expect 0 failures.
1. `rg "registry" lib/openlanes/adapters.rb` — expect no hash literal; `registry` is derived from `NAMES`.
1. `rg "Clock::System|Spawner::System|Log\.logger" lib --glob '!lib/openlanes/providers/*'` — expect only comments, YARD and `lib/openlanes.rb`'s boot-time `Container.start`; the remaining `Live.connect(` and `EventBus.for(` hits are listed, each with its reason, in this plan's `notes.md`.
1. `./exe/openlanes agents list` and `./exe/openlanes resync prs --dry-run` in any project with a `.plans/` folder — expect output identical to the released gem's: this plan changes no behaviour.
1. A thread-safety check for the race the wiring exposed: `bundle exec ruby -Ilib -e 'require "openlanes"; 16.times.map { Thread.new { OpenLanes::Container["process"] } }.each(&:join); puts "ok"'` — expect `ok`, never `key not found`.
