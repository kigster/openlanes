# Clean Agent Bondaries and Transitions

## What we are trying to achieve

An agent that finishes its assignment should be able to say so, and the next agent should start within seconds of it saying so. Today neither is true: an agent's only way to report completion is to rename its own folder, and the harness then second-guesses the rename by re-deriving state from the folder's contents. When the two disagree, the run stalls silently and reports success.

The target behaviour, observable from the outside:

- Each agent writes a dated ledger entry into the document it owns, at the start and at the end, naming itself, its purpose, and what it achieved (`accomplished`, `almost completed`, `interrupted`, `blocked`).

It looks like so:

```markdown
> [!NOTE]
>
> [2026-09-04.11:29:20 AM PST] [ Agent Leah the Researcher: Starting (round 1) ]
```

Upon completion of her ## Research section, she adds at the bottom:

```markdown
> [!NOTE]
>
> [2026-09-04.11:29:20 AM PST] [ Agent Leah the Researcher: Completed (round 1) ]
```

If leah is ready to pass this on she adds:

```markdown
> [!NOTE]
> 
> [2026-09-04.11:29:20 AM PST Agent: Leah the Researcher Finished
> [2026-09-04.11:29:21 AM PST Agent: Bring Yoda the Writer Next 
```

Yoda does the same in the beginning and the end of his term, and creates a blank file plan.md

This state is called "ready-for-planning" and it's one we were missing between Yoda and Palpatine

Agenst Luke and Rey must be started with `--brief` to allow the agents to communicate.

If the master process (master Agent) needs `--brief `to communicate with them all, perhaps all agents can be started this way but communicated five minutes before their time is up.

A timeout warns the agent five minutes out and asks it to stop at zero, but never kills it. `--timeout` on the command line tightens agents whose own budget is longer, and leaves tighter ones alone.

## Why it matters

A real run over `qualified-at` plan `020.00` invoked `yoda-writer` twice, succeeded twice, moved nothing, and exited green.

`palpatine-planner` was never invoked. Six minutes and roughly 2.7M tokens bought nothing, and the closing box said OK. The cost is not the six minutes, it is that a harness which cannot tell "finished" from "stuck" cannot be left running unattended, which is the entire point of it.

Three defects meet in that transcript, and they are separable:

1. ⭐️ Planned requires `plan.md`, which is written by `palpatine-planner`, which handles ⭐️ Planned. Nothing can legitimately enter the state, so `yoda-writer`'s rename is undone by the per-round resync every time.
1. Chaining infers the handoff from folder contents rather than being told it, so an agent that did its job correctly has no way to report the fact.
1. The timeout terminates the child, so a long chain is capped by its slowest agent and unflushed work is lost rather than wrapped up.

## What already exists

- `docs/specs/2026-09-05-agent-ledger-and-status-bars.md` is a full design for all four changes, written with the human and already reviewed once. It is the starting point, not a blank page.
- `lib/agentilda/runner.rb` holds the round loop, `Runner#attempt`'s in-task chain, `further_of` and `MAX_CHAIN_HOPS`, all of which the dispatcher replaces.
- `lib/agentilda/executor.rb` passes `timeout:` to `TTY::Command` (the kill), and already renders `time_budget_section`, `control_section` and `budget_section` into every prompt. `Executor#ledger_section` joins them.
- `lib/agentilda/control.rb` already has `WRAP_UP`, `STOP`, a grace deadline and per-invocation control files. The advisory timeout reuses all of it and invents nothing.
- `lib/agentilda/status.rb` and `lib/agentilda/state_machine.rb` hold `STATUSES`, `SPINE`, `PREFERENCE` and `FAMILIES`, where 🏁 Spec Ready is inserted.
- `lib/agentilda/ui.rb` holds `UI.concurrently`, `Line`, the countdown and the meter. The two bars are drawn around `TTY::Spinner::Multi` with an ANSI scroll region rather than replacing it.
- `agents/*.md` carry `timeout:` already (only `leah-researcher` sets one). `subagents:` is new.

## What research needs to settle

The design settles the shape. What it does not settle, and what an implementer would otherwise have to guess:

