# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 210 | [\[057.00\](A) Config Schema and Main Checkout](https://github.com/kigster/openlanes/pull/210) | Open 🟡 |

## What these pull requests did

### #210 — [057.00](A) Config Schema and Main Checkout

https://github.com/kigster/openlanes/pull/210

_No description was written on the pull request._


## Findings: security-reviewer

### F101 [minor] schemas/openlanes-config.schema.json:1885
The generated `commands` schema embeds the generating machine's environment: the `install` command description carries the absolute home path `/Users/hermes/.agents/skills` and the locally installed skill list. A checked-in artifact now leaks a local username and path (information disclosure, not exploitable), and the staleness spec will fail on any other machine or user.
Scenario: a contributor with a different `$HOME` runs the commands-schema staleness spec. Expected: green, the schema is machine-independent. Actual: the description differs, so the spec fails; the published file keeps the original author's home directory.
Suggest: strip or normalise environment-derived text (`Dir.home`, installed-state lines) in `CommandsSchema.command_schema`.

No other findings: shell-outs use argv arrays (no injection), the schema has no `$ref` (no remote fetch), patterns are linear, json_schemer 2.5.0 is current, and the new dependency adds no secret handling.

## Findings: design-reviewer

### F201 [critical] lib/openlanes/support/config/schema.rb:25
`Config::Schema` is built but nothing in `lib/` calls it. `Config.parse` still validates with `KEYS`, `MERGE_KEYS`, `BACKOFF_KEYS` and the other constants in `config.rb`, and `config.rb` is not in the diff. The schema is therefore a second, hand-written copy of every key, enum and default. The spec (S4) says the parser, the writer and the page read the schema and that those constants are derived from it or removed. Scenario: add a key to `MERGE_KEYS` only. `Config.parse` accepts it, the schema refuses it, and the only thing that notices is a spec. Expected: `parse` refuses what the schema refuses, with today's message shape. Actual: `Schema.errors` is called only from specs.

### F202 [critical] lib/openlanes/support/config.rb:243
The full-file writer (S3) is not implemented. `Config#to_yaml` still writes only the keys that are set, and nothing calls `Schema.defaults`. Scenario: `Config.new(jobs: 2).to_yaml` writes one key. Expected: every key, with its default where unset, and parsing it back gives an equal `Config`. Actual: only `jobs`. The "write, then parse back" check in the spec has no test.

### F203 [minor] lib/openlanes/support/config/schema.rb:17
The comment names `just update-config-schema`, and the spec failure message tells the reader to run it. No such recipe exists in the `justfile`, so the instruction fails when followed. `Schema.write` is also uncalled. Scenario: change a command flag, the stale-file spec fails, `just update-config-schema` errors with "unknown recipe". Add the recipe or reword the message.

### F204 [minor] lib/openlanes/support/config/commands_schema.rb:35
`commands` reads dry-cli's private state with `instance_variable_get(:@commands).instance_variable_get(:@root)`. A dry-cli upgrade that renames either variable raises `NoMethodError` at `Schema.document`, which every config load would hit. Put the reach in one small seam with its own spec, or build from `OpenLanes::CLI`'s own command list if it exposes one.

### F205 [minor] lib/openlanes/support/project.rb:62
`Project.enter_main_checkout` is a command-boot step: it calls `Dir.chdir` and `UI.line`. It sits in `Project` beside the pure root-finding helpers, and `Start` calls it directly. Consider placing it with `Start` or a boot helper, keeping `Project` free of side effects.

### Round 2 recheck (design-reviewer)

The code under review is unchanged for F201 to F205. `lib/openlanes/support/config.rb` is still not in the diff, `Config::Schema` still has no caller outside `lib/openlanes/support/config/`, and the `justfile` still has no `update-config-schema` recipe. F201 and F202 stand as critical, F203 to F205 as minor.

### Round 3 recheck (design-reviewer)

The packet's diff still has no `config.rb` change, no `justfile` recipe, and no caller of `Config::Schema` outside `lib/openlanes/support/config/`. F201 and F202 stand as critical; F203 to F205 stand as minor. Nothing new found.

### Round 4 recheck (design-reviewer)

The packet's diff is the same as in rounds 2 and 3: no `config.rb` change, no `update-config-schema` recipe, and `Config::Schema` has no caller outside `lib/openlanes/support/config/`. F201 and F202 stand as critical; F203 to F205 stand as minor. Nothing new found.
