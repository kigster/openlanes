# Pull Requests

## Build, round 1 (luke-backend)

No front end in this plan, so luke is last. Integration proof and checks, run in the worktree:

- `bundle exec rspec spec/integration/event_journal_kill_spec.rb` (fork, SIGKILL, replay): passed.
- `bundle exec rspec` → `4117 examples, 0 failures, 9 pending`, exit 0.
- `bundle exec rubocop` → `556 files inspected, no offenses detected`, exit 0.
