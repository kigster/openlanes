---
execution: concurrent
---
Not a refactor (no `implementation_requirement: refactor`, nothing moved or renamed), so the share check does not apply; threshold 50 percent.

# Plan 068.00: Unblock Interview Chat

## Decisions on the spec's open points

- **Who interviews:** a new `Live::Interview::Operator`, built like `Live::Copilot::Operator` (one `claude -p` session, resumed per turn) but running the **unblocker's** agent profile with an interview brief. Not the run's copilot: its stream is one per node, shared by every plan, and the interview must be kept per question.
- **Scope:** one interview per open question. The confirmed decision is the answer to exactly that question, so the write path is the one `answer` already uses.
- **Model:** whatever `agents/unblocker.md` resolves to through `Agents::Profile` (Opus after PR 216). No new knob.
- **Nothing written early:** the interview lives in Redis only. The single write is the confirm command, through `Commands#write_answer`, so the drain folds it unchanged.
- **Leaving:** closing the panel deletes nothing; the question card keeps its buttons and text box, and an answer given there ends the interview (confirm refuses once the question is answered).

## Order and dependency graph

```
B1 interview store ──┬─> B2 operator + brief ──┐
                     └─> B3 confirm command ───┴─> B4 HTTP + demo ─> F1 client ─> F2 panel ─> F3 Cypress (integration)
```

B1 first. B2 and B3 in parallel (disjoint files). B4 after both. F1 after B4's `openapi.yaml`. F2 after F1. F3 last.

## Backend

### B1 Interview store

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/interview.rb` (new), `lib/openlanes/live/keys.rb` (add `#interview(plan, number)`), `spec/openlanes/live/interview_spec.rb`
- **Must not touch:** `lib/openlanes/live/copilot.rb`, `lib/openlanes/live/commands.rb`, `web/`
- **Depends on:** nothing
- **Done when:** `spec/openlanes/live/interview_spec.rb` passes.
- **Shape:** `Live::Interview` over one Redis stream per plan and question (`Keys#interview`), with `#history`, `#say(turn)` and `#close`. `Interview::Turn` (`Data.define`): `id`, `from` (`you` | `unblocker`), `kind` (`text` | `question` | `decision`), `text`, `options` (lettered, one recommended, for `question`), `answer` (for `decision`). `Turn.check` refuses a `question` or `decision` turn whose text holds a bare label (`/\b[BAUD]\d+\b/`), and a `question` without exactly one recommended option. Turns are published as `event: interview` with plan and number, the way copilot turns are.

### B2 Interview operator and brief

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/interview/operator.rb`, `lib/openlanes/live/interview/brief.rb`, `agents/unblocker.md` (an `## Interview` section only), `spec/openlanes/live/interview/operator_spec.rb`, `spec/openlanes/live/interview/brief_spec.rb`
- **Must not touch:** `lib/openlanes/live/copilot/**`, `lib/openlanes/live/commands.rb`, `lib/openlanes/web/app.rb`
- **Depends on:** B1
- **Done when:** both spec files pass with the `spawn:` seam doubled; no example reaches `claude`.
- **Shape:** `Operator.new(root:, plans_dir:, stores:, keys:, agent: Agents.find("unblocker"), spawn:)`, `#call(turn) -> [Turn]`. `Brief` carries the question's context and options, the plan's `spec.md`/`plan.md`, and the rules: one question at a time with a recommended answer; never reject (an unclear reply gets a clarifying question, or "here is what I understood, yes?"); no bare labels; finish with one `decision` turn. Model output is JSON turns checked by `Turn.check`; a refused turn goes back to the model as a rephrase request, never shown to the person as a refusal.

