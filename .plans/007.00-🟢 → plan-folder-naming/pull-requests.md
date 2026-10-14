# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 24 | [\[007.00\] Plan Folder Naming](https://github.com/kigster/openlanes/pull/24) | Open 🟡 |

## Front end (rey-frontend, round 1)

- `cd web && npx vitest run`: 27 files, 293 tests passed
- `cd web && npx eslint .`: no output
- `cd web && npx tsc -b --noEmit`: no errors
- `bundle exec rubocop`: 301 files, no offenses

## Verification (round 2, 2026-10-14)

- `bundle exec rspec`: 2355 examples, 0 failures
- `bundle exec rubocop` (`just lint`): 310 files, no offenses
- `cd web && npx vitest run`: 27 files, 293 tests passed
- `cd web && npx eslint .`: no output
- `cd web && npx tsc -b --noEmit`: no errors
- `spec/integration/plan_folder_migration_spec.rb`: a temp git repo with old-form folders, driven through `exe/openlanes` (`resync dirs -n`, `resync dirs`, `list-plans`, `list-plans --all`, `create`) plus `Live::Snapshot`; 7 examples pass

