<!-- generated-by: bin/wiki-gen -->

# Writing a Spec

_The `spec.md` frontmatter a plan is driven by, and the template it starts from._

**Up:** [Getting Started](Getting-Started.md)

______________________________________________________________________

## `spec.md` frontmatter

Every key is optional:

```yaml
---
starts: building     # research (default) | planning | building
frontend: false      # true forces frontend-coder; false keeps it out
depth: fast          # fast | medium | deep: the default effort for every phase
phases:              # per-phase overrides: research, specification, planning,
  build:             # build, frontend, review, unblock
    adapter: codex   # claude | codex | pi | grok | gemini; default: the agent's own, then (reviewers) .openlanes.yml review.adapters, then adapter:, then claude
    model: gpt-5-codex
    effort: medium   # low | medium | high | xhigh | max
  review: { model: opus }
implementation_suggestions:   # text or a list: language, libraries, an approach
  - Ruby, with dry-cli for the command line
implementation_requirements:  # text or a list: binding, exactly as written
  - The database is PG-strict
task-completed-when:          # what must be true for the task to be finished
  - "`openlanes create` opens an editor and writes no draft"
how-to-verify:                # the commands or checks that show it
  - bundle exec rspec spec/openlanes/cli/create_spec.rb
---
```

- **`implementation_suggestions`** is advice. Every agent is shown it as "suggestions from the spec's author", prefers it when it fits, and may take a better route as long as it writes why in the document it owns.
- **`implementation_requirements`** is binding. An agent that cannot meet one signs `Blocked` instead of substituting its own, and `staff-reviewer` rejects work that does not meet them. Agents start without your personal skills (`run --user-config` restores them), so write the rule itself, not the name of a skill that holds it.
- **`task-completed-when`** and **`how-to-verify`** are copied into `plan.md` under `## Task completed when` and `## How to verify`. After a planner signs, the harness appends whichever section is missing and never touches one that is there. No agent signs `Completed` until the first holds, every agent runs each check in the second, and the reviewer rejects work that fails one.

Model and effort precedence, highest first: `run --model` (model only), `phases.<phase>`, `depth` (effort only), the agent's own frontmatter. The adapter has the last word: a Claude agent asked for anything above Opus runs on Opus.

Adapter precedence, highest first: `phases.<phase>.adapter`, the agent's own `adapter:`, `.openlanes.yml` `adapter:`, `claude`. An agent names an adapter only when it depends on one (the verifier needs Claude's browser tools). An agent confined to its own files, such as `spec-keeper`, runs only on claude: codex, pi, grok and gemini cannot hold it there, so it is refused on them rather than run unconfined. Grok and gemini do refuse the forbidden commands themselves (grok through `--deny`, gemini through a policy file passed with `--policy`), and both run without web search or fetch unless the agent declares `network: true`. Gemini has no effort flag, so a phase's `effort:` does not reach it. Its own model is kept only on the adapter its frontmatter wrote it for, so a project on codex does not ask codex for `opus`.

Whether each adapter can take an agent on this machine is probed, never assumed: installed (on `PATH`), signed in, and with a model to run (`claude auth status`, `codex login status`, `pi --list-models`, `grok models`, `gemini -p ""` with nothing on stdin, which checks the sign-in and exits for want of input; no prompt reaches a model). The engine and the page each probe at start and every 15 minutes, one at a time per machine, and share the answer through Redis, and every snapshot the page reads carries it, the reason included. `openlanes agents list` probes there and then and prints an Adapters table under the roster: available or why not, what it can do, how many models it offers.

The control room's New idea dialog sets `phases.<phase>.adapter` and `.model` without editing YAML: one row per phase the plan will walk from its Starts, each with an adapter and a model select. Agent's default writes nothing. An adapter that cannot take an agent on this machine is listed disabled, with the reason. A car's model picker lists the models of the adapter that car runs on, and is disabled, with the reason, when that adapter is down.

## Lanes

| Lane    | Route                                                                                                                         | For                                                                                       |
| :------ | :---------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------- |
| `full`  | researcher → spec-writer → planner → backend-coder (+ frontend-coder) → staff-reviewer (+ security-reviewer, design-reviewer) | features you want researched and specified                                                |
| `plan`  | planner → backend-coder (+ frontend-coder) → staff-reviewer (+ security-reviewer, design-reviewer)                            | a spec you already trust: the harness writes a blank `plan.md` and moves the plan to 📋   |
| `quick` | chores-coder → staff-reviewer                                                                                                 | a short mechanical task: the harness writes a one-unit `plan.md` and moves the plan to ⭐ |

`openlanes create --starts building split big migration` writes the frontmatter for you.

<sub>Lifted verbatim from [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md).</sub>

## The spec template

### What we are trying to achieve

### Why it matters

### What already exists

### What research needs to settle

<sub>Lifted verbatim from [`docs/spec-template.md`](https://github.com/kigster/openlanes/blob/main/docs/spec-template.md).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md)
- [`docs/spec-template.md`](https://github.com/kigster/openlanes/blob/main/docs/spec-template.md)
