# Pull Requests

## Verification, luke-backend round 1 (back end only, no rey)

- `bundle exec rspec` → `3187 examples, 0 failures, 9 pending` (baseline: 3123, 0 failures, 9 pending)
- Re-run 2026-10-17: `bundle exec rspec` → `3187 examples, 30 failures, 9 pending`, all in `apps/` and `cli/app_spec.rb`, `Ports::Exhausted`; machine loopback answers every port. See `blocked.md` B1.
- `just lint` → `438 files inspected, no offenses detected`
- `./exe/openlanes agents list` → `ewoki-linker │ precedes ready_for_planning, planned │ in place │ haiku/low │ all`
- `./exe/openlanes eval --agent ewoki-linker` → `link-one` 8/8 PASS, `none` 7/7 PASS, `shared-files-only` 7/7 PASS
- `./exe/openlanes eval --agent ewoki-linker --recording fail` → all three FAIL, as planted
- Integration proof, `bundle exec rspec spec/openlanes/cli/run_linker_spec.rb spec/openlanes/engine/runner_linker_spec.rb` → `14 examples, 0 failures`
- Temp project, 034.00 at 📋 with `depends_on: []`, 050.00 at 📋 keyless and naming 034's parser, `./exe/openlanes run --dry-run --isolation shared`:
  - `034.00  luthen-rael-planner  [R:1]  no change  dry run - would invoke luthen-rael-planner`
  - `050.00  ewoki-linker       [R:1]  no change  dry run - would invoke ewoki-linker`
- No end-to-end suite in this repository beyond the above.
