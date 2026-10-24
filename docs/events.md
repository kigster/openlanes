# Durable run events

OpenLanes can keep an append-only record of what its runs did: which agents ran, which finished, which blocked, how long a human took to answer, what happened to each pull request, and what each agent used. Redis stays the live view; this is what is left after a run ends or Redis is flushed.

It is **off by default**. Nothing is created, and no directory is made, until you turn it on.

## Configuration

In `.openlanes.yml` at the project root:

```yaml
events:
  enabled: true
  dir: /var/lib/openlanes/events   # optional, absolute
```

- `enabled`: `true` or `false`. Anything else is an error. Absent means off.
- `dir`: an absolute path (a leading `~` is expanded). A relative path is an error, because it would land wherever the command was typed.

Without `dir`, the log lives outside the repository, so `git status` and the autonomy boundary never see it:

```
${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<6 hex of sha256(root)>/events/
```

A relative `XDG_STATE_HOME` is ignored, as the XDG specification says. This default follows plan 021.00 (run state out of `.plans/`); if that plan settles elsewhere, one method (`Events::Location.dir`) changes.

## Reading it

```bash
openlanes events report                 # table
openlanes events report --format json   # for scripts
openlanes events report -o report.txt   # to a file
```

The report gives completion rate, blocks and the runs that needed feedback, time to answer, PR outcomes, and usage per adapter and model. A computed cost carries an `(est.)` label. A cost the log could not price (codex and pi report none) reads `unknown`, never `$0`. Usage is never summed across adapters, because they count tokens differently.

## Events

Each line of a `<node>.jsonl` file is one event: `event_id`, `kind`, `at`, `project`, `plan`, `run`, `agent`, `adapter`, `model` and a `payload`. A payload may hold only the keys its kind allows; building an event with any other key raises.

| Kind             | Payload keys                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `run_started`    | `jobs`, `isolation`                                                                                |
| `run_finished`   | `rounds`, `changed`                                                                                |
| `agent_started`  | `round`, `invocation_start`                                                                        |
| `agent_finished` | `round`, `invocation_start`, `status`, `duration_s`, token counts, `cost_usd`, `estimated`, `incomplete` |
| `block_raised`   | `round`, `invocation_start`, `blocks`                                                              |
| `human_answered` | `round`, `block`, `answered_at`                                                                    |
| `pr_opened`      | `number`                                                                                           |
| `pr_reviewed`    | `number`, `verdict`                                                                                |
| `pr_merged`      | `number`                                                                                           |
| `pr_closed`      | `number`                                                                                           |
| `failure`        | `round`, `invocation_start`, `error_class`                                                         |

## What is never stored

Code, prompts, transcripts, conversation text, the text of an answer, and `total_cost_usd`. The only free string is a failure's `error_class`, cut to a short length.

## Multiple machines

- **One writer per file.** Each node appends only to its own `<node>.jsonl`. Nodes never write each other's files, so there is nothing to lock.
- **Late arrival.** A node that was offline contributes its file when it comes back. The report reads every file in the directory, so a late file is simply read with the rest.
- **Nothing is rewritten.** Lines are only appended. `event_id` is a SHA-256 of the node, checkout, plan, round, agent, invocation and kind, so the same event seen twice, from a restart or a copied file, counts once.

To combine machines, copy or sync their `*.jsonl` files into one directory and point `events.dir` at it.
