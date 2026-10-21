# Pull Requests

## Checks, round 1 (luke-backend)

- `bundle exec rubocop`: 441 files inspected, no offenses detected
- `bundle exec rspec`: 3177 examples, 30 failures, 9 pending; all 30 in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb` (machine answers every local port, see `blocked.md` B1)
- `bundle exec rspec spec/openlanes/{plans,evals,agents,engine,execution} spec/openlanes/vcs/mainline_spec.rb spec/openlanes/cli/link_spec.rb spec/openlanes/lifecycle/linker_spec.rb spec/openlanes/cli/help_spec.rb`: 1194 examples, 0 failures
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place`
- integration proof `spec/openlanes/cli/link_spec.rb`: `link --dry-run` prints `would invoke ewoki-linker for 050.00` and nothing for the `[none]` plan; refuses in a linked worktree and off `main`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS; `--recording fail` fails all three
