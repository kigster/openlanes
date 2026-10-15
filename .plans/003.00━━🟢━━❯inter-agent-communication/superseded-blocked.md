# Blocked: rey-frontend, round 1 (technical)

Done: `contract.md` is served by `GET /api/plans/:ordinal/files/:name` (`lib/openlanes/web/app.rb`, spec in `app_spec.rb`).

F1 and F2 name files and surfaces that do not exist in the code. The code wins, and what it needs is a decision outside my files.

- No web plan page or view templates, and no `web.rb:25` file list. The page is a React app (`web/src`) fed by `Live::Snapshot#plan` in `lib/openlanes/live/snapshot.rb` (luke's). Showing a count and a `last-known-state` table means adding keys to the snapshot wire (`Plan`), `web/src/api/types.ts`, both JSON fixtures, and a panel component with vitest tests.

## B1 Where does the unacked count and last-known-state travel to the page?

Options:
1. luke adds `unacked: Integer` and `last_known_state: [...]` to `Snapshot#plan` (his file); I add types, fixtures, a `PlanRow` badge and a detail table in `web/src`, with vitest tests. Recommended: one wire, read-only.

## B2 Is the terminal board in scope?

answers: yes

1. No code paints `Engine::Board` to a terminal here. Should I add `unacked` to `Board`/`Row` as data only (the dispatcher, luke's, would fill it)?

---

B1<1>

B2<1>
