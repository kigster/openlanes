# OpenLanes repository guide

OpenLanes is a Ruby gem whose `openlanes` CLI creates feature briefs and coordinates specialist coding agents toward pull requests. Human operators merge. The seven role definitions live in `agents/`.

## Setup and verification

The current `.ruby-version` selects Ruby 4.0.6. Activate rbenv before Ruby commands:

```bash
eval "$(rbenv init -)"
bundle check
# If dependencies are missing:
bundle install
just ci
```

`just ci` runs RuboCop and RSpec with coverage. CircleCI configuration is in `.circleci/config.yml`. Prefer `.agent/saul-gooodman` as the gate if that script is added. Do not infer the current test baseline from historical failures in `CLAUDE.md`.

`bin/setup` can install tooling and dependencies. The `ratatui_ruby` native dependency requires Rust, clang and libclang; README documents the jemalloc include workaround.

## Code map

```text
exe/                 CLI entry points
agents/              seven Markdown agent definitions and permissions
lib/openlanes/
  cli/               commands and options
  runner.rb          execution dependencies and task preparation
  dispatcher.rb      admission, attempts and lifecycle loop
  executor.rb        Claude process invocation, limits and permissions
  transcript.rb      streamed events and usage
  status.rb          lifecycle invariants
  state_machine.rb   allowed transitions
  worktree.rb        plan checkout isolation
  publisher.rb       commits, pushes and PR creation
  github.rb          GitHub access seam
  linear/            Linear integration
spec/                RSpec fixtures and tests
docs/WORKFLOW.md     generated lifecycle documentation
evals/               starter evaluation cases, currently no runner
```

Folder names encode lifecycle state. Preserve one definition of invariants in `status.rb` and topology in `state_machine.rb`; regenerate documentation with `just update-workflow`. Agents supply roles through frontmatter. Network seams are injected in tests; filesystem tests use actual temporary directories.

Commands do the work they are named for and preview with `-n` / `--dry-run`; configuration can affect effective behavior, so inspect CLI help before executing runs. Worker agents cannot merge. The publisher, not the worker, owns pushing.

`CLAUDE.md` contains useful design history but stale setup and repository-status claims. Read current files before relying on those claims. For the proposed scheduler, Jev, independent review, Braintrust and eval changes, read [the factory proposal](docs/software-factory-proposal.md). Those changes are not implemented yet.

## Distribution

This is a gem, not a deployed web service. `just build` runs setup; `gem build openlanes.gemspec` builds a package. `just publish` publishes to RubyGems and uses 1Password or an explicit OTP. `just release` tags and publishes a GitHub release and currently force-updates tags. Publishing and release require an explicit release request. Update the guide when those commands change.

Keep `.env` and credential values out of commits, prompts and telemetry. Preserve pre-existing local changes when preparing a PR.
