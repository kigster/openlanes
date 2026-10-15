# Implementation plan, 002.00

No front end: `plan-frontend.md` has no units, so rey-frontend is not started and there is no mailbox traffic. This file records the baseline, the interfaces as built, and the progress per unit.

## Baseline

`bundle exec rspec` on `origin/main` (`b2b5176`), 2026-10-14, before any change: `2214 examples, 0 failures`. `bundle exec rubocop`: no offenses.

## Interfaces as built

| Call | Answers |
| --- | --- |
| `OpenLanes::Refusal` | `Data.define(:message, :status)`; the `Failure` value of every workflow below |
| `CLI::Base#unwrap(result)` | the `Success` value, or `refuse(message, status)` |
| `Execution.credentials_notice` | `String` or `nil` |
| `Lifecycle.retitle_prs(tree:, github:, adopt:, root:, commit:)` | `Success(Array<Resync::Prs::Change>)`, `Failure(Refusal(…, 69))` |
| `Presentation.pr_changes(changes, dry_run:)` | `PrChanges` with `#lines` (STDOUT rows) and `#report` (STDERR) |
| `Lifecycle.unblock(tree:, agent:, root:, dry_run:, quiet:).call(tokens)` | `Success(0 \| 1 \| 65 \| 66)`, `Failure(Refusal(…, 65))` for an unknown agent |
| `Lifecycle.create_plan(dir:, root:, after:, status:, prs:, from:, spec:, draft:, lane:, depth:).call(words)` | `Success(CreateWorkflow::Created(path, message, spec))`, `Failure(Refusal(…, 64 \| 65 \| 66))` |
| `Engine.run(tree:, origin:, **options).call` | `Success(0 \| 1)`, `Failure(Refusal(…, 64 \| 65 \| 66))` |
| `Engine.start(tree:, origin:, rescan:, **options).call` | `Success(0)`, `Failure(Refusal(…, 69))` without Redis or the control room |

amended: `require "dry/monads"` moved from `lifecycle/creator.rb` alone to `lib/openlanes.rb`, beside the other dry-rb requires, because `Refusal` and every workflow now depend on it. Not in the plan's ownership table; one line.

## Progress

- [x] B1 `Refusal`, `Base#unwrap`, `Execution.credentials_notice`
- [x] B2 `resync prs` over `Lifecycle.retitle_prs` and `Presentation::PrChanges`
- [x] B3 `unblock` over `Lifecycle::UnblockWorkflow`
- [x] B4 `create` over `Lifecycle::CreateWorkflow`
- [x] B5 `run` and `start` over `Engine::RunWorkflow` and `Engine::StartWorkflow`
- [x] B6 `spec/openlanes/integration/thin_commands_spec.rb`

## Integration proof

`spec/openlanes/integration/thin_commands_spec.rb` spawns `exe/openlanes` in a `PlansFixture` project with fake `claude`, `codex` and `pi` first on `PATH` and `BUNDLER_ORIG_PATH`. Results in `pull-requests.md`.
