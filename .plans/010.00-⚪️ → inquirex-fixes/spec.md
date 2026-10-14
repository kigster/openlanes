---
depends_on: []
---

# Inquirex Fixes

## What we are trying to achieve

Fix the inquirex gems in `/Users/kig/github/inquirex` so openlanes can depend on them.

## Why it matters

`lanes init` interviews through inquirex-tty (decision M16), and the published gems cannot be used as they are.

## What already exists

- Decision M17 in `docs/decisions/decisions-on-merge-modes-and-verification.md`, which lists the five problems.
- The gems' own specs and CI (Ruby 4.0.2 only).

## What research needs to settle

- The shape of `Engine#back`, and the key that reaches the program in iTerm and Terminal.app (Cmd-Backspace may not).
- A non-interactive mode: an answers file, `--yes`, results on stdout or `-o`.
- Whether the gems pass their suites on Ruby 4.1.0-preview1.

## How to tell it's working?

- `inquirex`, `inquirex-llm` and `inquirex-tty` at the new versions install together in one bundle.
- A flow can be run with preset answers and no TTY, and its results land on stdout.
- Going back during a TTY run returns to the previous question with its answer filled in.
- No real name or email appears in any README.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

