---
depends_on: ["011", "014"]
---

# Stack Ports

## What we are trying to achieve

Porting a project to another stack: a generated "Port from X to Y" plan, both apps running side by side, parity checks by the verifier, and a final plan to retire the old code that always goes to the human.

## Why it matters

Some projects are a move from one language or framework to another, and a rewrite without parity checks is taken on faith.

## What already exists

- Decision M18 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.

## What research needs to settle

- Generating the port plan and its units from leah's inventory of the old code.
- Comparing outputs from two running apps.

## How to tell it's working?

- A small Flask app ported to Go passes parity on every unit, and the retirement plan waits for the human.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

