# spec.md template

`openlanes create <words> --lane <lane> --depth <depth>` writes the title, the frontmatter for the flags it was given, and the four headings; without `--no-draft` it also drafts them from the project's own docs. Fill what it left, keeping the headings in order. Frontmatter keys you do not need can be left out; `lane` defaults to `full`.

```markdown
---
lane: full                      # full | plan | quick
depth: medium                   # fast | medium | deep
frontend: false                 # omit to inherit .openlanes.yml; true forces the front-end agent, false forbids it
implementation_suggestions:     # offered to agents, who may take a better route and say why
  - Reuse the HTTP client already in lib/acme/http.rb
implementation_requirements:    # met exactly as written, or the agent blocks and asks
  - Every money column is numeric(19,4)
task-completed-when:            # copied into plan.md as "## Task completed when"
  - "`acme rates sync` stores today's rates and prints how many changed"
how-to-verify:                  # copied into plan.md as "## How to verify"
  - "bundle exec rspec spec/acme/rates_spec.rb"
phases:                         # optional, per phase: adapter, model, effort
  build: { model: opus }
---
# Rate Feed Sync

## What we are trying to achieve

The outcome, in a few sentences: what a user or the system can do afterwards.

## Why it matters

Who needs it and what it unblocks. A line from the project's backlog counts.

## What already exists

Specific files, modules and prior plans this builds on, by path.

## What research needs to settle

The open questions. Where nothing is known, say so in one line; research reads the gaps as its assignment.
```

Notes:

- Quote a list item that holds `: `, ` #`, a backtick, `{`, or starts with `?`; YAML otherwise reads it as something other than text.
- Leave out "tests and linters pass": openlanes tells every builder and the reviewer that already.
- `leah-researcher` appends `## Research` (that chapter is what makes the folder 🔎 Researched); `yoda-writer` then rewrites the body into the full specification. Neither needs a heading from you beyond these four.
- A retroactive plan (`NNN.MM`, `MM > 0`) opens with the provenance line in `retroactive-spec.md` instead of the four headings.
