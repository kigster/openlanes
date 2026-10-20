## How to test

- `bundle exec rspec` and `just lint` stay green.
- `./exe/openlanes agents list` shows `ewoki-linker` with `precedes ready_for_planning, planned`.
- In a temp project with two plans at 📋, where 050's spec mentions 034's parser and has no `depends_on:` key, `./exe/openlanes run --dry-run --isolation shared` reports `would invoke ewoki-linker` for 050 and not for a plan whose spec already has `depends_on: []`.
- `./exe/openlanes evals ewoki-linker` (offline scoring) passes every case.
