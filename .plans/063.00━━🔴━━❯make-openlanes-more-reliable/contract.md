# Contract, plan 063.00

Owner: backend-coder. No HTTP surface: the plan adds and changes no API, so there is no `openapi.yaml`.

## Baseline

Full `bundle exec rspec` on the branch at `4fcb6eb2`, before any change (9m52s, machine loaded by parallel agents; coverage 99.14%). 5 failures in 3 files, none of which this plan touches, reproduced alone with HEAD's `.openlanes.yml`:

- `spec/openlanes/agents/routing_spec.rb:19`, `:32`, `:42` and `spec/openlanes/engine/dispatcher_spec.rb:523`: routing expects `backend-coder` alone and gets more. Likely cause, unconfirmed: `frontend: true`, added to `.openlanes.yml` by `4fcb6eb2`, read by specs that run in the checkout.
- `spec/openlanes/engine/redis_outage_spec.rb:37`: `NoMethodError` from `hgetall` on a restarted Redis; environment-dependent (shared local Redis).

Plus, from this plan: `spec/openlanes/support/lefthook_spec.rb`, 5 examples, fails until blocked.md B1 is answered.

## Interfaces frontend-coder calls

None new. F1 reads the existing `GET /api/board` from the demo server started by `bin/web-e2e`, unchanged by this plan. Expected there: `005.00/staff-reviewer` reports `claude-opus-5-5` after the model is switched to Opus 5.5.

## Interfaces this plan adds (for humans, not for frontend-coder)

- `just bump <MAJOR.MINOR.PATCH> [--dry-run]` → `bin/bump-version`, run from the repository root.
  - Success: exit 0, prints `openlanes <old> -> <new>: lib/openlanes/version.rb and Gemfile.lock agree`.
  - `--dry-run`: exit 0, prints both intended changes and `dry run: nothing written`; writes nothing.
  - Errors, each exit 1 with `bump-version: <message>` on STDERR: no version (`usage: …`); a version that is not `MAJOR.MINOR.PATCH` (`"<v>" is not MAJOR.MINOR.PATCH`, nothing written); a missing `lib/openlanes/version.rb`, `Gemfile` or `Gemfile.lock`; `bundle lock` failing (tried `--local` first, then with network); the lock still disagreeing after relocking.
- `lefthook.yml` pre-commit job `architecture`: `glob: "lib/**/*.rb"`, no `root`, runs `just update-architecture && git add docs/architecture`. See blocked.md B1: not yet written.

## File ownership

| File                                         | Owner          |
| -------------------------------------------- | -------------- |
| `justfile` (the `bump` recipe only)          | backend-coder  |
| `bin/bump-version`                           | backend-coder  |
| `spec/openlanes/release/*_spec.rb`           | backend-coder  |
| `lefthook.yml` (the `architecture` job only) | backend-coder  |
| `spec/openlanes/support/lefthook_spec.rb`    | backend-coder  |
| `web/cypress/e2e/keyboard.cy.ts`             | frontend-coder |
| `web/cypress/support/e2e.ts`                 | frontend-coder |

No shared files.

## Build order

B1, B2 and F1 are independent; any order.

## Integration proof

F1's own: `web/cypress/e2e/keyboard.cy.ts` against the real demo server from `bin/web-e2e`, nothing stubbed, asserting `/api/board` reports `claude-opus-5-5` for `005.00/staff-reviewer` and the drawer reads "Model Opus 5.5". Run by whichever coder finishes last, via `just web-e2e`.
