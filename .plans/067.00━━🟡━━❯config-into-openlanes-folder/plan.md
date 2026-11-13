---
execution: concurrent
---
Not a refactor (no `implementation_requirement: refactor`; it moves a config file, not code). Share for the record: ~75 of 2206 tracked files (~3%), lines well under 10%; threshold 50%.

# Plan 067.00: Config Into the .openlanes Folder

## Decisions on the spec's open questions

- **How long the old path is read:** indefinitely, with the notice, until a later plan removes it. Removing a read path is its own decision; nothing here forces a date.
- **Live factory and a moved file:** picked up without a restart. `Config.current` caches on the *resolved* path plus mtime, so after `openlanes config move` the next tick resolves `.openlanes/config.yml`, the key differs, and the file is reread.
- **Notice frequency:** once per process, on STDERR, through `UI.line`. A tick loop must not print it every tick.
- **Move command name:** `openlanes config move [--dry-run]`, a new `config` group, so later config subcommands (`show`, `check`) have a home.
- `depends_on: ["057.00"]` was written by a person and stands (057.00 is merged on `main`, PR #210).

## Order and dependency graph

```
U1 path resolution ──┬─> U2 secret refusal ─┐
                     ├─> U3 coverage path ──┼─> U4 config move cmd ─┐
                     └─> U5 init ───────────┘                       ├─> U6 sweep ─> U7 own move + integration
```

- U2 and U5 both follow U1; U2 also edits `config.rb`, which U1 owns, so U1 → U2 is sequential.
- U3 and U5 can run beside U2 (disjoint files).
- U6 touches many files the earlier units own, so it runs after all of U1–U5.
- U7 is last.

## Backend

### U1 Resolve the config path, new first, legacy second

- **Discipline:** back end
- **Owns:** `lib/openlanes/support/project.rb`, `lib/openlanes/support/config.rb` (the `load` / `current` / `write_flag` path handling only), `spec/openlanes/project_spec.rb`, new `spec/openlanes/config_path_spec.rb`, `spec/support/settings_in.rb`, `spec/support/checkout_config.rb`, `spec/spec_helper.rb` (fixture writers move to the new path)
- **Must not touch:** `lib/openlanes/coverage/**`, `lib/openlanes/cli/**`, secret checks in `Config.parse`
- **Depends on:** nothing
- **Shape:** `Project::DIR = ".openlanes"`, `Project::FILE = ".openlanes/config.yml"`, `Project::LEGACY_FILE = ".openlanes.yml"` (the only place under `lib/` that spells it). `Project.config_path(root) -> String` returns the new path when present, the legacy path (and emits the one-line notice: new path + `openlanes config move`) when only it is present, the new path when neither is, and raises `OpenLanes::Error` naming both files when both are present. `Project.root` marks a directory holding `.openlanes/config.yml`, `.openlanes.yml` or the plans directory; `$HOME` counts for either config file. `Config.load`, `Config.current` and `Config.write_flag` go through `config_path`; `write_flag` creates `.openlanes/` when writing a new file. `Config::FILE` follows `Project::FILE`.
- **Done when:** `spec/openlanes/project_spec.rb` and `spec/openlanes/config_path_spec.rb` pass: new-only (quiet), legacy-only (read + exactly one notice per process), both (refused, message names both), neither; `Config.current` rereads after the file moves.

### U2 Refuse secrets in the config file

- **Discipline:** back end
- **Owns:** `lib/openlanes/support/config.rb` (`parse` and the `redis_url` reader), `spec/openlanes/config_redis_url_spec.rb`, new `spec/openlanes/config_secrets_spec.rb`
- **Must not touch:** `project.rb`, anything U1 owns outside `parse`
- **Depends on:** U1 (same file, sequential)
- **Shape:** at parse, `redis_url` with a userinfo password (`redis://:pw@host`, `redis://user:pw@host`) is refused; any string value, at any depth, that looks like a token (known prefixes such as `ghp_`, `gho_`, `github_pat_`, `sk-`, `xox[bp]-`, `lin_api_`, `AKIA`, or a key named `*token*`, `*secret*`, `*password*`, `*api_key*` with a non-empty value) is refused. The message names the file and the key path, and points at the `REDIS_URL` environment variable (for `redis_url`) or at an environment variable in general.
- **Done when:** `spec/openlanes/config_secrets_spec.rb` passes, covering each refusal and a password-less `redis_url` still accepted; `config_redis_url_spec.rb` stays green.

### U3 Coverage settings move to `.openlanes/coverage.yml`

- **Discipline:** back end
- **Owns:** `lib/openlanes/coverage/config.rb`, `lib/openlanes/coverage.rb`, `spec/openlanes/coverage/config_spec.rb`
- **Must not touch:** `project.rb`, `support/config.rb`, `cli/**`
- **Depends on:** U1 (uses `Project::DIR`)
- **Shape:** the coverage file becomes `.openlanes/coverage.yml`; `.openlanes.coverage.yml` stays as the legacy read, with the same notice and the same both-present refusal as U1 (reuse U1's resolver, do not copy its message text into a second table).
- **Done when:** `spec/openlanes/coverage/config_spec.rb` passes for new, legacy, both and neither.

### U4 `openlanes config move`

- **Discipline:** back end
- **Owns:** new `lib/openlanes/cli/config/config.rb`, `lib/openlanes/cli/config/subcommands/move.rb`, new `lib/openlanes/setup/config_move.rb`, the one `register "config", ...` line in `lib/openlanes/cli.rb`, new `spec/openlanes/setup/config_move_spec.rb`, new `spec/openlanes/cli/config_move_spec.rb`
- **Must not touch:** `project.rb`, `support/config.rb`, `coverage/**`
- **Depends on:** U1, U3
- **Shape:** `Setup::ConfigMove.new(root:).call(dry_run:) -> Array<[from, to]>`. Moves `.openlanes.yml` → `.openlanes/config.yml` and `.openlanes.coverage.yml` → `.openlanes/coverage.yml` with `git mv` in a repository (rename outside one), the way `OpenLanes.move_directory` does. Refuses when a destination exists. `--dry-run` prints the moves and changes nothing. Nothing to move is a success with one line saying so. It does not commit.
- **Done when:** both specs pass; the setup spec runs in a real temp git repo and asserts `git log --follow .openlanes/config.yml` reaches the pre-move commit.

### U5 `openlanes init` writes the new path, and nothing under it is ignored

- **Discipline:** back end
- **Owns:** `lib/openlanes/cli/init/init.rb`, `lib/openlanes/setup/project_form/dsl.rb`, `lib/openlanes/setup/stack_document.rb`, `lib/openlanes/setup/architecture_decisions.rb` (write path only), their specs under `spec/openlanes/setup/`, new `spec/openlanes/cli/init_config_path_spec.rb`
- **Must not touch:** `project.rb`, `support/config.rb`, `.gitignore`
- **Depends on:** U1
- **Shape:** init writes `.openlanes/config.yml`. In a project whose legacy file exists, init refuses and names `openlanes config move`. Init never writes a `.gitignore` entry under `.openlanes/`; when `git check-ignore` reports a path under `.openlanes/` as ignored, init warns on STDERR.
- **Done when:** `spec/openlanes/cli/init_config_path_spec.rb` passes: a new project gets `.openlanes/config.yml`, `git check-ignore -q .openlanes/config.yml` fails (not ignored), a legacy project is refused with the move command named.

### U6 Name the new path everywhere

- **Discipline:** back end
- **Owns:** every remaining file under `lib/` that spells `.openlanes.yml` or `.openlanes.coverage.yml` in a message, `--help` text or comment (about 45 files, from `rg -l '\.openlanes(\.coverage)?\.yml' lib`), plus `README.md`, `agents/*.md`, `skills/**/SKILL.md`, `skills/**/references/*.md`, the `docs/` pages that describe the config path, and the specs that assert those messages
- **Must not touch:** the legacy constant in `project.rb` and the legacy constant in `coverage/config.rb`
- **Depends on:** U1, U2, U3, U4, U5 (overlapping files, sequential)
- **Shape:** code refers to `Project::FILE` / `Config::FILE` rather than a literal; prose says `.openlanes/config.yml`. Regenerate `docs/WORKFLOW.md` (`just update-workflow`) and `docs/architecture/` (`just update-architecture`) if they change.
- **Done when:** `rg -n '\.openlanes\.yml' lib` lists only the `LEGACY_FILE` line in `lib/openlanes/support/project.rb`; `spec/openlanes/packaging_spec.rb` and `spec/openlanes/docs/architecture_doc_spec.rb` pass.

### U7 This repository moves across, and the integration check

- **Discipline:** back end
- **Owns:** `.openlanes.yml` → `.openlanes/config.yml` and `.openlanes.coverage.yml` → `.openlanes/coverage.yml` in this repository (through `exe/openlanes config move`), new `spec/integration/config_folder_spec.rb`
- **Must not touch:** anything under `lib/`
- **Depends on:** U6
- **Integration check (this unit):** real `exe/openlanes` processes, nothing stubbed, in temp git projects:
  1. legacy-only project: `status`, `list`, `states`, `docs`, `index --dry-run`, `resync dirs --dry-run` and `start --help` exit as before, STDOUT matches a new-path twin, and STDERR carries the one-line notice exactly once per process;
  2. both files: every command above exits non-zero with a message naming both paths;
  3. `config move --dry-run` changes nothing; `config move` leaves `git status` showing renames, and the next command prints no notice;
  4. this checkout: `exe/openlanes start` resolves its config from `.openlanes/config.yml` (asserted through the start command's config resolution, without launching agents).
- **Done when:** `spec/integration/config_folder_spec.rb` passes, the whole suite is green and rubocop is clean.

## Frontend

None: `spec.md` says `frontend: false`.

## HTTP surface

No. The plan adds no HTTP API and changes none.

## Build notes, backend-coder

- **U3 reduced:** `.openlanes.coverage.yml` was already retired before this plan (coverage settings live in the `coverage:` section of the config file, and the old file is only warned about). Creating `.openlanes/coverage.yml` would reintroduce the second file that decision removed, so only the retirement warning changed, to name `.openlanes/config.yml`. This repository's own `.openlanes.coverage.yml` is left for a person to delete.
- **U4 naming:** the CLI group is `OpenLanes::CLI::ConfigFile` (`openlanes config move`), because `CLI::Config` would shadow `OpenLanes::Config` for every command under `CLI`.
- **U7 command list:** the integration spec drives `status`, `index` and `resync dirs --dry-run`. `states`, `docs` and `start --help` never read the config file, so they cannot show the notice; `index --dry-run` is not a flag `index` takes.
- **U6 scope:** README, `docs/USAGE.md`, `docs/STARTING-AN-APP.md`, `docs/events.md`, `docs/continuous-learning.md`, `docs/wiki.yml`, `agents/*.md` and `skills/**` name the new path. `docs/decisions/*` are dated records and keep the name they were written with.

## Task completed when

- This repository's own config is at `.openlanes/config.yml` and `ol start` runs from it
- A temp project with only `.openlanes.yml` runs every command unchanged and sees the one-line notice
- No file under `lib/` spells `.openlanes.yml` outside the legacy read path

## How to test

- bundle exec rspec
- bundle exec rubocop
- rg -n '\.openlanes\.yml' lib
