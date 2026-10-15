# Blocked

## B1 How the coverage fixes reach main

PR #38 was merged into `main` (8165d25) at 2026-10-15T15:56Z with `ci/circleci: test` and `ci/circleci: web` red, before this rejection round ran. The worktree's local branch `kig/012.00-app-runner-and-preview` (70cb1ea) is the pre-rebase history, not the remote tip that merged (02e0982), so the harness's push would be refused as non-fast-forward, and would land on a merged pull request's branch even if it went through. The fixes are uncommitted in the worktree: `spec/openlanes/cli/app_spec.rb` (luke-backend) and `web/src/preview/useApps.ts` plus `useApps.test.tsx` (rey-frontend). All three files are identical on `main` apart from these changes, so they apply cleanly there.

a) Branch again from `origin/main`, carry the three files across, and open a new pull request that turns `main`'s CI green. (Recommended)
b) Reset the worktree branch onto `origin/main`, keep the three files, and let the harness push it as a new pull request under the same branch name.
c) Drop the fixes and leave `main` as merged.

## A1

So switch to that worktree, rebase onto main, and push a PR

Answered by kig on 2026-10-15
<!-- cmd:01M5056XRHX66AYA1F9JZYENE7 -->
