# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 39 | [\[009\] Plan aging and bombs](https://github.com/kigster/openlanes/pull/39) | Open 🟡 |

## Verification (luke-backend, last of the pair, 2026-10-15)

Stacked on #23. The integration proof spawns the real `exe/openlanes` against a `PlansFixture` tree, with `claude`, `codex` and `pi` on PATH replaced by scripts that fail if called, and drives the control-room app over HTTP.

```
$ just lint
308 files inspected, no offenses detected

$ PATH=<guard stubs>:$PATH REDIS_URL=redis://127.0.0.1:1 just test
2310 examples, 0 failures        (baseline, #23 alone: 2248 examples, 0 failures)

$ bundle exec rspec spec/openlanes/integration/plan_aging_spec.rb
1 example, 0 failures

$ cd web && npm run lint && npm run typecheck && npm test
eslint: clean; tsc: clean; 28 test files, 300 tests passed
```

What the integration spec asserts:

1. `run --isolation shared --no-web` over two plans blocked 8 days, each with a dependent: exit 1, STDERR names `001.00 Feed` and `003.00 Ports`, both folders are 💣, no agent CLI ran.
2. `snapshot.bombs` lists both with their `blocked.md`.
3. `POST /api/commands` `respond` writes `## A1` into 001's `blocked.md`.
4. The dispatcher drains 001 (lando-broker handles 💣); 001 leaves 💣 and `snapshot.bombs`, while 003 still halts the run.
5. `POST /api/commands` `resume_anyway` on 003 lifts the halt for 24 h, with no `.openlanes.yml` edit.
