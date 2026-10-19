# Plan 001.00, back-end half (luke-backend)

Split from `plan.md` by luke-backend on 2026-09-06 because `palpatine-planner` left no discipline split. Every unit below is a task in `plan.md`; the code is already written there and the unit is done when it is on disk verbatim and its spec is green. Line numbers refer to `plan.md`.

## Units

| Unit | plan.md task                    | Lines                   | Owns                                                                                                                                                                                                      | Depends on                              |
| :--- | :------------------------------ | :---------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------- |
| B1   | Task 1: The ledger              | 59-476                  | `lib/agentilda/ledger.rb`, `spec/agentilda/ledger_spec.rb`                                                                                                                                                | none                                    |
| B2   | Task 2: Agent frontmatter       | 477-749                 | `lib/agentilda/agent.rb`, `agents/*.md` frontmatter, `spec/agentilda/agents_spec.rb`                                                                                                                      | none                                    |
| B3   | Task 3: Ready for Planning      | 750-904                 | `lib/agentilda/status.rb`, `lib/agentilda/state_machine.rb`, `lib/agentilda/linear/mapping.rb`, their specs                                                                                               | none                                    |
| B4   | Task 4: pull-requests.md ledger | 905-1019                | `lib/agentilda/pull_request.rb`, `spec/agentilda/pull_requests_render_spec.rb`                                                                                                                            | B1 at runtime                           |
| B5   | Task 5: Child and Clock         | 1020-1402               | `lib/agentilda/child.rb`, `lib/agentilda/clock.rb`, `lib/agentilda/control.rb`, their specs                                                                                                               | none                                    |
| B6   | Task 6: The executor            | 1403-1844               | `lib/agentilda/executor.rb`, `lib/agentilda/transcript.rb`, their specs                                                                                                                                   | B1, B5 at runtime                       |
| B7   | Task 7: The state file          | 1845-2103               | `lib/agentilda/state_file.rb`, its spec, `.gitignore` line                                                                                                                                                | none                                    |
| B8   | Task 8: Dispatcher and runner   | 2104-3127               | `lib/agentilda/board.rb`, `lib/agentilda/dispatcher.rb`, `lib/agentilda/runner.rb` (whole, includes Task 4's `record_pull_request`), `spec/agentilda/runner_spec.rb`, `spec/agentilda/dispatcher_spec.rb` | B1, B3, B5, B6, B7 at runtime           |
| B9   | Task 12: prompts and briefer    | 4017-4079               | `agents/*.md` bodies, `lib/agentilda/brief.rb`, `spec/agentilda/brief_spec.rb`                                                                                                                            | B2 (same files, so run after)           |
| B10  | Task 13: lint config            | 4179-4238               | `.standard.yml`                                                                                                                                                                                           | everything, for the lint run            |
| B11  | shared require list             | Tasks 1, 5, 7, 8, 9, 10 | `lib/agentilda.rb` component list                                                                                                                                                                         | none; done first so every sibling loads |

## Waves

- Wave 1, concurrent: B1, B2+B9 (one agent, same files), B3, B4, B5, B6, B7, B8, plus B10 and B11 by the orchestrator.
- Wave 2, serial, orchestrator: full suite, `standardrb`, fix copy errors only.

## Done when

`bundle exec rspec` reports 0 failures outside the front-end specs Rey owns, and `bundle exec standardrb` is clean under the project-local `.standard.yml`.
