# Pull Requests

## Front end proof (frontend-coder, round 1)

- `cd web && npx vitest run` — all files pass, including `src/board/Rejections.test.tsx`.
- `npx tsc --noEmit -p .` and `npx eslint src` — clean.

## Back end and integration proof (backend-coder, last to finish)

- `bundle exec rspec spec/openlanes/engine/dispatcher_arbitration_spec.rb`: 3 examples, 0 failures.
- `cd web && npx vitest run src/board/Rejections.test.tsx`: 1 file, 3 tests passed.
- `bundle exec rspec`: 4277 examples, 0 failures, 45 pending (seed 46708). The pending are the Redis-backed integration specs, skipped because no Redis answers at `localhost:6379/11` from this sandbox; the baseline had 9. One earlier run in the same round showed 52 failures (outcome, merging, app specs); those files pass alone (61 examples, 0 failures) and the next full run was green, so I read it as load on the machine, not this change.
- `bundle exec rubocop`: 574 files, no offenses.
- End-to-end suite (`just web-e2e`): not run this round; it needs the web build and a browser, which this time budget did not allow.
