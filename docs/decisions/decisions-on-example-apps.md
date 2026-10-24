# Decisions on example apps and the project overview

Decided 2026-10-24, with Konstantin. The goal: a person can make a fresh project from a template, `cd` into it, run `ol start`, and watch the factory build an app.

## E1. Examples live in one `openlanes-examples` repository, copied out by `ol new`

- One repository, `kigster/openlanes-examples`, holds every template as a top-level folder plus an index `README.md`. Revised the same day: the first draft put them in `examples/` here.
- Why not this repository: a template's `.plans/` would be found by `Project.root`, `resync` and the Linear export as if it were ours; Swift, Cargo and Rails toolchains would land in the gem's CI; and templates would be tied to gem releases.
- `ol new --example <name> <dir>` makes a shallow, sparse clone, copies the one folder out, runs `git init` and `ol init -y`. With `--github` it asks first and then runs `gh repo create`, so pull requests and merges work end to end. Without it, the run is local (`--no-git-push`). `ol new --example` with no name lists the templates.
- Each template carries a `.openlanes-template` marker, and `ol start` refuses to run where it finds one: agents running in the examples checkout would branch and rewrite the templates themselves. `ol new` drops the marker when it copies.
- Each template names the minimum openlanes version it needs; `ol new` warns when the installed gem is older.
- The examples repository has its own CI, one job per template (a macOS runner for `macos-clipboard`).
- Rejected: `examples/` in this repository (above); one GitHub template repository per app, which means one repository per template to keep current; and running in place, which leaves a built example to clean before it can run again.

## E2. Four templates

| Template | Stack | App |
| --- | --- | --- |
| `macos-clipboard` | Swift, SwiftUI, built with `swift build` (SwiftPM) | Clipboard history in the menu bar |
| `rust-logtail` | Rust | `logtail`: a CLI that follows and filters JSON logs |
| `rails-habits` | Ruby on Rails | Habit tracker with streaks |
| `astro-blog` | Astro, TypeScript, static output | A markdown blog: posts, tags, RSS |

- Each template ships a `README.md`, `.plans/APPLICATION.md` and a skeleton that compiles.
- `astro-blog` is the front-end-only case: `frontend: true`, no back end, so plans route to rey-frontend alone and its checks are a static build plus Playwright against the built site. Astro over Next.js because its default output is static files with no server; Next.js pulls in server components and API routes, which blur "front end only".
- The macOS app needs Xcode, and chewie cannot run a GUI headless, so verification for it is manual.

## E3. Each template ships seed plans

- A few ⚪ plan folders, each with its `spec.md`, so `ol start` has work to do the moment it runs.

## E4. `.plans/APPLICATION.md`: the project overview

- One per project: what the app does, its goals, and its non-goals. The non-goals are what keep agents within scope.
- Uppercase like `INDEX.md`, the other project-level file in `.plans/`.
- It only matters if agents read it, so it is put into the prompts of the agents that write and plan (leah, yoda, palpatine) rather than left for them to find. That prompt change waits for the dry-rb refactor of the executor.

## E5. `.plans/BACKLOG.md`: candidates that are not yet plans

- Detailed items, typically what a grilling session produces from `APPLICATION.md`.
- An item becomes a plan through `ol create --from-backlog <item>`, which mints the ⚪ folder and removes the item from `BACKLOG.md`. Each idea lives in exactly one place at any time: nothing is written down twice.
- Rejected: keeping a promoted item with a link to its plan, which leaves two places to read its status from; and turning every item into a plan automatically.

## E6. Overview to backlog is its own plan

- A grilling step that reads `APPLICATION.md` and writes `BACKLOG.md`, plus the promotion command in E5. Separate from the templates, which do not depend on it because of E3.

## E7. Every project has a documented starting point

- [`docs/STARTING-AN-APP.md`](../STARTING-AN-APP.md) walks from an empty directory, or an example, to `ol start`, marking the steps not built yet. The README's Quick Start links to it.
- [`docs/application-template.md`](../application-template.md) is the shape of `APPLICATION.md`: what it is, goals, non-goals, stack and constraints, and what done looks like. `ol init` writes it to `.plans/APPLICATION.md` when the file is missing (plan 048.00).
- Every example's `README.md` follows the guide: what the app is, what to install, how to build and run it, and `ol start`. The guide is the one source for the steps, so the template READMEs link to it rather than restating them.

## E8. Anyone can contribute a template for their stack

- `openlanes-examples` takes pull requests for new templates. Its `CONTRIBUTING.md` holds the checklist a template must pass: the README shape from E7, an `APPLICATION.md` from the template with real non-goals, a skeleton that builds on a clean machine, two or three ⚪ seed plans, the `.openlanes-template` marker, a minimum openlanes version, and a CI job.
- `ol new --example` lists whatever folders the repository holds, so a merged template needs no change to the gem.
- A template that fails its CI job for two releases is moved to `unmaintained/` rather than kept broken in the list.
