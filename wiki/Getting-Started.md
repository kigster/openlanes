<!-- generated-by: bin/wiki-gen -->

# Getting Started

_Install OpenLanes, point it at a project, and start the factory._

**In this section:** [Starting an App](Starting-an-App.md) · [Configuration](Configuration.md) · [Writing a Spec](Writing-a-Spec.md) · [Running the Factory](Running-the-Factory.md) · [The Control Room](The-Control-Room.md) · [CLI Commands](CLI-Commands.md) · [Bundled Skills](Bundled-Skills.md)

______________________________________________________________________

## Quick Start

```bash
brew tap kigster/tap
brew install openlanes

# cd into your project directory, which can be nearly blank or can be an established codebase
ol setup      # downloads dependencies, ensures your `gh` is authenticated or runs `gh auth login -w`
ol init       # interactively creates the configuration file .openlanes.yml for project specific settings
ol start -j 8 # number of concurrent processes allowed
```

New project, or starting from an example app? [`docs/STARTING-AN-APP.md`](Starting-an-App.md) walks through every step, including `.plans/APPLICATION.md`.

This starts all the parts, and it's recommended to start this inside a `screen` or a `tmux` session that survives your terminal disconnecting.

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

## Manual Install

Requirements:

| Need                                                           | Why                                                                                               |
| :------------------------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| Ruby 3 or newer                                                | the gem; this repository is developed on Ruby 4                                                   |
| [`claude`](https://docs.anthropic.com/en/docs/claude-code) CLI | the default agent adapter; `codex`, `pi`, `grok` and `gemini` are optional alternatives per phase |
| `git`                                                          | one worktree and branch per plan (`--isolation shared` needs no git)                              |
| [`gh`](https://cli.github.com/), signed in                     | pushing branches, opening pull requests, `resync prs`                                             |
| Redis                                                          | the control room (`start`, `web`); `run` falls back to headless without it                        |

```bash
gem install openlanes agent-lock agent-evals -N
ol --help
ol skills install    # copy the bundled skills into ~/.agents/skills (-n to preview)
echo 'eval "$(ol completion zsh)"'  >> ~/.zshrc  # or bash; add to your shell rc
echo 'eval "$(ol completion bash)"' >> ~/.bashrc # for bash; add to your shell rc
```

[`agent-lock`](https://github.com/kigster/agent-lock) (`alock`) lets several agents share one checkout without overwriting each other's files.

`skills install` copies rather than links, so re-run it with `--overwrite` after upgrading the gem.

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

## Usage

Run these anywhere inside your project:

```bash
ol setup
ol init                    # .openlanes.yml and .plans/ at the project root; -y asks nothing
ol create tax rule dsl     # .plans/000.00━━⚪━━❯tax-rule-dsl/spec.md, drafted and opened
                                  # finish the brief in spec.md and save it
openlanes run 001 -n              # dry run: which agent would take plan 001
openlanes start                   # engine plus control room on http://127.0.0.1:11000
openlanes status                  # what is up; `openlanes stop` stops it, `start --background` detaches it
openlanes plans              # every open plan, its state and its pull requests; --all adds archived ones
```

`openlanes start` runs until you press **Stop Local Workers** on the page, Ctrl-C, or run `openlanes stop`; it restarts the engine or the page if either crashes. Answer the agents' questions under **Needs You**, create new plans, and watch the board. For scripts and CI, `openlanes run 001,002` works just those plans, headless, and stops at the first round in which none of them changed state; `--until planned` stops them earlier.

`init` scans the repository, then asks about what it holds now and what you want it to become, with what it found preselected and yours to change. The first question is how much detail you want to give: low, medium or high ask about 10, 15 or 21 topics, from layout, languages, task runner, how the app starts and how development secrets are kept, down to search and observability. Most questions take several answers. It then asks who merges a reviewed pull request (`human` or `auto`) and the desired codebase quality (`high` or `mvp`). The answers are written under `architecture_decisions:` in `.openlanes.yml`, the agents read them from there, and CI you asked for and the folder lacks is scaffolded. The stack is also written to `docs/decisions/stack.md`.

If something can read it, `init` also asks you to describe the app, and preselects what the description states. It tells you where the description goes before asking. It uses the first of: a `claude`, `codex`, `pi`, `grok` or `gemini` CLI that is signed in, however it authenticates, in a read-only mode; `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `XAI_API_KEY`, `GEMINI_API_KEY` or `OPENROUTER_API_KEY`; a local Ollama. With none of them it asks every question. `OPENLANES_EXTRACTION_MODEL` picks the model.

The form is an [Inquirex](https://github.com/inquirex/inquirex) definition in `lib/openlanes/setup/project_form/dsl.rb`, so the same questions can be generated as JSON for `inquirex-webui` and `inquirex-widget`.

```bash
openlanes init -y --ci github_actions --merge-by auto --quality mvp   # ask nothing, no network
openlanes init --reconfigure      # ask again with the current answers as defaults; shows the diff first
openlanes init --reconfigure -n   # the diff only, nothing written
```

Under `-y` it records what the scan found, never a recommendation; the defaults are `--merge-by human` and no `desired_codebase_quality` (the first review-passed review asks it). A folder with two languages gets no `docs/decisions/stack.md`.

> [!NOTE]
> `.openlanes.yml` files written by this release can hold `architecture_decisions:`. An older openlanes refuses that key as unknown, so upgrade every machine that reads the file. A file with `ci:` or `stack:` still reads, and `init --reconfigure` moves them over.

For a small mechanical task, skip research and planning:

```bash
openlanes create --starts building split big migration
```

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

## Running OpenLanes via mprocs

If you want to see how OpenLanes runs and what it logs, you can drop this `mprocs.yml` file in the root of your repo, and use `mprocs` command to start OpenLanes. The Ruby Gem sources comes with one, but it's not distributed as part of the gem package. The gem souces are available [on Guthub](https://github.com/kigster/openlanes).

```yaml
---
# `just start`: the engine, its API server and the page, all from this
# checkout. The page is Vite's dev server on 5173, not the built web/dist,
# so an edit to a .tsx or .css file is recompiled and pushed to the open
# page at once; Vite proxies /api to the API server on 11000.
#
# Everything lands in log/development.log: the engine and the API server
# through SemanticLogger, in colour here though the gem's default is plain,
# and bin/ol-tee adds Vite and what the API server prints itself. The
# engine is not piped, so its pane keeps its live board.
procs:
  engine: ol start -j 4 --no-web --log-format color
  api: bin/ol-tee api bundle exec exe/openlanes web --no-open --log-format color
  # npm ci again whenever package-lock.json is newer than what is installed.
  web: bin/ol-web
  logs: tail -F log/development.log
```

You write a short feature brief; a team of specialist coding agents researches it, specifies it, plans it, builds it and reviews it, until it is a set of reviewed, CI-passing pull requests. You merge. Every feature is a folder under `.plans/`, and the folder's name is its state. The gem installs three names for the same executable: `openlanes`, `lanes` and `ol`.

![The openlanes control room](https://github.com/kigster/openlanes/raw/main/docs/img/openlanes-control-room.avif)

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md)
