# blocked.md template

A plan with `blocked.md` naming at least one open question is blocked: ⭕ Technical Block (an engineer or the CTO decides) or 🛑 Product Block (a product manager decides). Agents step around it until a human answers and runs `openlanes unblock <NNN>`, which hands the file to `lando-broker`. The broker folds each qualifying answer into `spec.md` (what and why) or `plan.md` (how and in what order), deletes the question with its answer, and deletes the file when nothing is left.

Two heading kinds, and only these: `## B<n>` for a question, `## A<n>` for its answer. openlanes counts the `B` lines; a question numbered any other way blocks nothing.

```markdown
# Rate Feed Sync — Blocked

**Blocked since:** 2026-10-12
**Blocking:** U2 cannot start until the source of rates is chosen
**Decision needed from:** the CTO

## B1 — Do we read rates from the vendor feed or cache them per filing period?

**What we need decided:** one sentence, phrased so that an answer is possible.

**Why it blocks:** what gets built wrong if we guess.

**Options:**

| Option | What it means | Cost or risk |
| :----- | :------------ | :----------- |
| A      |               |              |
| B      |               |              |

**Recommendation:** one option, and why.

**If unanswered by 2026-10-19:** the default we will take.

## What is already decided

Anything settled that the decider need not reopen.
```

An answer, added under its question when it arrives:

```markdown
## A1

Decided 2026-10-13 by the CTO: rates are read from the vendor feed, never cached across a filing period.
```

Notes:

- An answer counts only when it names who decided (a role is enough), carries a date, and picks one option. "Leaning towards B" stays, and so does its question.
- Answer in pieces if that is how answers arrive; whatever is still open keeps the plan blocked.
- A new `blocked.md` lands at ⭕ on the next `openlanes resync dirs`. Rename the folder's emoji to 🛑 when product owns the decision; nothing else records which human it waits on.
- `openlanes unblock <NNN> -n` lists the questions openlanes can see. Run it after writing the file.
