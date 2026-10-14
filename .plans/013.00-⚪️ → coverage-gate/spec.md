---
depends_on: []
---

# Coverage Gate

## What we are trying to achieve

The engine runs the test command from `.openlanes.coverage.yml`, reads the coverage report in one of four formats, and withholds `ok-to-merge` below the minimum.

## Why it matters

Every project keeps about 95% unit test coverage, in any language, and a prompt cannot guarantee that.

## What already exists

- Decision M15 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.

## What research needs to settle

- Parsers for `lcov`, `cobertura`, `istanbul` and `simplecov`, and which figure each reports (lines or statements).

## How to tell it's working?

- Fixture reports in all four formats yield the right percentage.
- A missing report counts as 0% and blocks `ok-to-merge`.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

