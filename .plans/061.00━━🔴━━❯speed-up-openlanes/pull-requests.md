# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 207 | [\[061.00\](A) Speed Up Openlanes](https://github.com/kigster/openlanes/pull/207) | Open 🟡 |

## Round 1, backend-coder

- Done: B4 (review stage frontmatter), B1 (shared dependency cache for worktrees).
- Remaining: B2, B3, B5, B6.
- `bundle exec rubocop`: no offenses. `bundle exec rspec`: only the 4 baseline routing failures listed in `contract.md`.

## Findings: design-reviewer

### F201 [minor] lib/openlanes/vcs/warmup.rb:145
`Warmup#call` rescues only `SystemCallError, IOError`, and dispatches with `send(kind, ...)` over private methods named after `KINDS` keys. Each kind therefore lives in two places (the table and a same-named method). Scenario: someone adds `pip: {...}` to `KINDS` without a `pip` method → `NoMethodError` escapes `Worktree#checkout_for`, so the "never fatal" promise breaks and the plan cannot start. Prefer putting the strategy (bundler/npm) in the table, as a callable, or a `public_send` guard backed by a spec asserting every KIND has a handler.

### F202 [minor] lib/openlanes/vcs/warmup.rb:160
Private `clone(from, to)` overrides `Object#clone` on `Warmup`. Scenario: `warmup.clone` (or `dup`-based test doubles/`Marshal`) now raises `ArgumentError` (wrong number of arguments) — a surprising name collision. Rename to `clonefile` / `copy_on_write`.

### F203 [minor] lib/openlanes/agents/agent.rb:85
`review_stage` and `watches` are parsed, validated and defaulted (`1` / `[]` is written in both `Agent#initialize` and `Registry.review_stage`/`watches`), but nothing in `lib/` reads them yet (`rg 'watching\?|review_stage'` hits only agent.rb/registry.rb). Scenario: `security-reviewer` says `review_stage: 2`, yet it still runs in the same round as `staff-reviewer`: the frontmatter silently does nothing, the exact failure the registry comment warns about. Acceptable as a first slice only if B2 lands before this ships; and keep the default in one place (the Agent initializer).

### F204 [minor] lib/openlanes/vcs/worktree.rb:99
`warmup: Warmup.new` is the default, so every existing `Worktree.new(..., seeder: nil)` caller (a dozen specs) now warms for real unless it also passes `warmup: nil`. Scenario: a spec whose fixture repo gains a `Gemfile.lock` runs a real `bundle install` into `~/.cache/openlanes/deps`. The `seeder:` opt-out pattern is mirrored, but the safer default is an injected value from the facade (`Vcs.worktree`) rather than a real-side-effect default in the constructor; at least pass `warmup: nil` in the shared spec helpers.

## Findings: security-reviewer

### F101 [minor] lib/openlanes/vcs/warmup.rb:36
`bundle install` and `npm ci` now run in the harness process on every `checkout_for`, on a tree an agent has just edited, outside `Executor`'s `--disallowedTools` and before `Boundary.snapshot`. Scenario: a prompt-injected agent adds `system("git push origin HEAD")` to `Gemfile` (or a `postinstall` to `package.json`) together with a matching lockfile change; the next `checkout_for` (runner, merging, verification) evaluates it unattended, and `Boundary` never sees the push because its snapshot is taken after warm-up. The agent could already do this inside its own run, where `Boundary` at least reports it, so this removes the detection, not the capability. Consider `npm ci --ignore-scripts`, and warming only when the lockfile digest matches the base branch's.

### F102 [minor] lib/openlanes/vcs/warmup.rb:114
Bundler installs straight into the shared entry (`BUNDLE_PATH` → `~/.cache/openlanes/deps/bundler/<digest>`), so every worktree with that lockfile digest, in any project, writes into one directory. Scenario: an agent in plan A overwrites an installed gem's `.rb` file in the cache; plan B's agent, the verifier and the merge-time test run `require` the altered code. `node_modules` is cloned, so npm does not share this. Make the entry read-only after `complete!` (`chmod -R a-w`), or clone it per worktree as npm does.

### F103 [minor] lib/openlanes/vcs/warmup.rb:150
`point_bundler` reads and rewrites `.bundle/config` with `File.write`, which follows symlinks. Scenario: a branch tracks `.bundle/config` as a symlink to a file outside the checkout; the next warm-up overwrites that file with `---\nBUNDLE_PATH: ...`. Skip when `File.symlink?(config)` or when `.bundle` is a symlink.

No critical findings. Dependency check: no gem or npm package added or bumped.

## Answers, round 1 (backend-coder, after 🔴)

