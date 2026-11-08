<!-- generated-by: bin/wiki-gen -->

# Decisions on abandoning, discarding and trashing plans

**Up:** [Decisions](Decisions.md)

______________________________________________________________________

Settled 2026-11-01 in a design conversation. Not built yet; this file is the specification the implementation works from.

## Why

`.plans` drifts from reality when work happens outside OpenLanes: plans that already shipped, plans that conflict, plans that stalled. A person has no direct way to take a plan out of the active list, and the agents keep picking those plans up.

The main case is a project whose `.plans` shows a wall of ⭕ 🛑 💣 and half-finished states for features that were built some other way. Clearing that must be one command from whatever state each plan claims. It needs no pull request, no `plan.md`, no answered `blocked.md` and no legal path through the spine. Leftover files such as an unanswered `blocked.md` stay in the folder and cannot pull the plan back out, because the reason file outranks them (X4).

## X1. Three states, three words, three directories

| State     | Key         | Emoji | Directory           | Meaning                                                                                                                                        |
| --------- | ----------- | ----- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Abandoned | `abandoned` | 👎    | `.plans/abandoned/` | Work stopped before the plan was completed, without a clear decision to cancel it. It might be resumed.                                        |
| Discarded | `discarded` | ❌    | `.plans/discarded/` | Someone deliberately decided the plan should not proceed. It is kept as a record of that decision.                                             |
| Trashed   | `trashed`   | 🚮    | `.plans/trashed/`   | Removed from the workspace: already done outside OpenLanes, will never be done, conflicts with another plan, or needs restarting from scratch. |

- A plan can be abandoned and later discarded or trashed, and discarded and later trashed. Its earlier reason files stay in the folder.
- Each directory holds a tiny `README.md` explaining this distinction. It is written when a command or `resync dirs` first creates the directory, and the text comes from one place in the code rather than three copies.

## X2. The commands

```
ol plans abandon NNN.MM [NNN.MM ...] [--reason TEXT] [-n]
ol plans discard NNN.MM [NNN.MM ...] [--reason TEXT] [-n]
ol plans trash   NNN.MM [NNN.MM ...] [--reason TEXT] [-n]
```

- `plans` stays the plan table; the subcommands register beside it the way `worktree prune` sits beside `worktree`.
- Plan ids take the same forms other commands accept (`003`, `003.01`).
- Every id is resolved before anything moves. One unknown id refuses the whole command with nothing changed.
- `--reason` gives every listed plan the same reason and asks nothing.
- With no `--reason` and no terminal, the command refuses. It never hangs waiting for input.
- `-n` / `--dry-run` prints what would move and writes nothing.
- A plan already in the requested state is reported and skipped; its reason file is not overwritten.
- Prompts use `tty-prompt` on STDERR, as `init` does.

## X3. Asking for a reason

`trash`, per plan, as a single-choice select:

```
Trashing plans [ 003.00, 007.00 ]:

1. Plan 003.00: Tax Rule DSL
   State: ⚪ New

Why are we trashing it today?

   [✔] This plan is already implemented, but outside of OpenLanes
   [ ] This plan conflicts with another plan so we are scrapping it
   [ ] This plan is no longer relevant
   [ ] This plan is poorly spec'd and needs to be re-started anew
   [ ] Some other reason
```

"Some other reason" follows with `Reason for scrapping this plan:` and free text. It may not be blank.

`abandon` and `discard` ask for free text only, and may not be blank:

```
Please provide a reason for discarding this plan:
>
```

`abandon` words it "abandoning". "Re-started anew" only trashes the plan; it does not create a replacement.

## X4. The reason file is the state

- Each state's file is `<state>-reason.md`: `abandoned-reason.md`, `discarded-reason.md`, `trashed-reason.md`.
- Each holds the reason, the date, and the state the plan was in before the move.
- A non-empty file qualifies the plan for that state. Whitespace alone does not count.
- `ol resync dirs` moves an active plan holding one into the right directory with the right emoji, so writing the file by hand is equivalent to running the command.
- With several present, the order is trashed, then discarded, then abandoned. These three outrank every other state in `PREFERENCE`.
- Deleting the file reverses it: the next `resync dirs` puts the plan where its remaining files say. A 🟡 comes back as ⭐, because contents cannot tell those apart. There is no separate restore command.

## X5. Compatibility with what exists today

- `discarded.md` keeps qualifying a plan as ❌ alongside `discarded-reason.md`, because existing plans carry it.
- The PR watcher (`engine/pr_outcomes.rb`) writes `discarded-reason.md` from now on.
- `.plans/abandoned/` holds ❌ plans today. `resync dirs` moves them to `.plans/discarded/` because their state says so, keeping the date already in their names.
- ❌ stops being terminal, since it can go on to 🚮. 🚮 becomes the only terminal state. The note on ❌ changes from "dropped for good" to say it was decided against and kept as a record.

