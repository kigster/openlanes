# Pull Requests

## Verification, backend-coder round 1

- `bundle exec rubocop` → 568 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/plans spec/openlanes/config_spec.rb spec/openlanes/engine/dispatcher_spec.rb …` → all in-process examples pass, including the integration proof ("with a refactor that needs the global lock").
- `bundle exec rspec` (full) → 4214 examples, 6 failures, 45 pending. All 6 are `exe/openlanes` subprocesses failing to load gems (concurrent `gem install` rewriting the gem directory); see blocked.md B1.
