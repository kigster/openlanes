# Decisions: inquirex-fixes

## D1. The split plan folder is merged back into one

Asked by luke-backend, 2026-10-13. Answered by kig, 2026-10-13: merge.

An `openlanes unblock` process renamed `010.00-📋` to `010.00-🟡` while palpatine-planner was still writing in it, so `plan-backend.md` and `plan-frontend.md` landed under the old name and recreated a second `010.00` plan folder. Both files now live in `010.00-🟡 → inquirex-fixes`, and the second folder is gone. luke-backend's round 1 on the stray folder wrote no code and is not carried over. The harness bug is recorded in `docs/decisions/decisions-on-blocks-and-escalation.md` (D5, D6).