### B3 Confirm command

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/commands.rb` (new `confirm_interview`), `lib/openlanes/live/command.rb` (register the verb), `spec/openlanes/live/commands_interview_spec.rb`
- **Must not touch:** `lib/openlanes/live/interview*`, `web/`
- **Depends on:** B1
- **Done when:** `spec/openlanes/live/commands_interview_spec.rb` passes: the written `blocked.md` is byte-identical to what `answer` writes for the same text, `Lifecycle::Unblocker` drains it, and a second confirm, or a confirm after a button answer, is refused.
- **Shape:** payload `{plan, number, turn}`; reads the `decision` turn's `answer` from the interview, calls the existing `write_answer`, then closes the interview.

### B4 HTTP routes, events, demo responder

- **Discipline:** back end
- **Owns:** `lib/openlanes/web/app.rb`, `lib/openlanes/web/context.rb`, `lib/openlanes/web/events.rb`, `lib/openlanes/web/demo.rb`, `openapi.yaml` in this plan folder, `spec/openlanes/web/interview_routes_spec.rb`
- **Must not touch:** `lib/openlanes/live/**`, `web/src/**`
- **Depends on:** B2, B3
- **Done when:** `spec/openlanes/web/interview_routes_spec.rb` passes, including a `--demo` sequence of open, two replies and confirm.
- **Shape:** `GET /api/plans/:plan/questions/:number/interview` → `{turns: [Turn]}`, seeding the opening turn when empty; `POST` same path `{text}` → `202`, the reply arrives as `event: interview`. Confirm goes through the existing `POST /api/commands` with `confirm_interview`. Demo responder: two canned questions, then a decision, so Cypress needs no agent.

## Frontend

### F1 Interview client and hook

- **Discipline:** front end
- **Owns:** `web/src/api/interview.ts`, `web/src/api/interview.test.ts`, `web/src/interview/useInterview.ts`, `web/src/api/types.ts` (add `InterviewTurn`)
- **Must not touch:** `web/src/copilot/**`, `web/src/panels/**`
- **Depends on:** B4
- **Done when:** `web/src/api/interview.test.ts` passes under `npx vitest run`.
- **Shape:** `fetchInterview(plan, n)`, `sendInterview(plan, n, text)`, `confirmInterview(plan, n, turnId)`; `useInterview` merges history with `event: interview` turns, so a reload or second machine shows the same conversation.

### F2 Interview panel and entry points

- **Discipline:** front end
- **Owns:** `web/src/interview/InterviewPanel.tsx`, `web/src/interview/interview.css`, `web/src/interview/InterviewPanel.test.tsx`, `web/src/panels/UnblockWidget.tsx`, `web/src/panels/AskCard.tsx`
- **Must not touch:** `web/src/copilot/**` (import its pieces, do not edit), `lib/`
- **Depends on:** F1
- **Done when:** `web/src/interview/InterviewPanel.test.tsx` passes: question turns render buttons with the recommended one marked, a typed reply is sent, the decision turn shows Confirm, and closing the panel leaves the card's buttons usable.
- **Shape:** a panel in the copilot's look; "Talk it through" on each question card and in the Unblock widget opens it for that question.

### F3 Cypress interview spec (integration check)

- **Discipline:** front end
- **Owns:** `web/cypress/e2e/interview.cy.ts`
- **Must not touch:** every other file
- **Depends on:** F2
- **Done when:** `bin/web-e2e` passes `interview.cy.ts`.
- **Integration check:** against the real `--demo` server, nothing stubbed: open the demo board's blocked plan, Talk it through, answer two questions (one by button, one typed), reload and see the same conversation, confirm; the question card must disappear and the plan's `blocked.md` (via the plan file popup) must hold the answer.

## HTTP surface

Yes. `GET` and `POST /api/plans/:plan/questions/:number/interview`, and a new command verb `confirm_interview`. `backend-coder` writes `openapi.yaml` beside `contract.md` in B4.

## Task completed when

- From a blocked plan a person opens a conversation with the unblocker, is asked one question at a time, and ends with a decision they confirmed
- The confirmed decision unblocks the plan with no further typing
- An unclear answer in the conversation produces a follow-up question, never an 'answer not accepted' note

## How to test

- bundle exec rspec
- cd web && npx vitest run
- bin/web-e2e, with a Cypress spec that opens the interview on the demo board's blocked plan, answers two questions and confirms

## Rebase decisions

- `docs/architecture/README.md`: took main's side, then regenerated with `just update-architecture`; it is derived output, so hand-merging counts would only go stale.
- `lib/openlanes/live/command.rb`: kept main's `extend_time`/`rule_finding` and added `confirm_interview` to KINDS, PLAN_KINDS and its `question turn` PAYLOAD.
- `lib/openlanes/live/commands.rb`: kept main's HANDLERS (incl. `extend_time`, `rule_finding`) and added `confirm_interview`.
- `lib/openlanes/web/context.rb`: kept main's `root:` initializer and added the branch's `interview:` keyword.
- `web/src/api/events.ts`: union of imports, `BoardDelta` from main plus `InterviewEvent` from the branch.
