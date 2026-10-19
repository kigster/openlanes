# Decisions on blocks, escalation and answering them

Date: 2026-10-13. Grilling session, one question at a time.

## Why

A run on openlanes' own plans left five plans ⭕️ blocked, and reading their `blocked.md` files did not tell the author what to do:

- 002: three questions, planned against a four-week-old worktree whose code `main` had already replaced.
- 003: B1 asked luke to change his own file, a question between partners, not for a person. The author's answers (`B1<1>`, `B2<1>`) were ignored, because the parser only accepts `## A1`, and nothing said so.
- 009: waiting on plan 008, which is a dependency, not a question.
- 010: B1 reported a harness bug (a folder renamed under a running agent) as a question.
- Option lists came in three styles (`1.`/`1.`, `1.`/`2.`, `answers: yes, no`), and no file said how to answer.

## Decisions

### D1. Partners settle their own questions

When an agent needs something from its partner (luke ↔ rey), it asks through the mailbox and never blocks the plan. A person is engaged only when the partners cannot agree or cannot resolve the issue between them.

### D2. Either partner escalates, after the other has replied once

Either partner may escalate a mailbox thread to a person, but only after the other side has answered at least once, so nobody escalates a question their partner never saw. The harness counts nothing. The agent judges disagreement better than a message count would.

### D3. A question for a person is context, lettered options, and room for something else

Every question that reaches a person has one shape: a short context paragraph, then lettered options `a)`, `b)`, `c)`, with exactly one marked recommended. A yes/no question is `a) yes` and `b) no`. The page shows one full-width button per option, stacked, with a text box under them for an answer none of the options covers. Agents write only this shape. A lenient parser reads older files (`1.`, `Option 1:`, `answers: yes, no`) into it.

### D8. `blocked.md` holds exactly one question

Supersedes the numbered `## B1` … `## Bn` blocks and their `## An` answers. Decided 2026-10-13 by kig.

- A plan is blocked for **one** reason: the first one the agent hit. `blocked.md` describes that one situation and asks that one question. An agent never writes a second issue into it.
- If the question has candidate answers, it is multiple choice in the D3 shape, and the last choice is always **Type something instead**.
- The blocked agent turns red on the page, with a 3px bright red border, and its question is posted to the side drawer.
- `openlanes unblock` in the terminal offers exactly the same choices for the same one question.
- If, once answered, the agent is still blocked on a next question, it **overwrites** `blocked.md` with that question and the cycle repeats.
- Every answered question is appended to the plan folder's `decisions.md` as one entry: the question, the chosen option or the typed text, the agent that asked, and when. Agents read `decisions.md` before asking, so nothing is asked twice.

### D4. A plan that waits on another plan waits silently

An agent that finds its plan needs another plan merged first records the dependency (`depends_on`, from plan 008) instead of asking. The plan shows a grey "waiting on NNN" badge, never reaches a person, and resumes by itself once the plan it waits on merges.

### D5. Two plan folders with one number are merged by the harness

What happened to 010: `openlanes unblock` (started by the web page for each answer) runs `resync dirs` over every plan folder when it finishes. It renamed `010.00-📋` to `010.00-🟡` while luthen-rael was still writing in it. The engine's "never rename a busy plan" rule lives only in the engine's memory, so the unblock process could not see it. luthen-rael's next writes went to the old path and recreated `010.00-📋`, and the engine started luke on that folder as if it were a plan of its own.

Two changes:

1. The rename race is fixed at its source: no process renames a plan folder whose `state.json` shows a running agent.
2. If two plan folders under `.plans/` still end up with one number, the harness merges them: the stray files move into the real plan folder (the one holding `spec.md` and the fuller `state.json`), the stray plan folder is removed, and the merge is logged.

### D6. A vanished file means locking failed, and all work stops

A fault is not a question. When an agent finds a file it wrote is gone, the locking did not work. The agent:

1. reports the lock it held (lock name and path), the file that disappeared, and the error condition to the dispatcher;
2. stops.

The dispatcher then:

1. broadcasts to every running agent: who removed this file, who holds a lock that conflicts with this one, or who removed a file without a lock;
2. tells every agent to stop what it is doing until the corruption is resolved.

Work stops until it is. In the 010 incident luthen-rael did hold an `alock` lock on `.plans/010.00-📋 → inquirex-fixes`, and the `unblock` process renamed that plan folder without checking it. Every plan folder rename must therefore respect `alock` locks as well as `state.json`.

### D7. An agent out of rounds says why and offers another round

An agent that is red with no question to answer (luke on 003: interrupted, no rounds left) gets a drawer whose first line says why, e.g. "Out of rounds: interrupted 3 times (last: killed 60s after q)", and one primary button, **Give another round**. Model, log and message stay below it.

