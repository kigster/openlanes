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
