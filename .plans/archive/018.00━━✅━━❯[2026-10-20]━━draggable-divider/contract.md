# Contract 018.00: draggable divider

## Interfaces frontend-coder calls

None. The plan adds and changes no HTTP route, no Ruby method and no `state.json` field (`plan.md`, `## HTTP surface`). No `openapi.yaml` is written. The divider's width lives only in the browser's `localStorage` under `openlanes-side-width`, which frontend-coder owns end to end.

## File ownership

| Files | Owner |
| :--- | :--- |
| `web/src/floating/useSideWidth.ts`, `useSideWidth.test.ts`, `web/src/floating/index.ts` | frontend-coder (F1) |
| `web/src/shell/ColumnDivider.tsx`, `ColumnDivider.test.tsx` | frontend-coder (F2) |
| `web/src/App.tsx`, `web/src/App.test.tsx`, `web/src/shell/shell.css` | frontend-coder (F3) |
| `web/cypress/e2e/divider.cy.ts` | frontend-coder (F4) |
| `contract.md`, `pull-requests.md` | backend-coder |

No file is shared. backend-coder writes nothing under `web/`, `lib/` or `spec/`.

amended: the `prompt_spec.rb` row is gone. The plan now runs in `openlanes.worktrees/018.00-draggable-divider`, an ASCII path, where that spec passes unchanged; backend-coder's fix lived only in the older `━━⚪━` worktree and is not part of this branch.

## Build order

F1 → F2 → F3 → F4. B1 (backend-coder) runs after F3: `bundle exec rspec spec/openlanes/web`, then `just web-build`.

## Integration proof

`just web-build && just web-e2e`: the built bundle served by `openlanes web --demo`, a real browser, real `/api`, nothing stubbed. `web/cypress/e2e/divider.cy.ts` (F4) is the divider's proof; the existing specs must stay green.

## Baseline (2026-10-15, before any backend-coder change)

- `bundle exec rspec`: 1 failure, `spec/openlanes/execution/prompt_spec.rb:49`. Cause: `Prompt#cli` shell-escapes `EXECUTABLE`, and this worktree's path holds `━` and `⚪`, so the escaped path no longer equals the raw one the spec expected. Environmental, not a regression; it passes in a checkout with an ASCII path. Fixed in the spec (compare against `Shellwords.escape(EXECUTABLE)`), since `rspec` must exit 0.
- `bundle exec rubocop`: 425 files, no offenses.
- Front-end suites: frontend-coder records their baseline (`just web-test`).

amended: baseline re-taken in `openlanes.worktrees/018.00-draggable-divider` (ASCII path). `bundle exec rspec`: 3013 examples, 0 failures. One earlier full run failed `spec/openlanes/apps/restart_spec.rb:77` and `spec/openlanes/apps/supervisor_spec.rb:133`; both pass in isolation (`spec/openlanes/apps`, 101/0, twice) and in the full rerun. Timing-sensitive port specs under load, not caused by this plan, which touches no Ruby.

## Built (B1)

- `bundle exec rspec spec/openlanes/web`: 167 examples, 0 failures.
- `just web-build`: built; `web/dist/assets/index-*.js` contains `Resize side panel`, so `openlanes web` serves the divider.
- `docs/badges/coverage_badge.svg` rewritten by rspec, reverted with `git checkout`.
