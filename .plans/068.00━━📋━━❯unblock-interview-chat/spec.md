---
created: 2026-11-12
starts: planning
depth: medium
frontend: true
implementation_suggestions:
  - "Reuse the copilot panel the page already opens on a plan for Pause and Discuss (`pause_discuss` in `lib/openlanes/live/commands.rb`, `lib/openlanes/live/copilot/`), with the unblocker's brief in place of the copilot's"
  - "Model the interview on the grill-me skill: one question at a time, each with a recommended answer"
  - "Start it from the Unblock button on a blocked lane and from a 'Talk it through' control on a question card"
implementation_requirements:
  - "The interviewing agent never rejects what a person says; it asks the next clarifying question, or says back what it understood and asks for a yes"
  - "Every question it asks stands alone: plain words, no bare labels such as B2 or A9"
  - "Nothing is written to `spec.md`, `plan.md` or `blocked.md` until the person confirms the decision the interview arrived at"
  - "On confirmation the decision is written as the answer to that question in `blocked.md`, in exactly the form the answer box writes, and the normal drain folds it"
  - "A person can leave the interview at any point and still answer with the buttons or the text box"
  - "The interview is kept, so a reload or a second machine shows the same conversation"
task-completed-when:
  - "From a blocked plan a person opens a conversation with the unblocker, is asked one question at a time, and ends with a decision they confirmed"
  - "The confirmed decision unblocks the plan with no further typing"
  - "An unclear answer in the conversation produces a follow-up question, never an 'answer not accepted' note"
---
# Unblock Interview Chat

Source: the owner, 2026-11-12: "In the blocking scenario it would be good to have a /grill-me session with the unblocking agent via the UI."

## What we are trying to achieve

When a plan is blocked on a question the person does not understand, or cannot answer in one click, they talk it through with the unblocker in the control room. The agent explains what is being decided, asks one question at a time with a recommended answer each, and finishes by stating the decision for the person to confirm. The confirmed decision is the answer.

## Why it matters

Today a question is one card and one answer. On 2026-11-12 a person answered a question with "What is the question?" and "what is B2?", because the card referred to things by label, and the unblocker bounced each answer back. There was no way to ask the agent anything. Pull request 216 makes questions stand alone and stops the bouncing; this plan adds the conversation.

## What already exists

- The unblocker, `agents/unblocker.md`, which drains answered questions out of `blocked.md` and, after pull request 216, asks a follow-up on the card when it cannot read a decision.
- Pause and Discuss: every agent holds and the page opens the copilot on the plan (`pause_discuss`, `respond`, `lib/openlanes/live/copilot/`).
- The Unblock button on a blocked lane (pull request 209), which brings that plan's questions to the front of the rail.
- `Lifecycle::ReasonInterview`, and decision M6 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`: a new idea is interviewed, one question at a time, before its spec is saved.

## Open, for the planner to settle or ask

- Whether the interviewer is the unblocker itself or the copilot given the unblocker's brief and the plan's documents.
- Whether one interview covers every open question on a plan or one question each.
- Which model it runs on; the unblocker is Opus after pull request 216.

## How to tell it's working?

- bundle exec rspec
- cd web && npx vitest run
- bin/web-e2e, with a Cypress spec that opens the interview on the demo board's blocked plan, answers two questions and confirms
