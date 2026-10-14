# Blocked: 010.00 inquirex-fixes

Asked by luke-backend, 2026-10-13. Technical.

## B1 Two inquirex gems have uncommitted Ruby 4.1 work. Where should 010 branch from?

The units say "branch `kig/010.00-inquirex-fixes` in each repository" under `/Users/kig/github/inquirex`. All three repositories are on `kig/migrate-to-ruby-4-1`, and two hold uncommitted work that is not this plan's:

- `inquirex-llm`: modified `.github/workflows/main.yml`, untracked `.ruby-version`
- `inquirex-tty`: modified `.github/workflows/main.yml`, untracked `.ruby-version`

Branching in those checkouts would either carry that work into this plan's branch or mean stashing someone else's changes, which no agent will do. No code has been written yet.

a) **Recommended.** Use a git worktree in each gem for 010, branched from `main`, and leave the current checkouts alone.
b) Same worktrees, but branched from `kig/migrate-to-ruby-4-1`, because Ruby 4.1 support should ship in 0.11.0. You commit the migration work first.
c) Branch from `kig/migrate-to-ruby-4-1` in the existing checkouts and carry the uncommitted changes along.
d) Type something instead
