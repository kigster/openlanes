---
name: openlanes-spec
description: "Create a openlanes plan and write its spec.md: choose the lane (full, plan, quick) and depth, and record implementation suggestions, requirements, done criteria and verification. Use when the user wants to start, spec or file a feature, task or fix in a project using `.plans/`, wants to document work that already shipped, or wants to add implementation detail to an existing plan's spec."
---

# openlanes-spec: from intent to a spec the agents can work

Load the `openlanes` skill first if it is not in context; it holds the lanes and the project model.

The spec is the only thing a human is sure to write. Every agent downstream reads it, and agents start without the user's personal skills, so what is not written in `spec.md` does not exist for them.

## 1. Pick the branch

- **New work**: continue at step 2.
- **Work that already shipped** (the user names merged PRs): `openlanes create --after <NNN> --prs <n,n> <words>`. It records the pull requests in a retroactive `NNN.MM` plan and has `yoda-writer` write its spec from the diff; the provenance line it must open with is in `openlanes-documents`. Skip to step 6.
- **An existing plan needs more detail**: open its `spec.md` (`fd spec.md .plans | rg '^.plans/<NNN>'`) and go to step 4.

## 2. Propose the lane and depth

Read `.openlanes.yml` for the project's default `lane`. Then judge this task:

| Lane    | Fits when                                                                                                   |
| ------- | ----------------------------------------------------------------------------------------------------------- |
| `quick` | One sentence describes it, no design decision, a handful of files: split a migration, rename a module, bump a dependency. |
| `plan`  | The user has already written the spec they want built (detailed notes, a file, a long message). Research and rewriting would only dilute it. |
| `full`  | Anything with open questions: new behaviour, an unfamiliar area, a choice between approaches.               |

Depth sets how hard every phase thinks: `fast` for small, known work; `medium` as the default; `deep` for architecture, money, security or data migrations.

Say the pick in one line with its reason, and wait for a yes:

> Lane **quick**, depth **fast**: a mechanical rename across ~6 files, no design call. OK?

When the user already named the lane, skip the question. When the task straddles two lanes, ask which, giving the cost of each (full is slower, quick fails over to blocked if the task turns out to need design).

## 3. Create the folder

```bash
openlanes create <two to five words> --lane <lane> --depth <depth> --no-open
```

- `--from notes.md` instead of words when the user's notes are a file: its frontmatter `title:` names the folder, and its body becomes the spec.
- `--no-draft` when the user has given you the full content; otherwise `create` drafts the four headings from the project's own docs, which takes up to a minute.
- `--no-open` because you are about to edit the file; the user can open it after.

Note the ordinal and folder `create` prints.

## 4. Write the frontmatter

Add what the user told you, and ask for the two keys that decide whether the work can be judged done, when the conversation has not supplied them:

```yaml
---
lane: full
depth: medium
frontend: false                 # omit to inherit .openlanes.yml; true forces the front-end agent, false forbids it
implementation_suggestions:     # offered to agents, who may take a better route and say why
  - Ruby, with dry-cli for the command line
implementation_requirements:    # met exactly as written, or the agent blocks and asks
  - The database is PG-strict
task-completed-when:            # what must be true; copied into plan.md
  - "`openlanes create` opens an editor and writes no draft"
how-to-verify:                  # commands or checks that prove it
  - "bundle exec rspec spec/openlanes/cli/create_spec.rb"
phases:                         # optional per-phase adapter, model, effort
  build: { model: opus }
---
```

`openlanes` adds one requirement to every builder and the reviewer on its own: after the changes, all tests and linters pass (`just check-all` when the justfile has that recipe, otherwise `bundle exec rspec` and `bundle exec rubocop` in a Ruby project). Leave it out of `implementation_requirements`; repeating it adds nothing.

The split between suggestions and requirements is the decision that matters most here. A requirement is binding: an agent that cannot meet it stops the plan and asks, and the reviewer rejects work that misses it. Put a preference there and the plan blocks over a preference. When the user says "use X", ask whether that is a must or a suggestion, unless it is obvious.

Quote any list item holding `: `, ` #`, a leading `?`, `` ` `` or `{`, since YAML otherwise reads a shell command as a mapping. Check the result parses as strings: `ruby -ryaml -e 'p YAML.safe_load(File.read(ARGV[0])[/\A---\n(.*?)\n---/m, 1])' <spec.md>`.

Write each rule out in full. "Follow our postgres-strict skill" means nothing to an agent that starts without skills; "every money column is `numeric(19,4)`" does.

## 5. Fill the body

Keep the four headings `create` scaffolded (the shape is in `openlanes-documents`, `references/spec-template.md`). Fill them from the conversation and the repository. Where nothing is known, leave the heading with one honest line ("unknown; research should settle") rather than an invented answer, because research reads the gaps as its assignment.

## 6. Check it routes

```bash
openlanes run -n --plan <NNN>
```

Done when the preview names the expected first agent: `leah-researcher` for full, `luthen-rael-planner` for plan, `r2d2-mechanic` for quick. A retroactive plan has already been through `yoda-writer`, so the preview names whoever handles the state it settled in. A wrong agent means the frontmatter did not parse as intended; re-read it.

Report the folder, lane and depth in two lines, and offer to start the agents (`openlanes-run`).
