# Decisions on agent names, models per coding agent, and reviewers

Started 2026-10-25 by the owner (kig), grilling session, one question at a time. Supersedes the reviewer roster of R1 in [decisions-on-three-reviewers-and-auto-merge.md](decisions-on-three-reviewers-and-auto-merge.md) where they disagree; the comment format of R2 stands unless a decision below changes it.

## Status

Settled 2026-10-25, after a grilling session. Not built yet.

## Names

### N1. Agents are named by their purpose

The Star Wars names go. Every agent is named for what it does.

| Was                         | Now                 |
| :-------------------------- | :------------------ |
| `leah-researcher`           | `researcher`        |
| `yoda-writer`               | `spec-writer`       |
| `luthen-rael-planner`       | `planner`           |
| `luke-backend`              | `backend-coder`     |
| `rey-frontend`              | `frontend-coder`    |
| `r2d2-mechanic`             | `chores-coder`      |
| `hansolo-reviewer`          | `staff-reviewer`    |
| —                           | `security-reviewer` |
| —                           | `design-reviewer`   |
| `chewie-verifier`           | `verifier`          |
| `lando-broker`              | `unblocker`         |
| `bb8-resolver`              | `rebaser`           |
| `obi-wan-kenobi-arbitrator` | `arbitrator`        |
| `palpatine-risk-assessor`   | `deploy-assessor`   |
| `c3po-operator`             | `copilot`           |

Settled 2026-10-25. `rebaser` resolves the conflicts that stop a rebase onto `origin/main`. `deploy-assessor` decides whether a PR that passed review may be merged by the engine unattended, or needs a person.

### N2. An agent's name is a constant, never a string literal

`OpenLanes::Agents::Names` holds one constant per agent, and code refers to agents only through it. The web UI takes names from the API and never spells one out. Renaming an agent is then one constant, one `agents/*.md` file, and prose.

When this was decided, `lib/` spelled a name as a string in 12 places; two were already constants (`Engine::Rebase::RESOLVER`, `Verification::Outcome::AGENT`).

### N3. Old names are rewritten once, in this repository only

No other project runs on openlanes yet, so there is no runtime migration and no alias table. The rename PR rewrites the old names in this repository's `.plans/**` (`state.json`, ledgers, journals) in the same change, and nothing reads an old name afterwards.

## Coders

### C1. Both coders build to SOLID

`backend-coder` and `frontend-coder` are told, in any language:

- SOLID design principles;
- small files;
- one responsibility per class, module or component;
- implementations that are easy to swap: depend on an interface or an injected collaborator, not on a concrete class.

## Models per coding agent

### M1. Each agent lists its default models per coding agent

When the main coding agent is not claude, each agent's models are mapped to that coding agent's. For each agent: coding agent → models, most preferred first. The run picks the first model the chosen coding agent offers (from the startup probe of plan 040.00).

The map lives in each agent's frontmatter, and nowhere else:

```yaml
models:
  claude: [opus]
  codex: [gpt-5-codex]
  grok: [grok-4.7]
  gemini: [gemini-2.5-pro]
```

`openlanes agents models` prints the whole map as one YAML document. A separate YAML file was rejected: it would say the same thing twice.

## Init interview

### I1. The interview asks only about coding agents that are installed and signed in

The startup probe of plan 040.00 runs first.

### I2. It asks for the main coding agent

Saved as `adapter:` in `.openlanes.yml` (the project default of plan 040.00). When it is not claude, every agent runs on its `models:` entry for that coding agent (M1).

### I3. It asks whether to review with several coding agents, and which

Only when more than one is available. The list, main coding agent first, is saved in `.openlanes.yml` and drives V7.

## Arbitration

### A1. A person gets 60 seconds to override the arbitrator

When `arbitrator` rules, the control room shows its ruling before it takes effect:

- a description of the dispute;
- the options it weighed, with its own choice preselected in green;
- a countdown from 60 seconds, and a `+` button that adds another minute each time it is pressed.

