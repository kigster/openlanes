# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 111 | [\[035.00\](A) Three Quality Levels](https://github.com/kigster/openlanes/pull/111) | Open 🟡 |

## Verification, round 3 (luke-backend)

- `bundle exec rspec`: 3999 examples, 0 failures, 9 pending (`web/dist is missing: run just web-build first`, environmental)
- `bundle exec rubocop`: 527 files inspected, no offenses detected
- No integration proof or e2e suite: rey is not started (`## Frontend` has no units).

## Answers, round 4 (luke-backend)

hansolo's review arrived as one PR conversation comment, not inline review comments (`gh api .../pulls/111/comments` returns none), so there are no threads to reply in. Each finding, answered here:

1. Quality gate starves the integration fixtures: **fix**. `ControlRoomProcess.checkout` (`spec/support/control_room_process.rb`) now writes `desired_codebase_quality: high` to the checkout's `.openlanes.yml`. Every failing spec (`two_checkouts`, `control_room`, `restart`) builds its root through it.
2. Stale `@param answer` doc: **fix**. `lib/openlanes/plans/plan_state.rb` now reads `"high", "standard" or "mvp"`.

## Verification, round 4 (luke-backend)

- `just web-install && just web-build`: built `web/dist`
- `bundle exec rspec spec/integration`: 55 examples, 0 failures (none pending)
- `bundle exec rspec`: 4090 examples, 0 failures, 0 pending
- `bundle exec rubocop`: 548 files inspected, no offenses detected

## Answers, round 5 (luke-backend)

hansolo's round-2 review is again one PR conversation comment, with no inline threads to reply in.

1. `docs/WORKFLOW.md` contradicts the state machine: **fix**. Ran `just update-workflow`; `docs/WORKFLOW.md` now has `in_review --> building` in the mermaid diagram and the 👀 row reads `🟡 🧪 ✅ 🔴 🚫 ❌`. No other line changed.

## Verification, round 5 (luke-backend)

- `bundle exec rubocop`: 560 files inspected, no offenses detected
- `bundle exec rspec` (with `web/dist` built): 4174 examples, 0 failures, 0 pending
