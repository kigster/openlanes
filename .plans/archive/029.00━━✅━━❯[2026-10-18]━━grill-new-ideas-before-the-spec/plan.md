# Plan: Grill New Ideas Before the Spec

## Backend

### B1 Live::Interviewer
One OpenRouter call returns up to 5 D3 questions for an idea; each is validated through `ChoiceConverter.render` and `Plans::Choices`. Done.

### B2 POST /api/interview
Returns the questions, or none with a reason when there is no interviewer. Done.

### B3 create_plans writes decisions
`payload.decisions` becomes `## Decisions` in `spec.md`; none leaves the spec as today. Done.

### B4 Idea dialog interview step
`web/src/panels/IdeaDialog.tsx` and `postInterview` in `web/src/api/client.ts`; covered in `web/src/panels/dialogs.test.tsx`. Done.

## Frontend

## Task completed when

## How to test

- Adding an idea on the page starts an interview; each question shows a recommended answer.
- The saved `spec.md` records the decisions.
- Skipping the interview is possible and leaves the spec as today.
