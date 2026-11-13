# Contract 068.00: Unblock Interview Chat

Owner: backend-coder. No code here.

## Baseline

`bundle exec rspec` before any change: recorded at the end of round 1 below.

## Interfaces frontend-coder calls

Full schema: [openapi.yaml](openapi.yaml).

### InterviewTurn (wire shape)

`{id: String, from: "you"|"unblocker", kind: "text"|"question"|"decision", text: String, at: ISO8601, options: [{label: String, recommended: Boolean}] (question only), answer: String (decision only)}`

- A `question` has 2..5 options, exactly one `recommended: true`.
- `question` and `decision` text never holds a bare label such as `B2`.

### GET /api/plans/:plan/questions/:number/interview

- 200 `{turns: [InterviewTurn]}`, oldest first. Empty history is seeded with the unblocker's opening `question` turn.
- 404 `{error}` when the path names no plan or question number. amended: the route checks the shape only, not that `blocked.md` asks the question (the demo board has no plan files).

### POST /api/plans/:plan/questions/:number/interview

- Body `{id: String, text: String}` (id matches `[0-9A-Za-z_-]{1,64}`, text 1..4000 chars).
- 202 `{turn: InterviewTurn}` (the person's turn). The reply arrives as SSE `event: interview` with `{plan, number, turn}`.
- 403 `{error}` without the session's X-CSRF-Token; 404 `{error}` when the path names no plan (`NNN.MM`) or question number; 422 `{error}` for an invalid message; 503 `{error}` when nothing answers interviews in this server.
- amended: no 409. A reply after the question was answered is stored but harmless; confirm is what refuses (round 2, kept the route free of file reads).
- The unblocker's turn ids are `u<n>`, n being the turn's place in the conversation.
- SSE `event: interview` data is `{plan, number, turn}`; it is followed from one repo-wide stream (`Keys#interviews`), so it carries no `id:` and never moves the reply cursor.

### Confirm: POST /api/commands

- `{id, kind: "confirm_interview", plan, payload: {question: "<number>", turn: "<decision turn id>"}}`.
- Writes the decision's `answer` into `blocked.md` exactly as `answer` does, then closes the interview.
- Refused: `the interview has no decision <turn> to confirm`; `this question already has an answer waiting` (answered by button, text box or an earlier confirm).
- Under `--demo` the board settles the question exactly as `answer` does; there is no `blocked.md` to write.
- amended: payload key is `question` (not `number`) so it matches `answer`'s payload.

## File ownership

- backend-coder: `lib/**`, `agents/unblocker.md`, `spec/**`, `openapi.yaml`, `contract.md`.
- frontend-coder: `web/src/**`, `web/cypress/**`.
- Shared: none.

## Build order

B1 store -> B2 operator, B3 confirm -> B4 HTTP + demo -> F1 -> F2 -> F3.

## Integration proof

`web/cypress/e2e/interview.cy.ts` against the real `--demo` server: open, two answers, reload, confirm, card gone, `blocked.md` holds the answer.

## Round 1 status (backend-coder, superseded in round 2)

- Done: B1 interview store (`Live::Interview`, `Keys#interview`), B3 `confirm_interview` command.
- Not done: B2 operator + brief, B4 HTTP routes, events, demo responder, `openapi.yaml`.
- Baseline: full-suite run started before changes; result not captured within round 1 (it had not finished).

## Round 2 status (backend-coder)

- B2: `Live::Interview::Operator` and `Brief`. Built like the copilot's operator, with one difference: the whole conversation goes into each brief and no `claude` session is resumed, so nothing is kept per question beyond the stream. A reply that fails `Turn.check` goes back to the model once, then a plain clarifying question is asked instead.
- B4: the routes, `event: interview`, `Demo::Interview` (two questions, then a decision joining the replies), and `confirm_interview` on the demo board.
- The route spec is `spec/openlanes/web/app_interview_spec.rb`, not `interview_routes_spec.rb`, because rubocop's `RSpec/SpecFilePathFormat` requires `app*_spec.rb` for `App`.
