---
name: openlanes-setup
description: "Set a project up on openlanes: check the prerequisites, run `openlanes init`, install the skills, and create the first plan. Use when the user wants to set up a new project on openlanes, bring an existing repository onto it, or when a openlanes command exits 66 with no project root."
---

# openlanes-setup: put a project on openlanes

Load the `openlanes` skill first if it is not in context. Read `<command> --help` before using a flag here.

## 1. Prerequisites

Check each, then report every gap at once with its fix. Ask before installing anything system-wide.

| Check | Fix when it fails |
| --- | --- |
| `command -v openlanes && openlanes version` | `gem install openlanes` |
| `git rev-parse --show-toplevel` | offer `git init`; without git, `openlanes run` needs `--isolation shared` and opens no pull request |
| `gh auth status` | `gh auth login`; a "token in GH_TOKEN is invalid" line means `unset GH_TOKEN` and retry |
| the agents' CLI: `command -v claude`, the default adapter, or `codex` / `pi` when the plans' `spec.md` select them per phase | install the CLI the plans use; `openlanes agents list` shows each agent's adapter |
| Redis answers at the URL openlanes will use (order below): `url=$(ruby -ryaml -e 'puts((YAML.safe_load_file(".openlanes.yml") rescue {}).to_h["redis_url"])' 2>/dev/null); redis-cli -u "${url:-${REDIS_URL:-redis://localhost:6379/0}}" ping` | start `redis-server`, or point openlanes at another Redis (below) |

Redis carries the control room, its commands and plan claims. `openlanes start` refuses to run without it (exit 69); `openlanes run` still works, headless, and says so. openlanes looks for it in `--redis-url`, then `redis_url:` in `.openlanes.yml`, then `$REDIS_URL`, then `redis://localhost:6379/0`; `openlanes web` checks `$OPENLANES_REDIS_URL` before all of those but the flag.

## 2. `openlanes init`

Run it at the repository root. Infer values from the repository, say them in one line, and wait for a yes:

- `--project`: the product's name, else the directory name.
- `--lane`: `full` unless the user writes complete specs themselves (`plan`).
- `--[no-]frontend`: `--frontend` when there is a `web/`, `app/javascript/`, `package.json` with a UI framework, or views; `--no-frontend` for a library or CLI; leave it out when plans differ.
- `-j`: leave the default unless the user wants to limit load.

> Project **Acme**, lane **full**, **front end** (a `web/` React app), default jobs. OK?

Then `openlanes init -y <flags> -n` to show the file, and the same without `-n` to write `.openlanes.yml` and create `.plans/`. An existing `.openlanes.yml` is kept unless `--overwrite`.

If the repository has a database and a `CLAUDE.md` or `AGENTS.md`, offer one line there naming its PostgreSQL class (`PG-lax`, `PG-strict` or `PG-analytics`), so every agent assumes the same rules.

## 3. Skills

```bash
openlanes skills install -n                      # what would be installed, kept, replaced
openlanes skills install                         # into ~/.agents/skills
openlanes skills install --into ~/.claude/skills # when the user's agent reads another directory
```

After a gem upgrade, `--overwrite` replaces the copies already there.

## 4. The first plan

Hand off to `openlanes-spec` to create and write the first plan. A new project's first plan is `000.00`. Then:

```bash
openlanes run -n --plan 000
```

and offer `openlanes-run` to start the agents.

## Done when

- [ ] `openlanes status` lists the plan.
- [ ] `openlanes run -n --plan 000` names its first agent.
- [ ] With Redis up, `openlanes web --demo` opens the control room on a sample run (Ctrl-C to stop).
- [ ] `openlanes start` is running: the factory and its control room, up until Stop All Local or Ctrl-C. From here the user works on the page (see `openlanes-run`).
