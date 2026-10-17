# Contract: 021.00 Runtime State Outside Plans

Owner: luke-backend. Rey reads; asks through the mailbox.

## Baseline

- `bundle exec rspec` before any change: 3123 examples, 0 failures attributable to the base branch (CLAUDE.md: suite green). One run that overlapped luke's first `lock.rb` edit failed `spec/integration/plan_folder_migration_spec.rb:109`; that came from the edit in flight, and the same example passes on the final tree.
- After: 3148 examples, 0 failures, 9 pending (the web/dist-dependent integration specs). `bundle exec rubocop`: 438 files, no offenses.

## Interfaces rey calls

### `OpenLanes::Plans::Lock.read(dir)` (Ruby, F1)

- Input: the plan folder path, exactly as today (`feature.path`).
- Returns `Lock` or `nil`. Looks in the state directory first (`<XDG_STATE_HOME>/openlanes/<root>-<hash>/locks/<ordinal>.lock`), then the legacy `<dir>/locked-by.pid`.
- `Lock` attributes: `pid` (Integer), `host` (String), `started_at` (Time, UTC).
- `Lock#foreign?` -> Boolean: `host != Socket.gethostname`. A foreign lock is always held, never stale.
- `Lock#local?` stays (`!foreign?`).
- Errors: none raised; unreadable or missing returns `nil`.

### Snapshot `locked` (JSON, F2)

Per plan in the control-room snapshot (`Live::Snapshot`, served by the web board):

```text
locked: null
locked: { "pid": Integer, "host": String, "started_at": "ISO8601 UTC", "foreign": Boolean }
```

`foreign` is new; the other three keys and `null` are unchanged. Described in `openapi.yaml` in this folder.

## File ownership

| Files | Owner |
| --- | --- |
| `lib/openlanes/support/runtime.rb`, `lib/openlanes/plans/lock.rb`, `lib/openlanes/engine/*`, `lib/openlanes/lifecycle/resync.rb`, `lib/openlanes/live/snapshot.rb`, `lib/openlanes/plans/plan_state.rb`, `schemas/plan-state.schema.json`, `spec/spec_helper.rb`, `.gitignore`, `README.md`, `docs/decisions/decisions-on-runtime-state.md`, matching specs, `spec/integration/runtime_state_spec.rb` | luke |
| `lib/openlanes/presentation/reporter.rb`, `spec/openlanes/presentation/reporter_spec.rb`, everything under `web/` | rey |

Shared: none written by both. `spec/spec_helper.rb` is luke's and lands first (B1): it points `XDG_STATE_HOME` at a per-run temp dir, so rey's specs that write a lock through `Lock.write` land there too.

## Build order

B1 -> (B2, B3) -> B4 -> B5 -> B6. F1 and F2 start once B3 lands (luke mails rey). B5 reads the reporter's 🔑 line, so it runs after F1.

## Integration proof

`bundle exec rspec spec/integration/runtime_state_spec.rb`: a real `.plans` tree in a real git repo, a lock through `PlanLocks`, a `StateFile` saved; asserts nothing runtime under `.plans/`, the folder renamed while locked still reads as locked through `Lock.read`, the reporter's 🔑 line and the snapshot's `locked`. Nothing stubbed but `XDG_STATE_HOME`; the foreign case is a lock file naming another host, so `Socket.gethostname` needs no stub. amended: the plan allowed stubbing it; the spec does not need to.

## Amendments

- amended: `spec/openlanes/support/runtime_spec.rb` lives at `spec/openlanes/runtime_spec.rb`, because `RSpec/SpecFilePathFormat` requires the path to follow the constant and `support/` is collapsed.
- amended: `.gitignore` gets `.plans/**/*.tmp` (one line, covering `state.json.*.tmp` and `blocked.md.*.tmp`); the old lines stay in this repo, as in any other.
- amended: `Lock.write` also refuses a live or foreign legacy `locked-by.pid` held by another process, so a run on the old layout and one on the new cannot both claim a plan.

## Assumptions

- `root` for the state directory is the parent of the plans directory (`File.dirname(plans_dir)`), so a plan folder `dir` maps to root `File.dirname(File.dirname(dir))`.
