# Contract 018.00: draggable divider

## Interfaces rey calls

None. The plan adds and changes no HTTP route, no Ruby method and no `state.json` field (`plan.md`, `## HTTP surface`). No `openapi.yaml` is written. The divider's width lives only in the browser's `localStorage` under `openlanes-side-width`, which rey owns end to end.

## File ownership

| Files | Owner |
| :--- | :--- |
| `web/src/floating/useSideWidth.ts`, `useSideWidth.test.ts`, `web/src/floating/index.ts` | rey (F1) |
| `web/src/shell/ColumnDivider.tsx`, `ColumnDivider.test.tsx` | rey (F2) |
| `web/src/App.tsx`, `web/src/App.test.tsx`, `web/src/shell/shell.css` | rey (F3) |
| `web/cypress/e2e/divider.cy.ts` | rey (F4) |
| `spec/openlanes/execution/prompt_spec.rb` | luke (baseline fix, see below) |
| `contract.md`, `pull-requests.md` | luke |

No file is shared. Luke writes nothing under `web/` or `lib/`.

## Build order

F1 → F2 → F3 → F4. B1 (luke) runs after F3: `bundle exec rspec spec/openlanes/web`, then `just web-build`.

## Integration proof

`just web-build && just web-e2e`: the built bundle served by `openlanes web --demo`, a real browser, real `/api`, nothing stubbed. `web/cypress/e2e/divider.cy.ts` (F4) is the divider's proof; the existing specs must stay green.

## Baseline (2026-10-15, before any luke change)

- `bundle exec rspec`: 1 failure, `spec/openlanes/execution/prompt_spec.rb:49`. Cause: `Prompt#cli` shell-escapes `EXECUTABLE`, and this worktree's path holds `━` and `⚪`, so the escaped path no longer equals the raw one the spec expected. Environmental, not a regression; it passes in a checkout with an ASCII path. Fixed in the spec (compare against `Shellwords.escape(EXECUTABLE)`), since `rspec` must exit 0.
- `bundle exec rubocop`: 425 files, no offenses.
- Front-end suites: rey records their baseline (`just web-test`).
