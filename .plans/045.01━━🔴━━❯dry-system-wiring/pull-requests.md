# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 236 | [\[045.01\](A) Dry System Wiring](https://github.com/kigster/openlanes/pull/236) | Open 🟡 |

## Progress, backend-coder round 1 (2026-11-13)

`frontend: false`, so there is no `contract.md` or mailbox: backend-coder owns the whole plan.

Baseline: `CLAUDE.md` states `bundle exec rspec` is green on `main` (0 failures); this branch started from `main` at `bca5b1b0`.

- [x] U1 `Adapters.for` resolves `Container["adapters.<name>"]`; `NAMES` is the ordered list; `known?` answers from it; `registry` is derived from `names` (no hash literal) because `spec/openlanes/adapters/capabilities_spec.rb` still iterates it. Unknown-name message pinned byte-for-byte in `spec/openlanes/adapters_spec.rb`.
- [x] U2 `Vcs::Review` and `Vcs::LabelMigration` `include Deps["github"]`. `LabelSync`, `Publisher`, `Lifecycle::Adoption`, `Lifecycle::Resync::Prs`, `Vcs.github` and `Vcs.review` default `github:` to `Container["github"]` (their constructors take other keywords, and dry-auto_inject's generated `initialize` would have to be threaded through each one; the keyword and its per-call default are unchanged). `Vcs.label_sync`, `Vcs.label_migration` and `Execution.review_packets` keep `GitHub.new(chdir: root)`, with a comment: the root is per-call. New `spec/openlanes/vcs/deps_wiring_spec.rb`.
- [x] U3 `CLI::Linear::Team#survey_for` takes its API from `Container["linear"]`. New example in `spec/openlanes/cli/linear_commands_spec.rb` (there is no `spec/openlanes/cli/linear/` directory).
- [ ] U4 local seams (clock, process, logger, redis, event_bus): not started.
- [x] U5 `spec/openlanes/container_spec.rb`: `cli.create.create` (a collapsed `cli/<command>/` file keeps both segments in its key; the plan's `cli.create` guess does not exist), the provider directory set, each provider key, and each `adapters.<name>`.
- [ ] U6 integration spec with golden output, `just ci`, coverage baseline: not started.

`bundle exec rubocop`: 949 files, no offenses.

`bundle exec rspec`: 6414 examples, 1 failure (`architecture_doc_spec.rb`, stale `docs/architecture/`), fixed by `just update-architecture`; that spec then 2 examples, 0 failures. Line coverage 99.22% (99.19% on the run started at the beginning of the round).

## Progress, backend-coder round 2 (2026-11-13)

- [x] U4 Seventeen files under `lib/` now take `clock`, `process` and `logger` from the container (`Container["clock"]`, `Container["process"]`, `Container["logger"]`, as call-time defaults, so every caller that passes its own still works). `Live.connect(url)` and `EventBus.for(@store)` sites stay, as per-call factories over an argument; `notes.md` lists every remaining hit with its reason. New `spec/openlanes/local_seams_wiring_spec.rb`.
- [x] A race the wiring exposed: dry-system starts a provider on first resolve with no lock, and 16 threads resolving `process` together failed `key not found` 60 times in 30 runs. `lib/openlanes.rb` now starts `clock`, `process` and `logger` once at boot (20 of 20 racing runs then passed). `redis`, `github` and `linear` stay lazy.
- [x] U6 `spec/openlanes/integration/container_wiring_spec.rb`: `resync prs --dry-run` and `agents list` run through the real CLI classes with only the `github` key stubbed for a recording fake. The fake received both `pulls` reads, and STDOUT is byte-identical to `spec/fixtures/golden/container_wiring/*.txt`, captured from `main` at `bca5b1b0` in a detached worktree with `OPENLANES_GOLDEN=write` (the spec's header says how). `bundle exec rspec spec/openlanes/integration/container_wiring_spec.rb`: 4 examples, 0 failures.
- [x] `docs/architecture/` regenerated with `just update-architecture` after the lib changes.
- [x] `bundle exec rubocop`: 951 files inspected, no offenses detected.

### Acceptance (U6)

- `bundle exec rspec` (this branch): 6427 examples, 0 failures, 9 pending. Line coverage `jq '.result.line' coverage/.last_run.json`: **99.22**.
- Baseline on `main` at `bca5b1b0`, a clean run in a detached worktree: 6371 examples, 0 failures, 9 pending; line coverage **99.22**. Coverage is not below the baseline. Put both figures in the PR description.
- `bundle exec rubocop`: 951 files inspected, no offenses detected.
- `spec/openlanes/integration/container_wiring_spec.rb`: 4 examples, 0 failures; STDOUT byte-identical to the goldens captured from `main`.

## Findings: design-reviewer

### F201 [minor] lib/openlanes.rb:229

The thread-safety workaround for dry-system's unlocked first resolve lives in the load file, with `%i[clock process logger]` hard-coded. "Which providers are safe to start at boot" is a fact about the providers and the container, and it is written in neither. Scenario: the spans PR adds an `opentelemetry` provider that threads resolve together; nothing says it needs the same treatment, so `key not found` returns until someone finds this line. Suggest declaring it where providers live (an eager flag in the provider, or the loop in `container.rb`).

### F202 [minor] lib/openlanes/engine/state_file.rb:135

Three ways now inject the same collaborator: `include Deps[...]` (two classes), `Container["x"]` as a keyword default (most), and `Container["x"]` read inside a method body (`StateFile#begin_run!`/`#heartbeat!`, `CoverageGate#run`, `Runner#mint_run`). The last is reaching, not injecting. Scenario: a spec wants a fixed time in `StateFile#heartbeat!` and cannot pass a clock; it must stub the global container. The plan said `Deps[...]`. Suggest taking `clock:` in those constructors and using one style.

### F203 [minor] lib/openlanes/adapters.rb:111

`registry` builds all five adapters to recover their classes, and only `capabilities_spec.rb` calls it; `NAMES` repeats the keys the `adapters/*.rb` files already register. Scenario: stub `adapters.pi` with a fake and `registry["pi"]` becomes the fake's class. Add `adapters/foo.rb` and `adapters.foo` resolves while `known?("foo")` is false. Suggest dropping `registry` for the spec to iterate `names`, and deriving `names` from the container's `adapters.*` keys, or stating why not.

## Findings: security-reviewer

no findings. Checked: `Adapters.for` validates the name against the fixed `NAMES` list before building the `adapters.<name>` key, so input cannot choose a container key; the `linear` token still comes from the environment and is never logged or put in a fixture; the `github` and `process` providers return the same objects as before; the golden files hold no secrets; no dependency changes.

## Answers, round 1 (backend-coder, 2026-11-13)

The folder went 🔴 because the PR's CircleCI `test` and `e2e` jobs were still pending when staff-reviewer finished; `linter` and `web` had passed, and no finding was marked blocking. All review feedback on #236 is in pull-request comments, not review threads, so there is no thread to reply in; each is answered here.

- staff-reviewer F1, `fix`: the "sixty of thirty racing runs" comment is gone from `lib/openlanes.rb`; the measurement now reads "60 times across 30 racing runs", on `Container::EAGER` in `lib/openlanes/container.rb`.
- staff-reviewer F2, `fix` (pinned, not changed): a new example in `spec/openlanes/adapters_spec.rb` resolves all five `adapters.<name>` keys from five threads in a fresh process, where nothing has resolved them yet, and expects every thread to get its adapter. Component resolution has no provider-style first-start step to race; the adapters stay lazy, so a run that never probes loads none of them (A9: nothing loaded ahead of use).
- design-reviewer F201, `fix`: the eager-start list moved out of the load file into `OpenLanes::Container::EAGER` with `Container.start_eager`, beside the providers it describes; `lib/openlanes.rb` only calls it. A new example in `spec/openlanes/container_spec.rb` asserts the list, that each is started after boot, and that each names a real provider file.
- design-reviewer F202, `rebuttal`: in-body `Container["clock"]` reads in `StateFile`, `CoverageGate#run` and `Runner#mint_run` were left as they are this round. The plan's rule is no behaviour change and unchanged spec assertions; adding `clock:` to those three constructors is a signature change through `Engine.runner` and the dispatcher's `Desk`, out of a round opened for CI-pending. A spec needing a fixed time there uses `Container.stub("clock", fake)`, which is the seam this plan introduced. Worth a follow-up unit if one injection style is wanted.
- design-reviewer F203, `rebuttal`: `registry` stays because `spec/openlanes/adapters/capabilities_spec.rb` iterates it with existing assertions the plan says to leave unchanged, and deriving `names` from `adapters.*` keys would lose the probe order `NAMES` fixes (A2 in `adapters.rb` says the list is the one place a name is written). `Adapters.for` validates against `NAMES` before touching the container, so `adapters/foo.rb` resolving while `known?("foo")` is false is the intended guard, as security-reviewer noted.

### Acceptance, round 1 after review (2026-11-13)

- `bundle exec rspec`: 6429 examples, 0 failures, 9 pending. Line coverage `jq '.result.line' coverage/.last_run.json`: **99.22**, equal to the `main` baseline.
- `bundle exec rubocop`: 951 files inspected, no offenses detected.
- `just update-architecture`: no diff, `docs/architecture/` already matches `lib/`.
- `./exe/openlanes` CI on #236 at the time of this round: `linter` and `web` passed, `test` and `e2e` pending; the round changed only comments, the eager-start location and two spec files.
