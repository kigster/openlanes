# 007.00 Plan Folder Naming — front end

Built by `frontend-coder`, after B4 lands the `locked` field in `Live::Snapshot`.

## F1. Control room: new emoji set and 🔑

- **Discipline:** front end.
- **Owns:**
  - `web/src/panels/support.ts` (`BLOCK_EMOJI` holds both `⭕`/`🛑` and the old `⭕️`/`🅱️`, so a snapshot from an unmigrated repo still marks blocked plans)
  - `web/src/board/model.ts` (block marks use the N2 emoji; a plan with `locked` shows 🔑)
  - `web/src/board/Car.tsx` (renders the 🔑 mark, with `host` and `started_at` in its title)
  - `web/src/api/types.ts` (`locked: { pid: number; host: string; started_at: string } | null` on the plan type)
  - tests: `web/src/panels/support.test.ts`, `web/src/board/model.test.ts`, `web/src/board/Board.test.tsx`
- **Must not touch:** anything under `lib/`, `spec/`, `bin/`; the web board's agent-name parsing (research §1: unaffected).
- **Depends on:** B4 (the snapshot shape above).
- **Done when:** `support.test.ts` asserts old and new block emoji are both recognised; `model.test.ts` asserts the 🔑 mark for a locked plan and none for `locked: null`; `Board.test.tsx` renders a locked car; the web test suite and its lint are green.