## X6. What each state does to the rest of the system

|                                                                            | 👎               | ❌               | 🚮               |
| -------------------------------------------------------------------------- | ---------------- | ---------------- | ---------------- |
| Agents leave it alone (`SETTLED`)                                          | yes              | yes              | yes              |
| Plans with `depends_on:` on it keep waiting                                | no, rewired (X9) | no, rewired (X9) | no, rewired (X9) |
| Stops counting as a waiting dependent in the aging sweep (`Aging::CLOSED`) | yes              | yes              | yes              |
| Hidden from "Choose an existing plan" (`Snapshot::FINISHED`)               | yes              | yes              | yes              |
| Number stays reserved                                                      | yes              | yes              | yes              |
| Listed by `ol plans --all`                                                 | yes              | yes              | yes              |

- None of the three leaves dependents waiting on the removed plan, because the purpose of these commands is to clear plans standing in the way of building. X9 says how. Today's ❌ keeps dependents waiting; this changes that.
- The moves use `OpenLanes.move_directory` (`git mv`), which stages and does not commit. Committing stays with the person.

## X7. Things the commands do not touch

- Open pull requests stay open on GitHub; the command prints a warning naming them. A later merge or close of such a pull request must not move the plan back out of 👎 ❌ 🚮.
- The PR watcher keeps updating `pull-requests.md` rows for plans in those three directories, and changes nothing else about them, so a plan restored later is judged on true rows.
- Known limit: an open pull request's branch may carry its own copy of the plan folder under the old top-level name. Merging it can cause a rename conflict, or a second active folder with the same number. The warning says to close the pull request first or expect this. `Tree#duplicates` reports a duplicate; nothing repairs it automatically.
- Worktrees and branches stay where they are.
- If an agent is currently working on the plan, the command refuses for that plan, names it, and exits non-zero after handling the rest.

## X8. State machine edges

- `abandon`: from every state except `abandoned`, `discarded`, `trashed`.
- `discard`: from every state except `discarded`, `trashed`.
- `trash`: from every state except `trashed`.
- Going the other way is X4's file deletion, not an event.

## X9. Removing a plan rewires the graph around it

`A -> B` means A depends on B. Given `A -> B -> C`, moving B to any of the three directories rewrites A's `spec.md` so that `A -> C`: an ordering the plans declared must survive the removal of the plan in the middle.

- Build the graph from every declared `depends_on:` first, and rewrite only then.
- Each dependent replaces B with all of B's own dependencies, without duplicates. With `A -> B`, `B -> C` and `B -> D`, A ends up depending on C and D.
- B's dependencies that are already done (✅ 😎) are not inherited; the gate would ignore them anyway.
- If B has nothing left to pass on, A simply loses the entry, and A's list may end up empty.
- Several plans removed in one command give the same result in any order: `A -> B -> C -> D` with B and C trashed leaves `A -> D`.
- A plan never comes to depend on itself; such an entry is dropped.
- Only the `depends_on:` line changes. Dependents rewritten are every plan not in `archive/`, `abandoned/`, `discarded/` or `trashed/`, so `deferred/` plans are included.
- `resync dirs` runs the same rewiring when a hand-written reason file moves a plan, so the two paths cannot differ.
- `-n` prints each rewrite without making it. A real run prints each one as `A: B → C, D`.
- The reason file records each rewrite, for the person restoring the plan.
- Restoring a plan does not rewire anything back. A dependent that should wait for it again is edited by hand. This holds for 👎 too: by the time an abandoned plan is resumed, the plans on either side of it may be gone, so its old edges are not worth preserving.
- The dependency gate also treats an entry naming a 👎 ❌ 🚮 plan as met, so an edge the rewrite never saw (a plan restored later, a hand edit) cannot hold a plan forever. The plan table reports such an entry as ignored, as it already does for done plans.

## Out of scope

`ol plans move --to <state> --pr N`, for plans whose open or merged pull requests are not reflected in their state. Raised in the same conversation, not decided, not built here.

## Left to the builder

- Where the command logic lives (`Lifecycle` facade, one operation with three configurations).
- Placing the new states in `linear/mapping.rb`, following "when adding a state" in `CLAUDE.md`, and regenerating the docs that derive from `STATUSES`.
- Updating `skills/openlanes-documents` and its closing templates.

<sub>Lifted verbatim from [`docs/decisions/decisions-on-plan-abandon-discard-trash.md`](https://github.com/kigster/openlanes/blob/main/docs/decisions/decisions-on-plan-abandon-discard-trash.md).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`docs/decisions/decisions-on-plan-abandon-discard-trash.md`](https://github.com/kigster/openlanes/blob/main/docs/decisions/decisions-on-plan-abandon-discard-trash.md)
