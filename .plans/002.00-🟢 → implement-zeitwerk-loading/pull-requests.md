# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 35 | [\[002.00\] Implement Zeitwerk Loading](https://github.com/kigster/openlanes/pull/35) | Open 🟡 |

## Verification (luke-backend, 2026-10-14)

```
$ bundle exec rspec spec/openlanes/integration/thin_commands_spec.rb
6 examples, 0 failures

$ just test
2261 examples, 0 failures        (baseline: 2214 examples, 0 failures)

$ just lint
316 files inspected, no offenses detected
```

What the integration spec asserts, under `NO_COLOR=1`, nothing stubbed:

- `create billing sync --no-draft --no-open` prints `003.00-⚪️ → billing-sync` and exits 0; `create --from missing.md` exits 66.
- `unblock 002 -n` prints `002.00	blocked	1 open	not attempted`, lists `B1. Which vendor`, exits 0; `unblock 999 -n` exits 66.
- `run -n --isolation shared --no-web` prints `001.00  luke-backend` and exits 0; `run --agent nobody` exits 65.

Command sizes, `wc -l`, before and after:

| Command | Before | After |
| :--- | ---: | ---: |
| `cli/create/create.rb` | 354 | 100 |
| `cli/run/run.rb` | 576 | 98 |
| `cli/unblock/unblock.rb` | 235 | 41 |
| `cli/resync/subcommands/prs.rb` | 111 | 50 |
| `cli/start/start.rb` | 97 | 53 |

Each `call` now does option handling, one workflow call, output and exit. The one CLI spec change beyond constants: the two "the publisher" examples moved from `run_spec.rb` to `spec/openlanes/engine/run_workflow_spec.rb` with `publisher_for` (plan decision 6).
