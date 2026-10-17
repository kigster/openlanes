# Pull Requests

## Verification, luke-backend, round 1

Integration proof:

```text
$ bundle exec rspec spec/integration/runtime_state_spec.rb
4 examples, 0 failures
```

Full suite and lint:

```text
$ bundle exec rspec
3148 examples, 0 failures, 9 pending
$ bundle exec rubocop
438 files inspected, no offenses detected
```

End-to-end suite:

```text
$ just web-build && just web-e2e
All specs passed!  00:21  23 tests, 23 passing, 0 failing
```