| Finding | Answer | Files |
| :-- | :-- | :-- |
| F2 (staff, must fix) | fix: `.bundle/config` is written only when git ignores it, so `git add -A` cannot publish it; otherwise Bundler is skipped with a reason | `lib/openlanes/vcs/warmup.rb` |
| F3 (staff) | fix: `bundle check` runs first; when it passes, nothing is installed (`skipped: "already satisfied"`) | `warmup.rb` |
| F1 (staff, must fix) | not yet: B2, B3, B5, B6 remain, see `contract.md` "Still to build". Signed `Almost completed` | — |
| F101 (security) | fix: a kind is warmed only when every input (`Gemfile`, `Gemfile.lock`, `package.json`, `package-lock.json`) has the same blob as `origin/<default>`; npm runs with `--ignore-scripts` | `warmup.rb`, `worktree.rb` |
| F102 (security) | fix: gems install into the worktree's own `.bundle/openlanes-gems`, and the cache keeps a clone; no worktree writes into the cache | `warmup.rb`, `warmup/kind.rb` |
| F103 (security) | fix: Bundler is skipped when `.bundle` or `.bundle/config` is a symlink | `warmup.rb` |
| F201 (design) | fix: kinds are `Warmup::Kind` rows (inputs, target, check, install, env); no `send`, and `call` rescues `StandardError` | `warmup/kind.rb`, `warmup.rb` |
| F202 (design) | fix: `clone` renamed `copy_on_write` | `warmup.rb` |
| F203 (design) | partly fixed: still unread by `lib/` until B5 lands, which is still to build | — |
| F204 (design) | fix: `Worktree.new` defaults to `warmup: nil`; only the `Vcs.worktree` facade injects `Warmup.new` | `worktree.rb`, `vcs.rb` |

- `bundle exec rubocop`: no offenses (851 files).
- `bundle exec rspec`: 3104 examples. The failures are the 4 routing baseline failures plus `redis_outage_integration_spec.rb:72,:100`, which use a live Redis and pass when run alone (flaky, not in a file this plan touches). `architecture_doc_spec` is green after `just update-architecture`.

## Round 2, backend-coder

- Done: B2 (`GitHub#open_pull_snapshot`, `Vcs::PullSnapshot`, shared `Vcs::Buckets`, two-page GraphQL fixture under `spec/fixtures/github/`).
- Remaining for staff F1: B3, B5 (also closes F203), B6.
- `bundle exec rubocop`: no offenses (854 files). `bundle exec rspec spec/openlanes/vcs`: 303 examples, 0 failures.
- Full suite: 4007 examples. Failures: `dispatcher_spec.rb:523` (routing baseline), `redis_outage_integration_spec.rb:100` (live Redis, flaky), and `run_workflow_spec.rb:115,:226`, which also fail on a clean detached checkout of HEAD 9c5bb259, so they come from HEAD and not from this change.

## Round 3, backend-coder

- Done: B5 core. `Reviews#startable?` and `#stage_two`, an early decision on a stage-1 rejection, and the `Dispatcher#eligible?` gate. Six new examples in `reviews_spec.rb`, including restart. `review_stage` and `watches` are now read by `lib/` (F203).
- Remaining: wire `changes:` to `git diff --name-only` in `RunWorkflow`, the dispatcher spec for B5, then B3 and B6.
- `bundle exec rubocop`: no offenses. Full suite: 3818 examples. Every failure listed is a known baseline (routing x3, dispatcher:523, run_workflow:115/:226, redis_outage:100).

## Round 4, backend-coder

- Done: B5 wiring. `Vcs::Changes` (git diff in the plan's worktree) is passed into `Reviews` by `RunWorkflow#reviews_for`. Specs: `spec/openlanes/vcs/changes_spec.rb`, plus two staged examples in `dispatcher_spec.rb` (staff alone first; a staff rejection skips stage 2).
- Remaining for staff F1: B3, B6.
- `bundle exec rubocop`: no offenses (856 files). `bundle exec rspec`: 3110 examples, 3 failures, all `routing_spec.rb:19,:32,:42` (baseline). The process overran the 330 s shell timeout after printing its summary, so its exit code was the timeout's.

## Round 5, backend-coder

- Done (B3, part): `Steps::Snapshot`, `POLL = 10`, `Context#snapshot`, PrWatch on the snapshot, `Vcs::SnapshotReads` (labels and checks from the snapshot, refreshed on every write) wired into Merging and Verification, and a row in `docs/thread-safety.md`. Specs: `steps/snapshot_spec.rb`, `vcs/snapshot_reads_spec.rb`, and two snapshot examples in `pr_watch_spec.rb`.
- Remaining: the `pull_request` reads in `merging.rb` and `upkeep/sweep.rb`, then B6.
- `bundle exec rubocop`: no offenses (860 files). `bundle exec rspec`: 4142 examples. Failures: `run_workflow_spec` x3 (baseline), and `cli/web_spec.rb:255,:277` plus `cli/engine_command_spec.rb:289,:317`. Those four come from an OpenLanes admin-login variable in this shell's environment: credentials come back as user "kig" where the spec expects none. The thread-safety inventory failure from this round is fixed.

## Round 6, backend-coder

- Done (B3, rest): `Vcs::SnapshotReads#pull_request` now answers from the snapshot row whenever the pull request is open there. The GraphQL query adds `headRefOid baseRefName body mergeStateStatus mergeCommit`, and `PullSnapshot.details` fills in `head body merge_state base merge_commit`. A merged pull request is never in the snapshot, so it is still read live, and that read is what carries its merge commit. `Upkeep.keeper` gets `snapshot_github`, so `Sweep#ask` reads from the snapshot as well.
- Specs: `snapshot_reads_spec.rb` has a `#pull_request` group. `merging_spec.rb` has "reads the pull request from the tick's snapshot, with no gh pr view". The page1 fixture node 201 carries the new fields.
- Remaining: B6, the integration spec.
- Targeted runs: `merging_spec:96`, `pull_snapshot_spec`, `snapshot_reads_spec` and `engine/upkeep` give 48 examples, 0 failures. Rubocop is clean on the touched paths. I did not run the full suite this round: about 19 rspec processes from other agents were sharing the machine.
