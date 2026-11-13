# Contract: 061.00 Speed Up Openlanes

No front end in this plan (`## Frontend` has no units), so backend-coder owns every unit and there is no interface for frontend-coder to call.

## Baseline (before any change, clean HEAD 4fcb6eb2)

- `bundle exec rspec`: 4 order-dependent failures, none in files this plan's units change:
  - `spec/openlanes/agents/routing_spec.rb:19`, `:32`, `:42` (reproduced on a clean detached worktree of HEAD)
  - `spec/openlanes/engine/dispatcher_spec.rb:523` (same routing cause: "no front-end units" still routes frontend-coder)
- `bundle exec rubocop`: 0 offenses.

## Interfaces landed

- `Agents::Agent#review_stage` (Integer, default 1), `#watches` (Array of globs, default []), `#watching?(files) -> Boolean` (true when `watches` is empty; otherwise any file matches a glob, `**` crossing directories).
- `Agents::Registry` refuses `watches:` unless `phase: review`, and `review_stage` other than 1 or 2.
- `Vcs::Warmup.new(cache:, installer:)`, `#call(path) -> Warmup::Result(installed:, shared:, failures:)`, `.digest(lockfile)`, `#entry_for(kind, lockfile)`. `installer` is `(kind, dir, env) -> Boolean`.
- `Vcs::Worktree.new(..., warmup: Warmup.new)`; `warmup: nil` warms nothing. Warm-up runs after `seed` on both paths of `checkout_for`; failures are logged, never raised.

## Warmup (B1), amended

amended: after review (F2, F3, F101–F103, F201–F204). Each kind installs into the worktree (`.bundle/openlanes-gems`, `node_modules`) and the cache keeps a clone. Nothing is installed when an input differs from `origin/<default>`, when git does not ignore the target or `.bundle/config`, when that config is a symlink, or when `bundle check` already passes. npm runs with `--ignore-scripts`. `Warmup#call(path, base:)` returns `Result(installed, shared, skipped, failures)`. `Worktree.new` warms nothing by default; `Vcs.worktree` injects `Warmup.new`.

## Pull snapshot (B2), built

`GitHub#open_pull_snapshot(repo: nil, clock:) -> Vcs::PullSnapshot`: one `gh api graphql` call per 100 open pull requests, following `pageInfo.endCursor`. Raises `OpenLanes::Error` ("could not read open pull requests: …") on a `gh` failure or bad JSON. `PullSnapshot(pulls, taken_at)`: each row is `GitHub.row`'s shape (`number title url branch files state open labels`) plus `checks:` (`{name:, bucket:}`, from `Vcs::Buckets`, which `GitHub#branch_checks` now uses too). Readers: `#[](n)` (nil when not open), `#checks(n)`, `#labels(n)` (both empty when not open), `#numbers`.

## Staged review (B5), built

`Reviews.new(agents:, review:, changes:)`: `changes` is `(subject) -> Array<String>, nil`; nil (the default) means every stage-2 reviewer watches. `Reviews#startable?(agent, subject)`: stage 1 always, stage 2 only after every stage-1 reviewer passed this round and `Agent#watching?(changes)`. `#stage_two(subject, notes)`. `#decide` decides at once on a stage-1 rejection or slop; otherwise pending is stage 1 plus watching stage 2. `Dispatcher#eligible?` asks `startable?`. amended: wired. `RunWorkflow#reviews_for` passes `Vcs::Changes.new(worktree:)`, which runs `git -C <plan worktree> diff --name-only origin/<default>...HEAD` with no network and answers nil when there is no checkout or git fails. A shared-tree run passes nil, so every stage-2 reviewer watches. `dispatcher_spec` shows that staff-reviewer runs alone first and that a staff rejection never starts stage 2.

## Still to build

B3 (snapshot consumers, `POLL = 10`), B5 (staged review round in `reviews.rb` and `dispatcher.rb`), B6 (integration spec).
