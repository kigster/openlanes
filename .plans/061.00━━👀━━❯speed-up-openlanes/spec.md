---
created: 2026-11-10
starts: planning
depends_on: [none]
task-completed-when:
  - "A new plan worktree for a project with a JavaScript lockfile starts with its dependencies installed, without a full install per worktree"
  - "One GitHub request per poll returns the state, labels and checks of every open pull request the engine watches"
  - "A review round whose first rejection is known does not spend tokens on verdicts that can no longer change the outcome"
---
# Speed Up Openlanes

## What we are trying to achieve

Make things faster, and stop doing things that are slow but can be done in bulk.

## Why it matters

Speed of software development is one of the metrics a Software Factory is judged on.

## What needs to be done

- Pre-warm worktrees. 
  - **A fresh worktree "has never run bundle install"; either keep a pool of seeded ones, or share vendor/bundle and node_modules.**
- **Replace 30sec gh polling (Steps::POLL, verification's 15sec) with one batched GraphQL query for all open PRs.**
- Review in two stages. 
  - **Run staff-reviewer first and start security and design only if it passes, or only when the diff touches paths they care about.**

## What already exists

Checked against `main` on 2026-11-10.

- **Worktrees.** `Vcs::Worktree` creates the checkout and runs the user's own `setup-worktree` script, which copies ignored files (`.env`, credential keys) and installs nothing. Correction to the item above: for Ruby there is nothing to pre-warm, because gems live in the rbenv Ruby and are shared by every worktree; `bundle check` passes at once in a fresh one. The real cost is JavaScript: `web/node_modules` is absent, and `just web-install` runs `npm ci` per worktree. The same is true of any target project with a `package.json`.
- **Polling.** `Vcs::GitHub` shells out to `gh` once per pull request and per question (`checks`, `labels`, `pull_request`, `review_comments`). `Engine::Steps::Sweeps` and `Steps::Merges` each run at most once per `Steps::POLL` (30 s), and `Engine::Verification::Driver::INTERVAL` is 15 s. There is no GraphQL call anywhere.
- **Review.** `Engine::Reviews` waits for every reviewer, then labels. Decisions V1 to V8 in `docs/decisions/decisions-on-agent-names-models-and-reviewers.md` fix this: an odd number of reviewers (V5), one rejection rejects (V4), a failed reviewer is replaced, never skipped (V6), and `deploy-assessor` starts alongside the reviewers (V8).

## Notes for whoever builds this

- Pre-warming: `git worktree add` then a copy-on-write clone of the main checkout's `node_modules` (`cp -c` on APFS, `cp --reflink=auto` on Linux) is near-instant and safe; a symlink is faster but lets one worktree's install change another's. Skip it when the lockfile differs from the main checkout's.
- Polling: one `gh api graphql` query can return `state`, `labels`, `mergeable` and `statusCheckRollup` for all open pull requests. Keep the per-call methods as the fallback and as the seam the suite already doubles.
- Review in two stages changes recorded decisions. Skipping security or design by path breaks V5's odd count. Running `staff-reviewer` first adds one reviewer's wall-clock time to every approval. Since one rejection already rejects (V4), the cheaper change is to keep all three in parallel and stop the others on the first rejection.
- Plan 060.00 changes how a review round starts (packet, gate). Build this after it.

## Decisions needed

- Which review change: stop the rest on the first rejection, run `staff-reviewer` first, or leave review as V1 to V8 decided it. Stopping early loses the other reviewers' findings for that round, and `review-vulnerability` when security had not yet reported.

## How to tell it's working?

- bundle exec rspec spec/openlanes/vcs spec/openlanes/engine/steps spec/openlanes/engine/reviews_spec.rb
