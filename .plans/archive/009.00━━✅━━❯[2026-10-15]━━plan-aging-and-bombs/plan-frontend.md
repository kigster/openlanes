# Plan 009.00 — front end

`frontend-coder` builds this against the contract in `plan.md`. It can start as soon as the contract is fixed; it is verified against the real snapshot once B6 lands.

## F1 Bomb notice, answer box and buttons

- **Discipline:** front end
- **Owns:** `web/src/panels/BombNotice.tsx` (new), `web/src/panels/BombNotice.test.tsx` (new), `web/src/panels/index.ts`, `web/src/panels/command.ts`, `web/src/copilot/useCopilot.ts`, and the snapshot type that gains `bombs`.
- **Must not touch:** `lib/**`, `spec/**`, `UnblockWidget.tsx`, `AskCard.tsx`.
- **Depends on:** the contract in `plan.md`; B6 for live verification.
- **Builds:**
  - One full-width notice per entry in `snapshot.bombs`, above the board.
  - Left: `blocked_md` rendered with the existing markdown renderer. Right: answer box with **Respond** (sends `respond` with the box text, disabled while empty) and **Pause and Discuss** (sends `pause_discuss`, then opens the copilot with the plan loaded; changes nothing else).
  - **Resume anyway for 24 h** button (sends `resume_anyway`); when `resume_until` is in the future the notice shows "halt lifted until <time>" instead of the button.
- **Done when:** `BombNotice.test.tsx` shows: renders one notice per bomb; Respond sends `{kind: "respond", plan, text}`; Pause and Discuss sends `{kind: "pause_discuss", plan}` and opens the copilot with that plan; Resume anyway sends `{kind: "resume_anyway", plan}`; no notice when `bombs` is empty. The web test suite and lint are green.
