# Contract — 057.00 Config Schema and Main Checkout

No front end in this plan (`plan.md`, `## Frontend`: none; plan 058 renders the settings page), so frontend-coder is not started and there is no mailbox exchange.

## Baseline

Before round 2's changes: 6418 examples, 1 failure, 9 pending. The failure was `spec/openlanes/docs/architecture_doc_spec.rb:13` (`docs/architecture` stale after round 1's new `Config::Schema` methods), fixed by `just update-architecture`.

## Interfaces plan 058 will read

- `OpenLanes::Config::Schema.document`: the whole JSON Schema (draft 2020-12), `commands` built from the CLI registry.
- `OpenLanes::Config::Schema.defaults`: every key with its default; nested sections as Hashes.
- `OpenLanes::Config::Schema.errors(settings)`: json_schemer errors, empty when valid.
- `OpenLanes::Config#to_yaml`: the whole file, every schema key in schema order, unset ones empty.
- `OpenLanes::Config.parse`: refuses with `"<path>: <key>: <problem>"`; an empty value reads as unset.

## Integration proof

`spec/openlanes/config_schema_integration_spec.rb`: runs `exe/openlanes init -n -y` as a subprocess in a temp git repository, validates the output against the checked-in schema, checks every key is present, loads it back with `Config.load` and compares `to_yaml`, and checks a corrupted value is refused in today's shape.
