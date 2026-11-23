# How plan 060 landed

Moved from `.plans/discarded/` to the archive as Approved & Merged on 2026-11-20 (decision C7 in `docs/decisions/decisions-on-memory-compounding.md`).

It was discarded on 2026-11-14 because its only pull request, #223, closed unmerged after the arbitrator ruled no_go at the rejection cap (finding F5: the review gate was judged on the wrong builder of a pair). By then four of its five items had landed on `main` through other pull requests.

| Item in spec.md | Where it landed |
| :-- | :-- |
| 1. One prepared review packet | #201, commits `c622e0a8`, `0542cf08` (`Execution::ReviewPacket`) |
| 2. Gate review behind lint and tests | Not landed. Built on #223, closed with F5 open. Moves to its own plan (decision C8). |
| 3. Size the builder by the work unit | #245, commit `9c48e587` (`Agents::Sizing`); the Fable 5.2 price in #278 (C12) |
| 4. Handle provider rate limits | #204, commits `b5d58a4f`, `a4616326` (`Execution::Throttle`); pausing new starts per adapter is C13 |
| 5. Split dispatcher.rb | #205 (steps over one Desk) and #243, commit `608dd10a` (`engine/dispatcher/`) |

`blocked.md` (the no_go ruling) and `discarded-reason.md` were removed from the folder; both remain in git history.
