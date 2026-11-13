# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 238 | [\[067.00\](A) Config into Openlanes Folder](https://github.com/kigster/openlanes/pull/238) | Open 🟡 |

## Checks run by backend-coder, round 3

- `bundle exec rubocop`: 1002 files inspected, no offenses detected
- `rg -n '\.openlanes\.yml' lib`: only `lib/openlanes/support/project.rb` (`LEGACY_FILE` and the comment beside it)
- `git check-ignore .openlanes/config.yml .openlanes/x`: exit 1, nothing under `.openlanes/` is ignored
- `bundle exec rspec spec/integration/config_folder_spec.rb`: 4 examples, 0 failures
- `bundle exec rspec`: 6670 examples, 0 failures, 10 pending, exit 0

## Findings: design-reviewer

### F201 [minor] lib/openlanes/setup/config_move.rb:26
The both-files rule and its message are written twice: `Project.resolve` raises "both X and Y exist; keep …", and `ConfigMove#call` raises its own different wording. Scenario: a project with both files gets two different messages depending on whether it runs `status` or `config move`; editing one leaves the other stale. Reuse a shared message from `Project` (or call `Project.config_path` in a rescue-free check).

### F202 [minor] lib/openlanes/cli.rb:199
The new `register "config"` block was inserted between the comment "The durable run log, read back. See {OpenLanes::Events}." and `register "events"`. Scenario: a reader sees the events comment sitting over the config group. Move the comment back down and give `config` its own.

### F203 [minor] lib/openlanes/support/project.rb:55
`Project.resolve(root, current, legacy)` is generalised "for every file that moved", but its only caller is `config_path`; the coverage file it was built for (U3) was dropped. Scenario: the parameters promise a reuse that does not exist. Fine to keep, but say so or inline it.

## Findings: security-reviewer

no findings

## Findings: staff-reviewer

### F1 [critical] lib/openlanes/support/config/secrets.rb:17
`KEY = /token|secret|password|passwd|api_?key/i` matches by substring, so `commands.<cmd>.max_tokens`, which the schema types as `string` or `number`, is refused as a secret whenever it is written as a string. Input: `.openlanes/config.yml` with `commands: { run: { max_tokens: "200k" } }`. Expected: parses, as it did on `main`. Actual (reproduced with `Config.parse`): `commands.run.max_tokens looks like a secret; this file is committed, so put it in an environment variable instead`, and every command in that project now refuses to run. Anchor the key check to whole words or credential-shaped names (e.g. `/(?:\A|_)(?:token|secret|password|passwd|api_?key)\z/i`), and add a spec that every string-typed key in `schemas/openlanes-config.schema.json` with a harmless value parses.

### F2 [minor] README.md:226
The callout is now `> [!NOTE]` / `>` / `> [!NOTE]`, followed by a separate blockquote, so GitHub renders a stray "[!NOTE]" line and the older note about `architecture_decisions:` loses its callout. Expected: one NOTE per callout. Drop the duplicated marker and keep each note in its own callout.

## Answers, round 4

No inline review comments on #238 (`gh api repos/kigster/openlanes/pulls/238/comments` returns 0). Staff-reviewer's findings:

- F1 fix: `Secrets::KEY` in `lib/openlanes/support/config/secrets.rb` is anchored to the whole key name or its last `_`-separated word, so `max_tokens: "200k"` parses again while `api_key`, `github_token`, `client_secret` are still refused. `spec/openlanes/config/secrets_spec.rb` adds a `max_tokens: 200k` parse and a walk over every string-typed key in `schemas/openlanes-config.schema.json`; both fail (2 failures) with the old regex.
- F2 fix: README.md callout split into two `> [!NOTE]` blocks, one note each.
- Design-reviewer F201-F203 (minor) not in staff-reviewer's findings; left for a later round.

## Checks run by backend-coder, round 4

- `bundle exec rubocop`: 1002 files inspected, no offenses detected
- `bundle exec rspec spec/openlanes/config/secrets_spec.rb`: 7 examples, 0 failures
- `bundle exec rspec`: 6672 examples, 0 failures, 10 pending, exit 0
