# Decisions on openlanes skills, `--dry-run`, project root and `.openlanes.yml`

Decided 2026-10-12, in a grilling session with Konstantin.

## 1. Skills ship with the gem

- `skills/` in this repository replaces the old `skills/openlanes-factory/`, which was the `create-plan` skill renamed, with templates pointing at `~/.agents/lib/spec_plan_build`.
- Five skills: an umbrella `openlanes` (what the factory is: states, lanes, agents, which sibling to load) and four job skills:
  - `openlanes-spec`: create a plan, choose its lane and depth, write the implementation frontmatter.
  - `openlanes-run`: run the agents to a fixed point, handle blocked plans.
  - `openlanes-status`: list plans, the index, a plan's `state.json` and mailbox.
  - `openlanes-sync`: `resync dirs`, `resync prs`, `linear import`.
- Lane and depth: the agent proposes one with a line of why, and the user confirms. Ask outright only when the call is unclear.
- Installed through `agentilda-ai-setup`'s `configuration.yml`, never from an interactive session.

## 2. `--commit` is gone; `-n` / `--dry-run` replaces it

The global CLI rule says a command does the work it is named for. Every command that took `--commit` now does the work when run and takes `-n` / `--dry-run` for the preview: `run`, `unblock`, `resync dirs`, `resync prs`, `linear import`.

- `OPENLANES_AUTOCOMMIT` is removed; it existed only to undo the dry-run default.
- `linear import --force` becomes `--update-unchanged`, per the rule against `--force`.
- `run` asks no confirmation. The `openlanes-run` skill previews with `-n` unless the user has already said to run.

## 3. The project root

Every command that reads or writes a project finds its root first and `chdir`s there:

1. Walk up from the current directory and take the nearest one holding `.openlanes.yml` or a `.plans/` directory.
1. Failing that, the nearest one holding `.git` (a directory, or a file in a worktree).
1. `$HOME` is never a root unless it holds `.openlanes.yml`; a dotfiles repository in `$HOME` must not capture every project under it.
1. Nothing found: refuse, exit 66.

When the root is not the current directory, print one line on STDERR naming it (silenced by `-q`). `-D` and `PLANS_DIR` resolve against the root. Commands that need no project (`version`, `states`, `docs`, `agents`, `describe`, `completion`, `eval`) skip the search.

## 4. `.openlanes.yml` replaces `~/.local/config/openlanes.json`

```yaml
project: Equilibris App   # heading for INDEX.md and similar; default: the root's directory name
lane: full                # default lane for `openlanes create`: full | plan | quick
frontend: false           # project default for a spec's `frontend:`; omit to let each plan decide
jobs: 4                   # how many plans `openlanes run` works on at once
commands:                 # per-command option defaults, what openlanes.json used to hold
  run:
    timeout: 1800
```

- Precedence: CLI flag > the plan's `spec.md` frontmatter > `.openlanes.yml` > built-in default.
- `jobs` at the top level and `commands.run.jobs` are the same fact; setting both is an error, not a tie-break.
- An unknown key or a bad value is an error naming the file, the same stance the JSON config took: a config silently ignored is a timeout that stops applying with no signal.
- The user-level JSON file is no longer read.
- `openlanes init` writes the file at the root (the nearest `.git`, else the current directory) and creates `.plans/`. It prompts for the four values on a TTY and takes them as flags (`--project`, `--lane`, `--[no-]frontend`, `--jobs`). `-y` / `--yes` skips the prompts, `-n` previews, and an existing file is kept unless `--overwrite` is given.

## 5. `openlanes skills install`

`openlanes skills install [--into DIR]` copies the gem's bundled `skills/*` into `DIR`, default `~/.agents/skills` (the shared skill store that `~/.claude/skills` links into).

- Copies, never symlinks: a link into the gem's versioned install path dangles after `gem cleanup`. Re-run after upgrading the gem.
- A skill directory already at the destination is kept unless `--overwrite` is given; the report lists installed, kept, and replaced.
- `-n` / `--dry-run` previews. Needs no project root.
- The gemspec ships `skills/**/*`.
- `openlanes skills install -h` lists every bundled skill: its name, the first sentence of its `description`, and whether it is already installed at the default destination. The list is read from `skills/*/SKILL.md` frontmatter when help renders, so a new skill appears without editing the command.

## 6. Seven skills: `openlanes-start` and `openlanes-documents` join the five

Decided 2026-10-13.

- `openlanes-start` walks a project onto openlanes: prerequisites (openlanes, git, `gh`, `claude`, Redis), `openlanes init`, `openlanes skills install`, the first plan.
- The leftover `skills/openlanes-factory/` draft is reworked into `openlanes-documents`: what each file in a plan folder is for, the formats the code parses (B1/A1, spec frontmatter, `pull-requests.md`, the retroactive provenance line), and templates matching what `openlanes create` and the agents write.
- Renamed because the umbrella `openlanes` skill already calls itself the software factory; a second skill with "factory" in its name would compete for the same trigger while covering something narrower. "Documents" names what it covers.
- Which state requires which file is never copied into a skill; they point at `openlanes docs` and `openlanes states`.
- 2026-10-13, later: `openlanes-start` is renamed `openlanes-setup`. It is about setting a project up, and `openlanes start` is now the command that runs the factory with its control room. `openlanes-run` documents that command, and `openlanes-setup` ends with it running.