1. **Does `DECSTBM` behave across the terminals actually in use here?** Specifically iTerm2, Terminal.app, tmux and a plain pipe. Whether the region survives `SIGWINCH`, and whether `TTY::Spinner::Multi`'s cursor handling fights it. ***Answer: DO NOT WORRY ABOUT MULTI-TERMINAL. It must work on iTerm2. Do worry about getting killed and knowing where to restart from.***
1. \*\*\*\***Can an agent be relied on to write its own closing ledger entry?** If a meaningful fraction of invocations forget, the design's central assumption fails and the harness has to write the entry from the agent's exit status instead. This is answerable by instrumenting one real run. It is also answerable by instructing the agent to maintain a memory, throughout its work, of what it is being asked at the end. ***Answer: generally the agent should be trusted to write to the ledger.***
1. **What is the right poll interval?** Ten seconds is asserted, not measured. Cost of the poll against handoff latency, over a tree with a realistic number of plans. ***ANSWER: Poll every second and update agent's status line (see the dashboard below)***
1. **Does `Brief::TIMEOUT = 60` want the same advisory treatment?** The drafting shell-out that created this very folder timed out and discarded its work, which is the same defect in a different file. ***ANSWER: The prompt to briefer must be that he has 50 seconds to explore the codebase and write a brief. Use Haiku model for him. For consistency, create a `jabba-briefer` agent that does exactly what is needed, so no dynamic prompt has to be passed.***
1. **What happens to 🟡 Building?** With `luke-backend` and `rey-frontend` handling ⭐️ Planned, nothing writes 🟡 unless luke renames on start. Confirm that is wanted rather than retiring the state. ANSWER: Yes let's have Luke be in charge of that name transition. If he does not do it, that is a bug and it should be fixed. Hans Solo may reject the PR which renames the folder again, and should then restart Luke and Rey's work.
1. **Which existing plan folders break?** An audit across `qualified-at`'s `.plans` and this repo's, run before the state insert lands, the same way DSL vocabulary changes are audited before tightening. ANSWER: irrelevant.

## Agent Display

We must utilize the TTY::Cursor and TTY::Screen to show the agents working on the screen with top and bottom status bar showing different things. Both status bars are black, green and red letters on white background. Use magenta for tokens up, and use cyan for tokens down. Make that section have a grey background.

Belkow that after at least a single white space line, we see the header of the agents work table.

The header has fixed number of characters allocated and all data within it is sprintf("%n.ns") to properly fit into the slot. You can always use ljust and rjust.

After the header is the thin line made of "─" * Screen..width - 2 (all content has one character space on the left and on the right including status bars)

```
[ status bar ] [ plans in work: 001, 002, 003 ] [ total tokens: ↑ 450K  ↓ 342K ]

 timestamp  plan   file      agent [rounds:current]  model used   | what agents says
------------------------------------------------------------------------------------------
[date-time | 001 | spec.md | researcher [R:1/2] | model: opus5 |<status line every 1s>
[date-time | 002 | spec.md | writer     [R:1/2] | model: gpt5  |<status line every 1s>
[date-time | 003 | plan.md | planner    [R:1/3  | model: gpt5  |<status line every 1s>
------------------------------------------------------------------------------------------

	
[ lower status bar ]
[ working in <repo> path | agents total running : 7 | tokens: ↑ 40K  ↓ 3/2K 
```

The actual agent rows are informative, constnatly changing (every second, but they do not have to be in sync). They show the latest updated timestamp, the plan ID being worked on, the file the current agent is working on (we may want to add this to frontmatter), and the agent name with the name stripped.

Syntax [R:1/3] indicates rounds (1 of 3). To be honest I am not thrilled that the agents must redo all the work over many rounds for us to be satisfied withit. I would default all rounds to 1 and allow them to specify more than 1 but max 5.

next column shows which model each agentis using

And the final column shows in bold white on yellow background (background must reach 1 character before the ened of the screen).

Other colored elements in the table are:

Files:

- spec.md -> green
- Plan.md -> yellow
- Plan-backend -> bold yellow
- Plan-frontend -> cyan
- Implementation started, we say both luke and jey are working on the pull-requests.md file (magenta)
- Once the joined draft PR from Luke and Jey is pushed, reviewer starts to check it. Instead of the file name it should say the number of the PR: #43 and be clickable to the real PR. It should be in light blue color while the "reviewer" is reviewing it. If it returns to luke and rey rejected the PR # stays in the file column, but it turns red in color. The agents double in size (we should see both Luke and Rey in two lines working on the same red PR). Once they fixed it, the PR# changes to light blue and reviewer again is the agent working on in. The reviewer has the right to reject the PR maximum twice per PR. Once they've done it twice, they review the same PR and if they find it acceptable the approve it by commenting " 👍🏼 to deploy". At that point the work on this ticket finishes.
- When do so, the hansolo leaves the
- The exception to the rule is if Luke and Rey decided to create several PRs to implement this feature, so this file must be consulted to see if we are execting more work before cloising this ticket as done.
