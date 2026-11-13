# Pull Requests

## Round 4, backend-coder

All work units in plan.md were already on `main`. This round fixed the 10 baseline failures (see contract.md):

- `spec/spec_helper.rb`: `Config.current` returns an empty config when the root is this checkout, so the project's `.openlanes.yml` no longer steers the suite.
- `lib/openlanes/live/session.rb`: the probe thread gets its own Redis connection (`RedisClient` is not thread-safe).
- `.openlanes.yml`: `coverage:` section restored (lost in 4fcb6eb2), `minimum: 95`.

Checks:

- `bundle exec rubocop`: 847 files inspected, no offenses detected.
- `bundle exec rspec` (full): 5936 examples, 1 failure (`architecture_doc_spec`, stale docs after the session.rb change), coverage 99.17%. Fixed with `just update-architecture` (`docs/architecture/openlanes-live.md`); `bundle exec rspec spec/openlanes/docs/architecture_doc_spec.rb spec/openlanes/live/session_spec.rb`: 11 examples, 0 failures.
- `coverage.report_command`: prints 99.1740787801779.
