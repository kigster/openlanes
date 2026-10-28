---
created: 2026-10-27
starts: planning
---

# Config Schema and Main Checkout

Source: the user, 2026-10-27, split out of plan 056 (S6). Decisions S0 and S3–S5 were settled there and are copied here unchanged.

## What we are trying to achieve

1. **One JSON Schema for `.openlanes.yml`**, `schemas/openlanes-config.schema.json`: every key's type, allowed values, default and one line of help. `Config.parse` validates against it.
2. **The whole file, every key**: whatever writes `.openlanes.yml` writes every key with its value, the default where nothing else was chosen.
3. **`commands:` from the CLI**: the schema's `commands` part is generated from the dry-cli registry, each command with the options it really declares.
4. **The control room runs from the main checkout**, whichever checkout it was started in.

No UI here: plan 058 renders the page on top of this.

## Why it matters

The settings page (058) needs one source for every key's type, default and help, or the page, the parser and the writer drift apart. And a settings change committed to `main` is only seen by every worktree if the process that commits it runs in the main checkout.

## Decisions (2026-10-27)

- **S0, where the control room runs:** the server, the engine and the web page run once per project, from its main checkout. Started inside a worktree, `openlanes start` changes the process's directory to the main checkout before it boots anything else.
- **S3, every key, with its value:** the point of the page is to show what settings exist. Every key appears with its value, the built-in default where the file is silent, and Save writes the whole file, every key included. The same holds for generating the file: whatever writes a new `.openlanes.yml` (`openlanes init`, `Config#to_yaml`) writes every key with its default. Accepted cost: a project's file pins today's defaults, so a later change to a built-in default does not reach it until someone edits the value.
- **S4, one schema:** `schemas/openlanes-config.schema.json`, beside `plan-state.schema.json`, holds every key's type, allowed values, default and one line of help. `Config.parse` validates against it, the page renders its fields from it, and the full-file writer reads the defaults from it. The constants in `config.rb` that repeat those facts (`KEYS`, `MERGERS`, `MERGE_KEYS`, …) are derived from the schema or removed.
- **S5, the `commands:` pane:** built from the dry-cli registry. One sub-pane per command, listing the options that command really declares, with their types and defaults; the `commands` part of the schema is generated from the registry, so a new flag appears on the page without anyone editing the schema.

## What already exists

- `Config` (`lib/openlanes/support/config.rb`): a `Data.define`; `parse` rejects unknown keys (`KEYS`) and nested keys (`MERGE_KEYS`, `BACKOFF_KEYS`, …); `to_yaml` writes only the keys that are set; `Config.current` is cached by mtime. Its header comment lists every key with a one-line note, the raw material for the schema's help text.
- `schemas/plan-state.schema.json`, the pattern for a checked-in schema.
- `Project.root` finds the project root; `openlanes create` already refuses to run outside the primary checkout.
- The CLI registry in `lib/openlanes/cli.rb`, and `Base.default_params`, which merges `commands:` into a command's flags.

## How to tell it's working?

- Every key `Config.parse` accepts is in the schema, and a spec fails when one is missing or extra.
- `Config.parse` refuses a value the schema refuses, with the same message shape as today.
- Writing a config produces every key; parsing it back gives the same `Config`.
- A new option on a command appears in the generated `commands` schema with no hand edit.
- `openlanes start` run in a worktree boots in the main checkout, and says so on STDERR.
