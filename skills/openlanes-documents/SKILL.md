---
name: openlanes-documents
description: "The files inside a openlanes plan folder: what spec.md, plan.md, blocked.md, pull-requests.md and the closing documents are for, the exact formats openlanes parses, and a template for each. Use when writing or fixing a file in a `.plans/NNN.MM-…` folder by hand: blocked.md questions and answers, spec.md frontmatter, a pull-requests.md table, a retroactive spec's provenance line, or a discarded, deferred, deployed or rollback note."
---

# openlanes-documents: the files in a plan folder

Load the `openlanes` skill first if it is not in context.

A folder's contents justify the state in its name. `openlanes resync dirs` renames a folder whose contents contradict its emoji, so a file written in the wrong shape is a file the tool cannot see, and the folder stays where it was.

## Which state needs which file

Ask the tool, never a copy of its table:

- `openlanes docs` prints every state, the files it requires, and why. `openlanes states` draws the transitions.
- `openlanes resync dirs -n` after an edit shows what your change now justifies; drop `-n` to rename.

## The files

| File | For | Written by |
| --- | --- | --- |
| `spec.md` | what and why; its frontmatter says how to route and judge the work | `openlanes create`, the human, `leah-researcher` (`## Research`), `yoda-writer` |
| `plan.md` | units under `## Backend` and `## Frontend`, order, the integration check; blank means "waiting for the planner"; a `## Frontend` with no unit heading starts nobody | `yoda-writer` creates it empty, `palpatine-planner` fills it |
| `contract.md`, `openapi.yaml` | the interfaces between the halves; the HTTP surface when there is one | `luke-backend` |
| `blocked.md` | open questions a human must decide | any agent, or a human |
| `pull-requests.md` | the pull request table the review states are judged by | `openlanes run` when it opens the PR, `openlanes create --prs`, `openlanes resync prs` |
| `rewrite.md`, `delayed.md`, `discarded.md`, `deployed.md`, `rollback.md` | why the plan left the main path | the reviewer (`rewrite.md`), otherwise a human |
| `state.json` | stages, signatures, mailbox, read receipts, resume records (`last-known-state`) | the harness only; read it with `openlanes state show --plan <NNN>` |

Agents also sign a ledger inside the document they own: a `> [!NOTE]` block of `[ agent: … status: Started, round 1 ]` lines. Leave those blocks as they are; the harness reads them to decide who finished.

## Formats openlanes parses

**spec.md frontmatter.** Keys: `lane` (full, plan, quick), `depth` (fast, medium, deep), `frontend` (true or false), `phases` (`<phase>: { adapter, model, effort }`), and `implementation_suggestions`, `implementation_requirements`, `task-completed-when`, `how-to-verify` (each text or a list of text). An unrecognised value is ignored rather than fatal, so a typo silently costs the plan its lane. Choosing the values is `openlanes-spec`'s job. The body opens with the four headings `openlanes create` scaffolds: `## What we are trying to achieve`, `## Why it matters`, `## What already exists`, `## What research needs to settle`.

**blocked.md questions and answers.** A question is a line that starts with `B<n>`, after at most four `#` and an optional `**`: `## B1 — Which rate feed?`. Its answer is a heading `## A1` with the same number. Any other numbering (`1.`, `Q1`, a bullet `- B1`) is invisible: the folder never blocks, and `openlanes unblock` finds nothing to drain. Start no other line with `B` and a digit. An answer counts only when it names who decided (a role will do), carries a date, and picks one option.

Which human a block waits on lives only in the emoji. `resync dirs` files a new `blocked.md` as ⭕️ (engineering); rename the folder's emoji to 🅱️ by hand when product owns the decision, and `resync` keeps it there.

**pull-requests.md.** openlanes reads the first markdown table whose header names a pull request (`Pull Request Number`, `PR`, `#`) and whose rows link to `/pull/<n>`. Columns are found by header words: number, name or title, status. Status words: `Open`, `Draft` or `WIP`, `Merged`, `Closed`. Escape `[`, `]` and `|` inside a title. Prose below the table is ignored.

```markdown
| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 41 | [\[018.01\] Verify against filed returns](https://github.com/acme/app/pull/41) | Merged 🟣 |
```

**Retroactive provenance line.** A plan `NNN.MM` with `MM > 0` documents work that already shipped. Its `spec.md` opens, right after the H1, with a dated note naming the pull requests it describes. `openlanes create --after <NNN> --prs <n,n>` records the PRs and has `yoda-writer` write the spec; the line and how to pick `--after` are in [`references/retroactive-spec.md`](references/retroactive-spec.md).

## Templates

Copy the shape; replace every placeholder:

- [`references/spec-template.md`](references/spec-template.md): `spec.md`, frontmatter and the four headings.
- [`references/plan-template.md`](references/plan-template.md): `plan.md` and its unit shape.
- [`references/blocked-template.md`](references/blocked-template.md): `blocked.md` with `B<n>` and `A<n>`.
- [`references/closing-templates.md`](references/closing-templates.md): `rewrite.md`, `delayed.md`, `discarded.md`, `deployed.md`, `rollback.md`.
- [`references/retroactive-spec.md`](references/retroactive-spec.md): the provenance line and the anchor.

Done when `openlanes resync dirs -n` names nothing to rename for the folder you edited, or names exactly the state you meant it to reach.