Untouched when the countdown ends, the arbitrator's choice stands. Picking another option and confirming overrides it. With no control room running, the ruling takes effect at once.

## Reviewers

### V1. Three reviewers, ideally each on a different coding agent

| Agent               | Looks for                                                                                                                                  |
| :------------------ | :----------------------------------------------------------------------------------------------------------------------------------------- |
| `staff-reviewer`    | A Staff Engineer at Google's level, fluent in front end and back end: correctness, readability, runtime failures, performance.             |
| `security-reviewer` | Vulnerabilities and other security holes.                                                                                                  |
| `design-reviewer`   | Code organisation and systems design: SOLID in an object-oriented codebase, small files, single responsibility, swappable implementations. |

Different coding agents catch different things, so where several are available each reviewer runs on its own.

### V2. Reviewers comment on the PR and report a verdict; the dispatcher labels

Each reviewer leaves its comments on the PR and reports one overall verdict back to the dispatcher that started it. Only the dispatcher attaches labels.

| Verdict                    | Label             |
| :------------------------- | :---------------- |
| great                      | `review-approved` |
| ok, but not great          | `review-passed`   |
| rejected, with the reasons | `review-rejected` |

`review-passed` replaces R3's `review-ok-not-perfect`, keeping its colour `E8E890`. The startup label sync renames the label on each repository, so every PR that carries it keeps it under the new name.

### V3. The dashboard shows each verdict with the coding agent's mark

A tiny mark of the coding agent that reviewed sits beside its verdict: our own neutral glyph, a letter in the vendor's colour, not the vendor's logo. Vendor logos are trademarks with their own brand terms; they can replace the glyphs later, once those terms are checked (R5), without a code change.

### V4. The label is the majority verdict, but one rejection rejects

Once every reviewer has reported:

1. any `rejected` → `review-rejected`, and `review-vulnerability` beside it when `security-reviewer` found an exploitable hole;
1. otherwise the majority: at least two `great` of three → `review-approved`; otherwise `review-passed`.

The reviewers' own verdicts decide the label; R3's pooled emoji count (more than five 🤔) no longer does.

### V5. Always an odd number of reviewers, set by where the plan starts

| `starts:`              | Reviewers |
| :--------------------- | --------: |
| `building`             |         1 |
| `planning`, `research` |         3 |

An odd count means the majority of V4 never ties.

A `starts: building` plan is reviewed by `staff-reviewer` alone.

### V6. A reviewer that fails is replaced by the main coding agent, not blocked

Blocking is avoided wherever possible. When a reviewer crashes, times out or ends without a verdict, the main coding agent (I2) runs the same reviewer with the same prompt in its place, and its verdict counts as that reviewer's. The label still waits for every reviewer, so V4 never decides from an even count.

### V7. Reviewers are dealt across the chosen coding agents

`.openlanes.yml` keeps the list chosen in the interview (I3), main coding agent first. Each run assigns the reviewers to it in order: `staff-reviewer` to the first, `security-reviewer` to the second, `design-reviewer` to the third, wrapping when there are fewer. With one coding agent all three run on it, with different prompts. A reviewer's own `adapter:` frontmatter, or the plan's `phases.review`, overrides the dealing (precedence of plan 040.00).

### V8. `deploy-assessor` runs alongside the reviewers

It starts with them on the same PR, instead of after `verifier`.

- It never votes in V4, so the reviewer count stays odd.
- It runs again with the reviewers on every round, since a fix can change the risk; only the ruling of the round that passes review counts.
- `starts: building` plans get it too, beside `staff-reviewer`.
- Its ruling is a label on the PR, attached by the dispatcher, and nothing on the dashboard:

| Ruling                             | Label                   | Colour   |
| :--------------------------------- | :---------------------- | :------- |
| the engine may merge it unattended | `ai-can-merge-this`     | `0e8a16` |
| a person merges it                 | `human-must-merge-this` | `d93f0b` |
