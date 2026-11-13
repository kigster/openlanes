# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 234 | [\[056.00\](A) Plan Dependency Graph](https://github.com/kigster/openlanes/pull/234) | Open 🟡 |

## backend-coder, round 1

- `bundle exec rspec`: 5949 examples, 8 failures; 7 pre-existing at `4fcb6eb2` (blocked.md B1), 1 (`architecture_doc_spec.rb:13`) fixed by `just update-architecture` and rerun green.
- `bundle exec rubocop`: 849 files inspected, no offenses.
- `docs/WORKFLOW.md` is not tracked in this repository, so the regenerated copy was not added; `openlanes docs` lists `summary:` (documentation_spec).

## backend-coder, round 3 (after the Redis race question was answered: ship as is, race fixed in PR #206)

- `bundle exec rubocop`: 851 files inspected, no offenses.
- `bundle exec rspec spec/openlanes/web/dependency_graph_spec.rb spec/openlanes/web/app_spec.rb spec/openlanes/plans/spec_spec.rb spec/openlanes/presentation/documentation_spec.rb spec/openlanes/checkout_config_spec.rb spec/openlanes/agents/routing_spec.rb`: 216 examples, 0 failures.
- Full `bundle exec rspec`: had not finished after 11 minutes, with another agent's rspec running on the same machine. That fits the `Live::Store` Redis race that PR #206 fixes, but this round did not confirm it. Not run to completion this round.
- Cypress (`web/cypress/e2e/dependencies.cy.ts`) not run this round.

## Frontend integration proof, round 1

