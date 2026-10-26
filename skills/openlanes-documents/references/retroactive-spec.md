# Retroactive specifications: the provenance line

A plan numbered `NNN.MM` with `MM > 0` documents work that already shipped. Its `spec.md` must open by saying so.

A specification's form claims that somebody thought this through before it was built. A `spec.md` dated today and filed as an ordinary plan makes that claim falsely. The number carries the fact (`MM > 0`), but a number is easy to miss and easy to misread as containment; the opening line is what survives being copied, quoted or exported.

## The line

Immediately after the H1, before anything else:

```markdown
# Verify Against Filed Returns

> [!NOTE]
> **Written retroactively on 2026-08-17.** This documents work that shipped in
> #41 and #43, merged between plan 018 and plan 019. It describes what exists;
> it does not record a decision taken in advance.
```

Three things, all load-bearing:

1. **The date it was written**, not the date the work shipped.
1. **The pull requests it describes**, by number: the evidence a reader checks the document against.
1. **The disclaimer.** "Describes what exists" is the point.

## Choosing the anchor

`openlanes create --after <NNN> --prs <n,n> <words>` takes the next free slot in the gap after plan `NNN`. Choose `NNN` by **when the work merged**, not by what it is about:

```bash
git log --diff-filter=A --format='%ad %s' -- '.plans/018*' '.plans/019*'
gh pr view 41 --json mergedAt
```

If the pull requests merged after 018's folder was created and before 019's, the anchor is 018. The decimal is a slot in time, not a claim about subject matter.

## What happens next

`create --prs` writes `pull-requests.md` (the folder is born ⏪ Retroactive) and hands the folder to `spec-writer`, which writes `spec.md` from the diff and an empty `plan.md`. `--no-spec` stops after recording the PRs. From there the plan moves like any other; `openlanes run -n --plan <NNN.MM>` shows who takes it next.

## What does not deserve one

Most unmatched pull requests. The test is whether somebody would need to read it: a capability with behaviour, an interface, or invariants not obvious from the code. "Fix a typo", "remove dead code" and "bump a dependency" belong to no plan; `openlanes docs` names the prefix their titles carry instead.
