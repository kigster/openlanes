# Contract: An Action Strip per Lane

`frontend: false`: backend-coder built every unit, TypeScript included. No frontend-coder, no mailbox traffic.

## Interfaces

- `GET /api/plans/:ordinal/files` — unchanged route. `files` now may include `pull-requests.md`, in the order
  `spec.md plan.md contract.md research.md design.md blocked.md pull-requests.md`.
- `GET /api/plans/:ordinal/files/pull-requests.md` — readable. `PUT` answers 403 `pull-requests.md is read only`.
- No route added. No `openapi.yaml`.

## File ownership

All files written by backend-coder; no shared-file conflicts.

## Build order

U1 server list, U2 labels and hook, U3 markdown/mermaid, U4 DocumentModal, U5 LaneDocuments in PlanRow, U6 Cypress.

## Integration proof

`web/cypress/e2e/lane-documents.cy.ts` against the real demo server (`just web-e2e`). Not run in this round: see
`pull-requests.md`.

## Baseline

Before the work: Ruby and web suites had no failures recorded in this worktree (CLAUDE.md states the suite is green).

## Amendments

- amended: `PlanRow` tests (Board, PlanCost, Rejections, UnackedBadge) mock `useDocuments`, since `PlanRow` now needs a
  query client through `LaneDocuments`; the app already provides one.
