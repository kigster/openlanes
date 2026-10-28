# Plan: Three Reviewers

Six pull requests, in order. Each lands on `main` before the next starts. V1 to V8 are the decisions in `docs/decisions/decisions-on-agent-names-models-and-reviewers.md`; the D-numbers below are this plan's own.

## PR 1: verdicts, and the label they add up to

### Decisions

- **D1. A reviewer reports one verdict in its closing ledger note** (V2): `great`, `passed` or `rejected`, as in `Completed, round R (great)`. `security-reviewer` adds `vulnerability` beside `rejected` for an exploitable hole. `slop` stays: it sends the plan to rewrite, and counts as a rejection.
- **D2. `Plans::Verdict` takes the reviewers' verdicts, not their comments** (V4): any `rejected` gives `review-rejected` (plus `review-vulnerability` when security said so); otherwise two `great` or more give `review-approved`; otherwise `review-passed`. With one reviewer, `great` approves. The pooled emoji count of R3 goes, and with it `review.max_hmm` and `$OPENLANES_REVIEW_MAX_HMM`. No other project runs on openlanes yet (N3), so the key is dropped rather than warned about, and a file that still sets it is refused as an unknown key.
- **D3. `review-ok-not-perfect` becomes `review-passed`**, colour `E8E890` (V2). `ReviewLabel::RENAMED` maps the old name to it. `LabelSync` renames the label on the repository (`gh label edit --name`), so every PR carrying it keeps it, and creates it only where neither name exists. `LabelMigration` (M3 to R3) keeps its own steps: M3's `review-passed` meant what V2's does, so it no longer moves.

### Work units

- [x] `Plans::Verdict` rewritten to D2; the R3 count, `Config#max_hmm` and its env variable removed.
- [x] `ReviewLabel` rename; `LabelSync` renames in place; `LabelMigration` keeps its own M3 steps.
- [x] `openlanes docs` and the architecture regenerate.
- [ ] Lint, the full suite, every changed file above 95% coverage.

## PR 2: the dispatcher waits for every reviewer, then labels

### Decisions

- **D4. How many review, from `starts:`** (V5): `building` gets one reviewer (`staff-reviewer`), `planning` and `research` get every reviewer. Read through one method, so PR 3 adding agents changes no count.
- **D5. A reviewer's verdict lands in its stage in `state.json`**, not in a label. The plan stays at `in_review` while any of its reviewers for the round is running.
- **D6. When the last one reports, the dispatcher decides** (V2, V4): `Plans::Verdict` over the round's verdicts, the label set through `Vcs::Review` (still refused while CI is red for a passing label), then the folder moves as today: rejected to ⛔, slop to rewrite, passing on toward verification.
- **D7. Reviewers stop labelling.** `openlanes review` is withdrawn from `staff-reviewer`'s prompt; the dispatcher sets `review-in-progress` when the reviewers start.

As built: `Engine::Reviews` owns D4 to D7, and the dispatcher only asks it. A round is the stages whose `moves` match the plan's, so a verdict from before the last move never counts, and a reviewer rerun after a restart replaces its own. A reviewer that signs `Completed` with no verdict word fails its round instead of moving the plan on.

### Work units

- [x] Reviewer count and the hold at `in_review`; the round's verdicts read back from `state.json`.
- [x] The decision step and its label; `staff-reviewer.md` reports a verdict instead of labelling.
- [x] Dispatcher specs: one and three reviewers, every verdict mix, no verdict; finishing order and a restart mid-round in `reviews_spec`.
- [x] Docs, lint, the suite, coverage.

## PR 3: security-reviewer and design-reviewer

### Decisions

- **D8. One shared review brief** (R2, V1): how to review, the "Reviewed by <agent> using <model> by <provider> at <time>." header, the emoji table, D1's closing note, ignore existing comments, review only the diff. It lives once, in `agents/shared/review.md` (outside the registry's `agents/*.md` glob), and `Execution::Prompt` appends it for every agent whose `phase:` is `review`. Each `agents/*-reviewer.md` keeps only its own focus.
- **D9. Models:** `staff-reviewer` moves to Opus; `security-reviewer` Sonnet; `design-reviewer` Sonnet. 💣 and 🔓 stay `security-reviewer`'s alone.
- **D10. `Names::PLANNED` empties**, and the registry drift spec holds every name to a file.
- **D10a. A round's rejections count once** in `Arbitration::Counter`: three reviewers rejecting in one round are one rejection toward `merge.max_rejections`, not three.
- **D10b. Each reviewer owns its findings.** It writes under `## Findings: <name>` in `pull-requests.md`, so reviewers sharing a checkout never overwrite each other, and numbers its findings from its own first id: F1 for `staff-reviewer`, F101 for `security-reviewer`, F201 for `design-reviewer`. The arbitrator reads `F\d+` and strikes by id, so ids must not collide across reviewers.
- **D10c. The round a verdict belongs to is recorded with it**: the stage gains `review`, the plan's moves when the verdict was given. A stage's own `moves` is written at settle, after the deciding reviewer has already moved the folder, so it cannot tell the counter which round the last reviewer belonged to.

### Work units

- [x] The brief and the prompt hook; the two agent files; `staff-reviewer.md` trimmed to its focus.
- [x] `openlanes agents`, `openlanes docs`, architecture regenerated.
- [x] Docs, lint, the suite, coverage.

## PR 4: reviewers dealt across coding agents, and the mark on the dashboard

### Decisions

- **D11. `review.adapters:` in `.openlanes.yml`** (V7, I3): the list of coding agents to review with, main one first; written by the init interview (plan 011) once that exists, by hand until then. Unset means the project's `adapter:`.
- **D12. Dealing** (V7): staff to the first, security to the second, design to the third, wrapping; adapters the startup probe found unusable are skipped. A reviewer's frontmatter `adapter:` or the plan's `phases.review` still wins (plan 040's precedence).
- **D13. The verdict carries the coding agent's mark** (V3): a letter in the vendor's colour on our own neutral glyph, never a logo.

### Work units

- [ ] Config key, dealing in `Agents::Profile`, the snapshot field, the board mark.
- [ ] Specs (Ruby, vitest, one Cypress case), docs, lint, coverage.

## PR 5: a reviewer that fails is replaced, not blocking

### Decisions

- **D14.** A reviewer that crashes, times out or ends without a D1 verdict is run again, once, on the main coding agent with the same prompt; its verdict counts as that reviewer's (V6). The label still waits for every reviewer.

### Work units

- [ ] The replacement run, its stage and ledger record; specs; docs, lint, coverage.

## PR 6: deploy-assessor beside the reviewers

### Decisions

- **D15.** `deploy-assessor` starts with the reviewers on every round, never votes, and only the passing round's ruling counts (V8). Its ruling becomes a label the dispatcher sets. Open: V8's label names against the existing `auto-merged` / `merge-manually`.

### Work units

- [ ] Routing beside the reviewers; the ruling's label; specs; docs, lint, coverage.