### D9. The engine turns a prose question into choices

Decided 2026-10-15 by the owner (kig).

Agents are told to write D3's shape, and some still write a paragraph that ends in a question. The page then has no buttons to offer, only the text box.

1. **The rewrite goes into `blocked.md`.** When an open question's body yields no options to the lenient parser, the engine rewrites that body, under the same `## Bn` heading, into D3's shape: a short context paragraph and lettered `a)`, `b)`, `c)` options, one per line, exactly one marked `(Recommended)`. No "Type something instead" line, which amends D8 for rewritten questions: the page adds the text box itself. The page, lando-broker and anything else reading the file then see the same options. `## An` answers are never touched. The agent's original text is kept in the plan's `state.json` under `conversions` (question number, original body, its SHA256, when, model, outcome), so the rewrite is traceable and the same text is never sent twice, even across restarts.
2. **One direct call through `inquirex-llm`.** `OpenRouterAdapter`, keyed by `OPENROUTER_API_KEY`, asking for a JSON object with `context` and `options` (`label`, `recommended`). The default model is `anthropic/claude-haiku-5.5`, small and quick; `questions.model` in `.openlanes.yml` replaces it. The call runs off the tick thread and its result is applied on a later tick, and only if the question is still open, still unanswered and unchanged on disk, and the plan is still this run's. An answer that does not read back as two or more options with one recommended leaves the file as it was and is recorded as rejected. Without a key nothing is sent, and the page still shows the text box.
3. **The web page is the only answering path.** `openlanes unblock` need not offer the same choices in the terminal; D8's bullet saying it does is withdrawn.

The question text, and its heading, go to OpenRouter and to whichever provider serves the configured model.

### D10. Worktrees follow `origin/main`, and rebase conflicts never reach a person

Decided 2026-10-16 by the owner (kig).

What happened: plan 008.01's worktree branch had no commits of its own and sat 211 commits behind `origin/main`, so luke-backend went looking for code that had landed weeks earlier. A reused worktree was never refreshed, and a new branch started from the main checkout's local HEAD. The agent could not catch up by itself, because the boundary fails any run in which HEAD moved.

The owner: "I want the rebase from main to the worktree branch to happen automatically with conflict resolution by the implementing agent", and then: "I don't want to be manually dealing with git rebases onto main from worktrees and conflict resolution. This is the job for the agent, whichever is best suited to do it."

1. **The harness refreshes every plan worktree before each agent run**, in worktree isolation only, and only when no other agent is working in that checkout. It fetches `origin <default>` (the default branch from `origin/HEAD`, else `main`). A new branch starts from `origin/<default>`. A branch with no commits of its own is fast-forwarded; no agent is involved, which is 008.01's case. A branch with commits of its own and a clean tree is rebased. One with uncommitted changes is left on its base and the log says why: `--autostash` can strand uncommitted work in the stash when it fails to re-apply.
2. **The harness does every git step that moves HEAD; agents only edit and `git add`.** It fetches, fast-forwards, starts the rebase, runs `GIT_EDITOR=true git rebase --continue` once nothing is unmerged and no staged file holds a marker, aborts, and pushes. All of it happens outside the window `Boundary` checks, so "HEAD did not move during the agent's run" still holds. `git rebase` joins `git commit` in the commands every agent is denied, and is ungrantable: the harness pushes the rewritten branch with `--force-with-lease`, against the commit its tracking ref last saw, and only for the branch it named itself. Committing stays the harness's because the boundary is the only guarantee that an agent's run changed files and nothing else; an agent that may commit mid-rebase may commit anywhere.
3. **A stopped rebase is a job of its own, not plan work.** The assigned agent, if it builds (luke-backend, rey-frontend, r2d2-mechanic), resolves first; then `bb8-resolver`, an agent whose only job this is. Its prompt says to keep both sides' intent, to favour what landed on `origin/main` where they contradict, and to record each judgement call under `## Rebase decisions` in `plan.md` for the reviewer. The job signs nothing and spends no round; plan work starts on the next tick. No partner starts in the checkout while it runs.
4. **No question, no block.** If bb8-resolver fails too, the harness aborts, which restores the branch exactly, and the next run tries bb8-resolver again one step up a ladder (its own sonnet/high, then opus/high, then opus/max). Once the ladder is spent the plan carries on, on its old base, logged as `REBASE PENDING`, until `origin/main` moves to a new commit; then the cycle starts again. Nothing writes `blocked.md` for a rebase. The tally is kept in the engine's memory, so a restart starts the ladder over, which costs at most three bb8 runs.
5. **A rebased branch reaches its pull request on the next publish.** The publisher pushes only when the worktree holds new work, so a rebase alone does not update an open pull request until the plan's next build.
