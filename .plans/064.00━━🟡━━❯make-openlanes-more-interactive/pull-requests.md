# Pull Requests

## Frontend, round 1

- F1 `boardDelta.ts`, `useBoard.ts`, `events.ts`, `types.ts`: a `board_delta` applies only onto the held version; a mismatch reopens the stream (fresh full `board`). Tests: `boardDelta.test.ts`, `useBoard.test.tsx`, `events.test.ts`.
- F2 `AgentDrawer.tsx`: Extend time +10/+20 (`extend_time`) and Stop after this step (`wrap_up`), running cars only. Test: `AgentDrawer.test.tsx`.
- F3 `PlanReview.tsx`, `planReview.ts`: diff stat, patch toggle, findings with Accept/Strike (`rule_finding`). Test: `PlanReview.test.tsx`. Built against contract §3; backend B3 route was not yet built.
- F4 `Car.tsx`, `PlanRow.tsx`, `AgentDrawer.tsx`, `format.ts`: cost lines. Test: `Car.test.tsx`.
- `npx vitest run`: all pass (538); `eslint` and `tsc` clean.
- NOT run: `web/cypress/e2e/interactive.cy.ts` (written, never executed; needs the B3 route and a running demo server). Not the last agent, so the integration proof is still owed.
