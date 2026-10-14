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

What happened to 010: `openlanes unblock` (started by the web page for each answer) runs `resync dirs` over every plan folder when it finishes. It renamed `010.00-📋` to `010.00-🟡` while palpatine was still writing in it. The engine's "never rename a busy plan" rule lives only in the engine's memory, so the unblock process could not see it. palpatine's next writes went to the old path and recreated `010.00-📋`, and the engine started luke on that folder as if it were a plan of its own.

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

Work stops until it is. In the 010 incident palpatine did hold an `alock` lock on `.plans/010.00-📋 → inquirex-fixes`, and the `unblock` process renamed that plan folder without checking it. Every plan folder rename must therefore respect `alock` locks as well as `state.json`.

### D7. An agent out of rounds says why and offers another round

An agent that is red with no question to answer (luke on 003: interrupted, no rounds left) gets a drawer whose first line says why, e.g. "Out of rounds: interrupted 3 times (last: killed 60s after q)", and one primary button, **Give another round**. Model, log and message stay below it.
