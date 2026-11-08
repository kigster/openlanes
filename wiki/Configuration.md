<!-- generated-by: bin/wiki-gen -->

# Configuration

_Finding the project root, `openlanes init`, and every key in `.openlanes.yml`._

**Up:** [Getting Started](Getting-Started.md)

______________________________________________________________________

## Finding the project root

Every command that reads or writes plans first finds the project root and works from there, so it does not matter which subdirectory you type it in. The search, nearest first:

1. a directory holding `.openlanes.yml` or `.plans/`;
1. failing that, a directory holding `.git`.

Your home directory counts only if it holds `.openlanes.yml`, so a dotfiles repository there cannot capture every project under it. When the root is not where you are, one line on STDERR says so (`-q` silences it); when there is none, the command exits 66. `-D` and `PLANS_DIR` resolve against the root. `version`, `states`, `uml`, `docs`, `agents`, `describe`, `completion`, `eval` and `skills` need no project and skip the search.

## `openlanes init`

Writes `.openlanes.yml` at the nearest `.git` (else the current directory) and creates `.plans/`. It takes `--project`, `--starts`, `--[no-]frontend` and `--jobs`, asks on a terminal for whatever no flag gave, and confirms before writing. `-y` asks nothing, `-n` prints the file instead, an existing file is kept unless `--overwrite`, and `--no-setup` skips the machine check that otherwise runs `openlanes setup` first.

## `.openlanes.yml`

```yaml
project: Demo App         # heading for INDEX.md; default: the root's directory name
starts: research          # default for `openlanes create`: research | planning | building
frontend: false           # a spec's `frontend:` when spec.md says nothing; omit to let each plan decide
jobs: 4                   # how many plans `openlanes run` works on at once
adapter: codex            # claude (default) | codex | pi | grok | gemini: the coding agent for every agent that names none
review:
  adapters: [claude, codex, gemini]  # deal the reviewers across these, main one first; default: adapter:
redis_url: redis://localhost:6379/0   # the Redis the live run shares
commands:                 # option defaults for any command, by the name you type it as
  run:
    timeout: 1800
  resync prs:
    adopt: false
```

- Precedence, highest first: a typed flag, the plan's `spec.md` frontmatter, `.openlanes.yml`, the built-in default.
- `jobs`, `starts` and `project` are the same settings as `commands.run.jobs`, `commands.create.starts` and `commands.index.project`. Set either spelling, not both.
- An unknown key, a bad value, or an option the command does not take is an error naming the file (exit 65). A setting silently ignored is a timeout that stops applying with no signal.
- `dry_run` cannot be a default.
- `review.adapters` deals `staff-reviewer`, `security-reviewer` and `design-reviewer` to the first, second and third coding agent, wrapping when there are fewer. A coding agent the board's probe found unusable is skipped. A reviewer's own `adapter:` or the plan's `phases.review` still wins.
- A reviewer that crashes, times out or ends without a verdict runs its round again, once, on the main coding agent (`adapter:`, else claude), and that verdict counts as its own. Its stage in `state.json` records `replaced_by`. A reviewer a person stopped is not replaced.

<sub>Lifted verbatim from [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md).</sub>

## Configuration

- **`.openlanes.yml`** at the project root: `project`, `lane`, `frontend`, `jobs`, `redis_url`, `redis_outage_hours`, `ci_pending_hours` (how long CI may stay pending after verification before the run warns a person, 4 by default; a plan with several open pull requests waits on CI for each, and one built from another branch than the plan's is not run through the coverage gate, so its CI config alone gates it), `desired_codebase_quality`, `merge`, `ci`, `stack`, and per-command defaults under `commands:`. A typed flag beats `spec.md` frontmatter, which beats `.openlanes.yml`, which beats the built-in default. Unknown keys are an error.
- **`spec.md` frontmatter**: `lane`, `frontend`, `depth`, per-phase `adapter` / `model` / `effort`, `implementation_suggestions`, `implementation_requirements`, `task-completed-when`, `how-to-verify`.
- **`PLANS_DIR`**: the plans directory, `.plans` by default.
- **A lost Redis** does not stop the run. After 10 seconds without an answer every agent is paused through its control file (its clock stands still), nothing new starts, and the outage is recorded in `.plans/openlanes-state.json`. Redis is asked again after 1, 1, 2, 3, 5, 8 … seconds, never more than 30 seconds apart, each gap drawn at random below that (full jitter) so engines sharing one Redis do not ask in step; `redis_backoff:` in `.openlanes.yml` changes the three (`initial: 1`, `cap: 30`, `jitter: true`). When it answers, the agents resume. If it has not answered within `redis_outage_hours` (1 by default, any positive number), the run shuts down the way `q` does. On resume the log says how long Redis was gone and which copy of the run state won, e.g. `Redis is back after 72s (by heartbeat), run state from file; resuming`: the length comes from this node's last heartbeat in Redis, or from the engine's own clock when Redis came back without one, and the run state from whichever of Redis and `.plans/openlanes-state.json` has the higher `seq`. The board page shows the same as `run.outage`, and warns while the engine has not published for more than 15 seconds. A Redis that restarts empty (no AOF, an old RDB snapshot) does not stop the run either: the engine makes its commands group again (issue #59).
- **`events:`** in `.openlanes.yml`: `enabled` and `dir` for the opt-in durable run log, read back with `openlanes events report`. See [`docs/events.md`](Durable-Run-Events.md).

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md)
- [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md)
