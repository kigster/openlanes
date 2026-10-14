# Decisions on a shared lock for tests and the linter

Date: 2026-10-13. Asked by kig.

## Why

With several plans built in parallel worktrees, every agent finishes by running `rspec` and `rubocop`, and they all do it at once. The runs compete for the CPU, for the shared PostgreSQL and Redis, and for the coverage output, and the results are unreliable.

## Decisions

### D1. Tests and the linter run one at a time across the whole repository

`openlanes exclusive -- <command>` runs a command while holding one `alock` lock shared by every worktree of the repository. The lock lives in the main checkout (the parent of `git rev-parse --git-common-dir`), so worktrees take the same lock.

- **Waits without a timeout.** A second agent waits until the lock frees, printing who holds it and for how long every 30 seconds on STDERR.
- **Always released.** The lock is released in an `ensure` when the command passes, fails, raises or is interrupted.
- **Transparent.** It exits with the command's own exit status and passes its output through.
- **Holder names the plan.** The holder is `<agent>@<ordinal>` (`luke-backend@003.00`), not the bare agent name. Agents today sign locks with their bare name (`lib/openlanes/execution/prompt.rb`), so two plans' luke-backends count as one holder and never block each other.
- **Agents are told to use it.** The agent prompt says to run the test suite and the linter only through `openlanes exclusive`, with a long Bash timeout. If the tool call times out while waiting, run it again.
