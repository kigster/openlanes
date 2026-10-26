---
created: 2026-10-16
lane: plan
depends_on: ["032.00"]
---

# Three Quality Levels

## What we are trying to achieve

In 032 `032.00━━✅━━❯[2026-10-19]━━desired-codebase-quality` we introduced the `desired_codebase_quality` parameter to `.openlanes.yml`, and replaced `build_quality`. 

Unfortunately it's become clear that three levels of quality are desired, not two. Therefore this spec is a slight modification on the 032.00. 

## Why it matters

The three quality levels control various defaults agents use and harness applies to the software development loop. 

## What already exists

* `Config::KEYS` contains `desired_codebase_quality`; `QUALITIES = %i[high mvp]`; anything else is an error naming the file. `to_yaml` writes it back.

- `Config#max_rejections` defaults from it, M5's columns: `high` 2, `mvp` 1; unset stays 2. `merge.max_rejections` still beats it.
- `Config#quality_unset?` says the key is missing. amended: round 1 review, `Config#quality` had no caller and is removed.

## How It Shold be Working

We would like to:

1. Add a middle layer between "high" and "map" called "standard": `QUALITIES = %i[high standard mvp]`
2. Make this setting **required** during the `init` questionaire
3. If working on the project with `.openlanes.yml` that does not have this entry, block any work, until the user provides the answer. Ask it in the terminal as well as on the UI, with three options explained as follows (these options are not just shown to the user, they must be written into the `.plans/decisions.md`)
   1. **high** — the highest quality software design, modularity, low inter-module coupling, high intra-module cohesion, use of design patterns, events, immutability, functional programming, at the cost of potentially slower delivery,  more rounds per plan, high standards for accepting the review. For OOPS codebases, SOLID principles for classes, maximum reuse. Highest sophistication UI with best practices across the board.
   2. **standard** — a reasonable middle ground. Similar modularity and test coverage, but less strick on SOLID principles, immutability and functional programming. Still full test coverage, likely less rounds and faster delivery.
   3. **mvp** — the fastest and potentially least well designed codebase, suitable for fast MVPs and proptotyping, but not recommended for real software with paying customers. Cheapest to produce in terms of AI tokens, and the most likely to have bugs and (if UI is involved) less sophisticated UI.
4. Each level carries a slightly different workflow and standards for addressing PR feedback and automatic merging.

### Hwo it Maps to Execution

> [!NOTE]
>
> This table shows what the values of `desired_codebase_quality` decide:

| desired_codebase_quality                                     | `mvp`                         | `standard`                                                   | `high`                                                       |      |
| ------------------------------------------------------------ | ----------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ---- |
| feature, label, PR review result below ↓                     |                               |                                                              |                                                              |      |
| `review-ok-not-perfect` PR at the 👀 → 🧪 hand-off             | Goes on to verification       | Goes back to backend-coder and frontend-coder, plan moves to 🟡                   | Goes back to backend-coder and frontend-coder, plan moves to 🔴                   |      |
| `review-approved` PR at the 👀 → 🧪 hand-off                   | Skips verification            | Goes on to verification                                      | Goes on to verification                                      |      |
| Send-back counted as a rejection                             | No send-back, nothing counted | verifier runs, and rejects it if it finds a serious visual bug. Dispatcher's `merge.max_rejections` and the arbitrator see it and a PR can't loop | `Outcome#send_back_for_quality` signs it for verifier (`rejected: …; signed by harness`), so `merge.max_rejections` and the arbitrator see it and a PR can't loop |      |
| `Dispatcher#approved` treats 🔴 after a hand-off as its result | Never reached                 | Reached                                                      | Reached                                                      |      |
| Default depth, not wired yet                                 | fast                          | medium                                                       | deep                                                         |      |
| Levels of feature investigation:                             | Plan, Quick                   | Full, Plan, Quick                                            | Full, Plan, Quick                                            |      |
| researcher (researcher) is used for full plan features             | N/A                           | Based on the plan                                            | Based on the plan                                            |      |
| Default Number of Build Rounds                               | 2                             | 2                                                            | 3                                                            |      |
|                                                              |                               |                                                              |                                                              |      |

## Same under both values

- With the key missing, the plan stays 👀 and the project gets asked once (U3). The answer gets appended to `.openlanes.yml` and counts mid-run.
- Builders reply to every non-✅ comment when a PR is sent back (U4). That only happens under `high` in practice, since `mvp` never sends a PR back for this reason.
- The last three table rows belong to the follow-up plan "Quality drives depth and models", not this one.

## How to tell it's working?

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.
