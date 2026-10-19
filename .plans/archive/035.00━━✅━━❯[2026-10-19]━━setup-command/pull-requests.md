# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 82 | [\[035.00\](A) Setup Command](https://github.com/kigster/openlanes/pull/82) | Merged 🟣 |

## luke-backend, round 1 — verification

- `bundle exec rubocop` → 490 files inspected, no offenses detected
- `bundle exec rspec` → 3581 examples, 0 failures, 9 pending; coverage 98.8%
- `./exe/openlanes setup` (this machine) → ✓ brew, Brewfile, claude, gh, redis; exit 0
- `./exe/openlanes setup -n` → "Would install: nothing", same five ✓; exit 0
- gh logged out, gem files, init behaviour: covered by spec/openlanes/cli/setup_spec.rb, spec/openlanes/packaging_spec.rb, spec/openlanes/cli/init_spec.rb
