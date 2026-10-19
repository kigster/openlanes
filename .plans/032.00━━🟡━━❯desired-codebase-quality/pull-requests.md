# Pull Requests

## Round 1, luke-backend

- U1 `desired_codebase_quality: high | mvp` in `Config`: validated, written back, drives `max_rejections` (high 2, mvp 1; `merge.max_rejections` beats it). `spec/openlanes/config_quality_spec.rb`.
- U2 hand-off at 👀: `review-ok-not-perfect` goes to 🧪 under mvp, back to 🔴 under high, stays 👀 when unset. `spec/openlanes/engine/dispatcher_verification_spec.rb`, `spec/openlanes/engine/verification_quality_spec.rb`.
- U4 builders answer every non-✅ comment in its thread: `agents/luke-backend.md`, `agents/rey-frontend.md`.
- U5 `openlanes init --quality`, asked on a terminal: `spec/openlanes/cli/init_spec.rb`.
- U3 once-per-project question: `Engine::QualityQuestion` (ask, show as Q1, answer into `.openlanes.yml`), wired into `Verification::Driver`, `Live::Snapshot`, `Live::Commands`; web `Question.kind` gains `quality`. `spec/openlanes/engine/quality_question_spec.rb`, `spec/openlanes/live/commands_spec.rb` (Q1), `spec/openlanes/engine/dispatcher_verification_spec.rb` (asked once, answered mid-run).
- Web typecheck not run: `web/node_modules` is absent in this worktree.

Checks:

- `bundle exec rspec`: 3917 examples, 0 failures, 9 pending
- `bundle exec rubocop`: 522 files inspected, no offenses detected
