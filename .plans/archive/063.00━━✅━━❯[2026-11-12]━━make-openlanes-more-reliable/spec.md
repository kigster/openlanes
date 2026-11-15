---
created: 2026-11-10
starts: planning
depends_on: [none]
task-completed-when:
  - "`web/cypress/e2e/keyboard.cy.ts` passes 20 runs in a row on CI"
  - "A commit that changes `lib/openlanes/version.rb` without the matching `Gemfile.lock` fails the suite"
  - "`lefthook.yml` runs rubocop on staged Ruby files and refuses a commit whose `lib/` change leaves `docs/architecture/` stale"
---
# Make Openlanes More Reliable

## What needs to be done

- Fix the flaky keyboard.cy.ts model-picker test: it failed #195 yesterday on a PR with no web changes.
- Regenerate Gemfile.lock in the version-bump recipe: main says 4.0.0 under a 4.0.1 gem.
- Run just update-architecture in the pre-commit hook when lib/ changes; that is what broke #196.

## What we are trying to achieve

CI that fails only when the change is wrong, and local hooks that catch what CI would.

## Why it matters

Each of these cost a red pull request in the week of 2026-11-03, and none was caused by the pull request it failed.

## What already exists

Checked against `main` on 2026-11-10.

- **Flaky test.** CircleCI job 2249 on #195: "the arrow keys never reached Opus 5.5; focus is on ✓Sonnet 5.5", at `keyboard.cy.ts:136`. The test sends keys through `Input.dispatchKeyEvent` and already retries up to 12 times; commit `a1d292c1` was an earlier attempt to make it deterministic. Twelve arrow presses moved focus nowhere, so the keys were not reaching the listbox at all, which is a different fault from the off-by-one the retry loop guards against.
- **Lockfile.** There is no version-bump recipe. `justfile` reads the version from `lib/openlanes/version.rb`; `Gemfile.lock` on `main` still says `openlanes (4.0.0)` under a 4.0.1 gem, so every `bundle` run dirties it in every checkout.
- **Hooks.** `lefthook.yml` was copied from another project: its `rubocop` and `rspec` jobs have `root: "rails/"` and `format` has `root: "frontend/"`, directories this repository does not have. Every commit prints "rubocop (skip) no files for inspection". Only `gitleaks` runs.
- **Architecture docs.** `spec/openlanes/docs/architecture_doc_spec.rb` fails when `docs/architecture/` is stale, which is how #196 went red after a merge from `main`.

## Notes for whoever builds this

- Lockfile: a spec beside the architecture one that compares `Gemfile.lock`'s `openlanes (x.y.z)` with `OpenLanes::VERSION` catches it wherever the version is edited; a `just bump` recipe that edits the version and runs `bundle install` prevents it.
- Hooks: fix the roots first (rubocop on `{staged_files}` with `--force-exclusion`, biome or eslint under `web/`), then add the architecture job with `glob: "lib/**/*.rb"`, running `just update-architecture` with `stage_fixed: true`.
- A hook does not cover a merge from `main` done on GitHub. The `linter` CI job should also fail fast on stale docs, so the cause is named in seconds, not after the whole suite.
- Also seen on 2026-11-09, once, and not reproduced in four reruns: `spec/openlanes/engine/redis_outage_spec.rb:37` failed with "can't modify string; temporarily locked" from `Live::Store#call`, which reads as one Redis connection shared by two threads.

## How to tell it's working?

- bundle exec rspec spec/openlanes/docs
- cd web && npx cypress run --spec cypress/e2e/keyboard.cy.ts
