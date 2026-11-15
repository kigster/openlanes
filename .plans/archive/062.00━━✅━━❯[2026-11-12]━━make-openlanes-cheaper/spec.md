---
created: 2026-11-10
starts: planning
<<<<<<< HEAD:.plans/archive/062.00━━✅━━❯[2026-11-12]━━make-openlanes-cheaper/spec.md
depends_on: [none]
||||||| parent of 93b20aa6 (UPDATE THE PLANS):.plans/062.00━━⚪━━❯make-openlanes-cheaper/spec.md
=======
task-completed-when:
  - "A resumed session's prompt carries only the journal entries written since the round it resumes"
  - "`deploy-assessor` runs on a cheaper model when the plan's diff is under a configured size"
  - "A plan that has spent more than its dollar cap is not given another round, says so on the board, and waits for a person"
>>>>>>> 93b20aa6 (UPDATE THE PLANS):.plans/062.00━━⚪━━❯make-openlanes-cheaper/spec.md
---
# Make Openlanes Cheaper

## What we are trying to achieve

Reduce cost and number of tokens.

## Why it matters

Cost is always important.

## What needs to be done

- Trim the per-round prompt. The journal alone is up to about 5k tokens every round, resumed or not. 
  - On a resumed session, send only entries newer than the last round.
- Downgrade deploy-assessor from opus/high to sonnet for diffs under a size threshold.
- Add a dollar budget per plan. Tally counts tokens and the catalogue has rates; refuse a new round once a plan passes its cap, and show it on the board.

## What already exists

Checked against `main` on 2026-11-10.

- **Journal.** `Execution::Prompt#journal_section` prints the instructions and up to `JOURNAL_LIMIT` (40) entries on every round, "resumed or not", which its own comment prices at about 5k tokens. The executor resumes the previous round's session (`--resume`) and compacts sessions (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, the `compact` command).
- **deploy-assessor.** `agents/deploy-assessor.md` is `model: opus`, `effort: high`. `Agents::Profile` is where a model is chosen for one agent on one plan.
- **Budget.** Only a per-invocation token cap exists: `run --max-tokens` and `eval --max-tokens`, enforced in `Executor`. `Live::Meter` already prices each plan in dollars from the adapter's rates, and `Live::Snapshot` puts `cost` on every plan and on the run. `.openlanes.yml` has no budget key.

## Notes for whoever builds this

- Journal: a resumed session already holds its earlier prompts, so the older entries are duplicates there. After a compaction or a fresh start they are not, so send the full journal then. The journal instructions (about 20 lines) are also repeated every round and can shrink to one line on a resume.
- deploy-assessor rules whether a pull request may merge unattended, so a wrong `auto` is the expensive mistake. Downgrade only below the threshold and keep opus for anything touching migrations, auth or CI config.
- Budget: `Meter` loses a row ten seconds after its agent finishes, so the cap must count from what `state.json` or the event journal keeps, not from the live board alone. The cap needs a key in `.openlanes.yml` (see plan 057.00's schema) and an optional per-plan override in `spec.md` frontmatter.
- Plan 064.00 shows cost on the board; build the cap first so the page has one number to show.

## Decisions needed

- The default dollar cap per plan, and whether reaching it blocks the plan (⭕️, a question for a person) or only warns.
- The diff size under which `deploy-assessor` may run on sonnet. Proposed: 200 changed lines.

## How to tell it's working?

- bundle exec rspec spec/openlanes/execution/prompt_spec.rb spec/openlanes/agents/profile_spec.rb spec/openlanes/live
