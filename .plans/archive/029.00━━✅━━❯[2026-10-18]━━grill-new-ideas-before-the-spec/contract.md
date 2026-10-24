# Contract: 029.00 Grill new ideas before the spec

`spec.md` says `starts: planning` and `plan.md` has no `## Frontend` units, so rey-frontend is not started. luke-backend owns both halves.

## Baseline

Full suite before any change: 0 failures (`bundle exec rspec`), per CLAUDE.md. `bundle exec rubocop`: 0 offenses.

## Interfaces

### `POST /api/interview`

- Header `X-CSRF-Token` (the session's), body `{"idea": String}`.
- 200 `{"questions": [{"context": String, "options": [String], "recommended": Integer}]}`: at most 5 questions, 2 to 5 options each, `recommended` is the index of the one recommended option.
- 200 `{"questions": [], "reason": String}` when there is no interviewer (`OPENROUTER_API_KEY` unset) or it failed. The page then creates the plan as before.
- 422 `{"error"}` when `idea` is blank or the body is not a JSON object. 403 on a stale token.

### `create_plans` command, `payload.decisions`

- Optional `[{"question": String, "answer": String}]`. Each entry with both fields non-blank becomes `- **<question>** <answer>` under `## Decisions` in the seeded `spec.md`, after the idea.
- Absent or empty (interview skipped): no `## Decisions` section; `spec.md` as before.

## File ownership

All luke-backend: `lib/openlanes/live/interviewer.rb`, `lib/openlanes/live.rb`, `lib/openlanes/live/commands.rb`, `lib/openlanes/web/app.rb`, `web/src/api/client.ts`, `web/src/panels/IdeaDialog.tsx`, and their specs.

## Build order

1. `Live::Interviewer` (OpenRouter via inquirex-llm, questions checked through `Plans::Choices`).
2. `POST /api/interview`.
3. `create_plans` writes `decisions`.
4. Idea dialog: "Break it into plans" fetches questions, asks them one at a time (recommended option highlighted and labelled), "Skip the interview" sends with no decisions.

## Integration proof

`spec/openlanes/web/app_spec.rb` "POST /api/interview" plus `spec/openlanes/live/commands_spec.rb` "with the interview's decisions (M6)": a real request through the Sinatra app, and a real `create_plans` written into a temp `.plans` tree. The dialog step is covered by `web/src/panels/dialogs.test.tsx` (interview, recommended marking, skip).
