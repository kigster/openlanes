---
created: 2026-10-24
starts: research
depends_on: ["045.00", "048.00"]
---

# Ol New Application Generator

## What we are trying to achieve

`ol new <appname>` creates the directory, runs `git init`, the `ol init` interview, then an application grilling agent that writes `.plans/APPLICATION.md` and `.plans/BACKLOG.md`, offers to mint the first plans, and prints `cd <appname> && ol start` (A14). `--application FILE` starts from an existing overview, `--example <name>` copies a template, `--github` asks then runs `gh repo create`, `-y` skips the grilling. `ol start` in a folder with no `.openlanes.yml` offers the same steps in place. `new` stops being an alias of `create`.

## Why it matters

Starting an app from nothing is the first thing a new user tries, and today it needs a hand-written spec.

## What already exists

`Live::Interviewer` (029.00) asks questions with recommended answers; `ol init` and `Setup::Interview`; the `new` alias of `create` in `cli.rb`; plan 048.00 for APPLICATION.md and BACKLOG.md; `ol setup` owns tools and `gh` auth (A15).

## What research needs to settle

Needs its own short grilling for the application grilling agent: its name, prompt and handoff to the backlog.