- `npx vitest run` (Node 22): 56 files, 553 tests pass. Node 26 from Volta breaks `localStorage` in jsdom; environmental.
- `npm run typecheck` and `npx eslint .` in `web/`: clean.
- `npm run build`, then `bin/web-e2e` limited to `cypress/e2e/dependencies.cy.ts`: 4 passing, 0 failing. Fix made on the way: the filter's off-by-default keys were `done`, which is not a real state; now the archived states (`approved`, `deployed`, `deferred`, `abandoned`, `discarded`, `trashed`).
- `bundle exec rubocop`: 851 files, no offenses.
- `bundle exec rspec`: see the signing note; backend-coder reported flaky Live::Store Redis specs outside this plan.
- Correction: the full `bundle exec rspec` did finish: 5952 examples, 5 failures, 7 pending.
  - `spec/openlanes/live/redis_outage_integration_spec.rb:100`: the `Live::Store` race (PR #206).
  - `spec/openlanes/cli/web_spec.rb:255,277` and `spec/openlanes/cli/engine_command_spec.rb:289,317`: the shell had `OPENLANES_ADMIN_CREDENTIALS` set. `env -u OPENLANES_ADMIN_CREDENTIALS bundle exec rspec spec/openlanes/cli/web_spec.rb spec/openlanes/cli/engine_command_spec.rb` gives 84 examples, 0 failures. The suite does not clear that variable, so these 4 fail on any machine that sets it.
- `bundle exec rspec`: 4 failures, none in this plan's files, coverage 99.18%. `redis_outage_integration_spec.rb:72` is the flaky Live::Store race backend-coder reported. `cli/web_spec.rb:255`, `:277` and `cli/engine_command_spec.rb:317` read the admin credentials (`user="kig"`) and a LAN address from the checkout's uncommitted `.openlanes.yml`, the same leak backend-coder's `spec/support/checkout_config.rb` fixes for other specs. A reviewer should run them on a clean checkout.

## Answers, round 4 (backend-coder, after 🔴 Changes Requested)

PR #234 carries no inline review comments (`gh api repos/kigster/openlanes/pulls/234/comments` is empty) and no review bodies, so the findings below are answered here.

- F202 (back-end part): fix. Each entry in `states` now carries `archived: boolean`, derived from `Plans::Tree::INACTIVE_DIRS` through `Tree.subfolder_for`, in `lib/openlanes/web/dependency_graph.rb`; asserted in `spec/openlanes/web/dependency_graph_spec.rb`. `contract.md` and `openapi.yaml` amended; frontend-coder mailed (#9) to take the filter's default and the Cypress expectations from the flag. The front-end part (`useStateFilter.ts`, `dependencies.cy.ts`, the orphan doc comment) is frontend-coder's.
- F205: fix. `lib/openlanes/web/app.rb` goes through `Plans.tree(dir)`. `DependencyGraph` no longer reaches `Plans::Spec`, `Plans::Dependencies` or repeats the basename test: it asks `tree.dependencies`, the new `Subject#summary` (`lib/openlanes/plans/subject.rb`) and the new `Tree#inactive?(feature)` (`lib/openlanes/plans/tree.rb`), the latter built on the same `group` that orders the tree. Covered in `spec/openlanes/plans/tree_spec.rb` and the graph spec. `docs/architecture/` regenerated.
- F206: rebuttal. This pull request does not change `.openlanes.yml`: `gh pr diff 234 --name-only` does not list it, and `git diff main -- .openlanes.yml` on the branch is empty. The file on `main` already holds two `coverage:` blocks (lines 8 and 79, from commits `8d09f7c7` and `884d644a`); that duplication predates plan 056 and belongs in its own change, which is what the finding asks for.
- F201, F203, F204: frontend-coder's half; mailed to them in #9.

## Findings: design-reviewer

### F201 [critical] web/src/dependencies/DependenciesPage.tsx:1
Spec item 2 and G1 require React Flow (`@xyflow/react`) with draggable boxes, zoom and pan. The diff hand-rolls an SVG plus absolutely positioned buttons over dagre and drops `@xyflow/react` (jsdom measuring was the stated reason). Scenario: open `/dependencies`, drag a box or scroll to zoom: nothing happens, and a graph wider than the viewport has no pan. The page also owns edge geometry (`out`/`into`, `at.get(o)!`) that a graph library would own, so the next change to routing or interaction lands in the page component.

### F202 [minor] web/src/dependencies/useStateFilter.ts:6
The set of states hidden by default is a hand-copied list (`approved, deployed, deferred, abandoned, discarded, trashed`) of what `Plans::Tree::INACTIVE_DIRS` already derives, and it is copied again twice in `web/cypress/e2e/dependencies.cy.ts`. Adding an archived state in `status.rb` leaves the page showing it by default and the Cypress expectations silently wrong. The endpoint should send a per-state flag (e.g. `archived`/`default`) derived from `INACTIVE_DIRS`. The file also carries a stray orphan doc comment ("Off until asked for") stacked on the real one.

### F203 [minor] web/src/api/dependencies.ts:20
`useDependencies(stamp)` puts the board's plan signature into the query key, and `App.tsx` builds that stamp. Scenario: a plan moves on the SSE stream, the key changes, `data` is undefined for the new key, and the page swaps the whole graph for "Loading plan dependencies…" (pinned tooltips and layout lost); every move also leaves another cache entry. The refetch trigger belongs in one place (`invalidateQueries(DEPENDENCIES_KEY)` where the board snapshot is consumed), not as a prop threaded through `App`.

### F204 [minor] web/src/App.tsx:366
`App` now owns routing, the stamp computation and a `display: contents/none` wrapper around the board, whose JSX was not re-indented (file is 431 lines). Page selection belongs in a small `Pages`/shell component so `App` stays the board's host.

### F205 [minor] lib/openlanes/web/app.rb:193
Reaches `Plans::Tree.new(dir:)` although `Plans.tree(dir)` is the facade (`plan_files.rb:131` uses it). `DependencyGraph` also reaches `Plans::Spec`, `Plans::Dependencies` and re-derives "is in an inactive subfolder" from `Tree::SUBFOLDERS` (`inactive?`), a fact `Tree` already computes when ordering (tree.rb:146); ask the tree rather than repeating the basename test.

### F206 [minor] .openlanes.yml:75
The diff adds a `coverage:` block to the repo's `.openlanes.yml`, unrelated to this plan (no unit owns it, and the plan's B1 is about the suite ignoring this file). Move it to its own change.

## Findings: design-reviewer

### F201 [critical] web/src/dependencies/DependenciesPage.tsx:1
Spec item 2 and G1 require React Flow (`@xyflow/react`) with draggable boxes, zoom and pan. The diff hand-rolls an SVG plus absolutely positioned buttons over dagre and drops `@xyflow/react` (jsdom measuring was the stated reason). Scenario: open `/dependencies`, drag a box or scroll to zoom: nothing happens, and a graph wider than the viewport has no pan. The page also owns edge geometry (`out`/`into`, `at.get(o)!`) that a graph library would own, so the next change to routing or interaction lands in the page component.

### F202 [minor] web/src/dependencies/useStateFilter.ts:6
The set of states hidden by default is a hand-copied list (`approved, deployed, deferred, abandoned, discarded, trashed`) of what `Plans::Tree::INACTIVE_DIRS` already derives, and it is copied again twice in `web/cypress/e2e/dependencies.cy.ts`. Adding an archived state in `status.rb` leaves the page showing it by default and the Cypress expectations silently wrong. The endpoint should send a per-state flag (e.g. `archived`/`default`) derived from `INACTIVE_DIRS`. The file also carries a stray orphan doc comment ("Off until asked for") stacked on the real one.

### F203 [minor] web/src/api/dependencies.ts:20
`useDependencies(stamp)` puts the board's plan signature into the query key, and `App.tsx` builds that stamp. Scenario: a plan moves on the SSE stream, the key changes, `data` is undefined for the new key, and the page swaps the whole graph for "Loading plan dependencies…" (pinned tooltips and layout lost); every move also leaves another cache entry. The refetch trigger belongs in one place (`invalidateQueries(DEPENDENCIES_KEY)` where the board snapshot is consumed), not as a prop threaded through `App`.

### F204 [minor] web/src/App.tsx:366
`App` now owns routing, the stamp computation and a `display: contents/none` wrapper around the board, whose JSX was not re-indented (file is 431 lines). Page selection belongs in a small `Pages`/shell component so `App` stays the board's host.

### F205 [minor] lib/openlanes/web/app.rb:193
Reaches `Plans::Tree.new(dir:)` although `Plans.tree(dir)` is the facade (`plan_files.rb:131` uses it). `DependencyGraph` also reaches `Plans::Spec`, `Plans::Dependencies` and re-derives "is in an inactive subfolder" from `Tree::SUBFOLDERS` (`inactive?`), a fact `Tree` already computes when ordering (tree.rb:146); ask the tree rather than repeating the basename test.

### F206 [minor] .openlanes.yml:75
The diff adds a `coverage:` block to the repo's `.openlanes.yml`, unrelated to this plan (no unit owns it, and the plan's B1 is about the suite ignoring this file). Move it to its own change.

