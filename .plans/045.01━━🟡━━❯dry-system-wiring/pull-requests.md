# Pull Requests

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
