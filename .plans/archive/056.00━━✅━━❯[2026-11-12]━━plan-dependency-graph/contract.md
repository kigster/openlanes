# Contract: Plan Dependencies (056.00)

Owner: backend-coder. Partner: frontend-coder.

## Baseline

7 failures at `4fcb6eb2`, reproduced on a clean worktree of HEAD: routing_spec.rb:19,32,42; dispatcher_spec.rb:523; run_workflow_spec.rb:115,226,[1:2:6]. All caused by the repo `.openlanes.yml` (`frontend: true`, `desired_codebase_quality: high`) leaking into the suite through `Config.current`. See blocked.md B1.

## HTTP surface

`GET /api/dependencies` → `200 application/json`. Read-only, no CSRF, no params. Schema: `openapi.yaml` beside this file.

```
{
  "states": [{ "key": "new", "emoji": "🆕", "name": "New", "archived": false }, ...],  // every Status in STATUSES order; name = Status#label
  "plans":  [{ "ordinal": "056.00", "title": "Plan Dependency Graph",
               "state": "building", "summary": "…", "archived": false }, ...],
  "edges":  [{ "from": "055.00", "to": "056.00" }, ...]
}
```

- `states[].archived` (amended: review finding F202, 2026-11-13): true for a state whose plans live in an inactive subfolder, derived from `Plans::Tree::INACTIVE_DIRS` (today `approved`, `deployed`, `deferred`, `abandoned`, `discarded`, `trashed`). The page's filter takes its off-by-default set from this flag and keeps no list of its own; the Cypress test reads the same flag rather than naming the states.
- `plans`: every plan folder in `.plans`, the inactive subfolders (`archive`, `deferred`, `abandoned`, `discarded`, `trashed`) included, in `Tree#features` order (open first, then subfolders, by number within each). `archived` is true for any plan in a subfolder. `state` is a key present in `states`.
- `summary`: the spec's `summary:` frontmatter key when set; else the first prose paragraph under `## What we are trying to achieve`; else the spec's first prose paragraph; `""` when there is none or no spec.md. Never null.
- `edges`: one per `depends_on:` entry, `from` = dependency, `to` = dependent. An entry naming a plan the tree does not hold is left out (no box to point at). `[none]` yields no edges. Sorted by `to`, then `from`.
- Errors: none specific. A missing `.plans` answers `200` with `plans: []`, `edges: []`.

## File ownership

| Files                                                                                  | Owner          |
| -------------------------------------------------------------------------------------- | -------------- |
| `lib/**`, `agents/*.md`, `docs/WORKFLOW.md`, `spec/**`, this file, `openapi.yaml`      | backend-coder  |
| `web/**` (incl. `web/package.json`, `web/cypress/**`)                                  | frontend-coder |

No shared files. The Cypress fixture `.plans` under `web/cypress/fixtures/` is frontend-coder's.

## Build order

B1 (`summary:`) → B2 (`/api/dependencies`). F2 builds against the shape above, not B2's code. F4 needs B2 landed.

## Integration proof

`web/cypress/e2e/dependencies.cy.ts` (F4): the real Sinatra server over a fixture `.plans`, nothing stubbed, asserts boxes, arrows, the Done filter, the dashed bridge and the hover summary. Ruby side: `spec/openlanes/web/app_spec.rb` `GET /api/dependencies` over a real `PlansFixture` tree.

- amended: `states[]` entries carry `archived: boolean` (true when the state's plans live in a `Tree::INACTIVE_DIRS` subfolder). The page starts with those unchecked instead of a copied list (F202). Front end reads it as of round 3; back end to add it.