## Answers, round 3 (frontend-coder, after 🔴)

No PR line comments exist; the findings live above. Fixes in my half:

- F201 fix: `web/src/dependencies/DependencyFlow.tsx` draws the graph with `@xyflow/react` (drag, wheel zoom, pan, Controls); `PlanNode` is a React Flow node, `PlanEdge`/`BridgeEdge` custom edges; `flow.ts` maps the visible graph to nodes/edges; dagre keeps the layout in `model.ts`. jsdom shims for React Flow in `web/src/test/setup.ts`.
- F202 fix: `useStateFilter` takes the states and unchecks those the server flags `archived`; the copied list is gone from the hook and from `cypress/e2e/dependencies.cy.ts`. `DependencyState.archived` added to types and `contract.md` (amended); backend-coder mailed to add the field.
- F203 fix: one query key (`DEPENDENCIES_KEY` in `queryClient.ts`); `useBoard` invalidates it on each board snapshot; `useDependencies()` takes no stamp, so the old graph stays while it refetches.
- F204 fix: `web/src/shell/Pages.tsx` owns the nav, the route and the hidden board wrapper; `App` is the board's host again, re-indented.
- F205, F206: backend-coder's half (`lib/`, `.openlanes.yml`).

Checks this round: `npm run typecheck`, `npx eslint .` clean; `npx vitest run` 60 files, 601 tests pass (Node 22); `bundle exec rubocop` 952 files, no offenses. Not run this round (time budget): full `bundle exec rspec` and Cypress `dependencies.cy.ts` against the demo, which needs the `states[].archived` field from the back end.

## Integration proof, round 4 (backend-coder, last coder)

- `env -u OPENLANES_ADMIN_CREDENTIALS bundle exec rspec`: 6403 examples, 0 failures.
- `bundle exec rubocop`: 952 files inspected, no offenses detected.
- `cd web && npm run build`: built in 6.84s.
- `CYPRESS_specPattern=cypress/e2e/dependencies.cy.ts bin/web-e2e`: 4 tests, 3 passing, 1 failing. Passing: nav with no reload and refresh stays put; one box per plan and one arrow per edge; archived plans appear when Approved is checked. Failing: the hover/bridge tooltip case, `AssertionError: Timed out retrying after 8000ms: Expected to find element: .dep-tip, but never found it`. That selector is in frontend-coder's React Flow rewrite (F201, this round); `GET /api/dependencies` answered every request and the back end is unchanged by it. Mailed frontend-coder (#11).
