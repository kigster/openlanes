# Plan: front end (`rey-frontend`)

Order and the dependency graph are in `plan.md`. The interface here is the terminal board and the web page.

## F1. Unacked count, `last-known-state`, and the renamed file list on the board and the web page

- **Discipline:** front end
- **Owns:** `lib/openlanes/engine/board.rb` (and its row class under `lib/openlanes/engine/board/` if the count lives on a row), `lib/openlanes/web.rb` (including the file list at line 25: `implementation-plan.md` → `contract.md`, `plan-backend.md` / `plan-frontend.md` dropped with `plan.md` kept), `lib/openlanes/web/app.rb`, `lib/openlanes/web/context.rb`, the web view templates they render, `spec/openlanes/engine/board/unacked_spec.rb` (new), `spec/openlanes/web/plan_page_spec.rb` (new, or the existing web spec that covers the plan page)
- **Must not touch:** `lib/openlanes/plans/*`, `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/engine/runner.rb`, `agents/*.md`
- **Depends on:** B1 (`Mailbox#unacked`), B2 (`PlanState#last_known_states`)
- **Shape:**
  - The board shows the unacked count per plan, and a warning glyph and line when it is above zero. Informational only: it reads, it never feeds a decision.
  - The web page shows the same count and warning, and a `last-known-state` table per agent (source, round, status, next step) when the section exists; nothing when it does not.
  - Colours through `UI` as elsewhere; cover the coloured path by stubbing `UI.color?`.
- **Done when:** `spec/openlanes/engine/board/unacked_spec.rb` asserts zero shows nothing and two shows the count and warning; `spec/openlanes/web/plan_page_spec.rb` asserts the count, the `last-known-state` rows, and a file list naming `contract.md` and not `implementation-plan.md`.

## F2. Integration check: mail round trip through the CLI into the board and the page

- **Discipline:** front end
- **Owns:** `spec/integration/mail_round_trip_spec.rb` (new)
- **Must not touch:** every file another unit owns; this unit writes one spec and nothing else
- **Depends on:** B1, B2, B3, B4, B5, F1
- **What it must show, nothing stubbed** (a real `:tree` plan folder, the real `exe/openlanes` CLI, the real `Board` and web app rendered through `Rack::MockRequest` or the app's own test client):
  1. `openlanes mail send` from `luke-backend` to `rey-frontend` writes `state.json` with `read: "no"`, both with Redis unavailable and with a `Live::MemoryStore` behind the dispatcher thread, and the message appears exactly once.
  1. The board and the web page both show one unacked message and the warning.
  1. `openlanes mail ack` flips it; both views show zero and no warning.
  1. `openlanes mail render` prints the exchange and the plan folder is byte-for-byte unchanged.
  1. A runner round over the same tree assigns the same agents with and without the unacked message.
  1. An agent killed without `state resume` leaves a `source: "harness"` entry that the web page renders.
- **Done when:** `spec/integration/mail_round_trip_spec.rb` passes, and the whole suite and `just lint` are green with coverage at or above 98.63%.
