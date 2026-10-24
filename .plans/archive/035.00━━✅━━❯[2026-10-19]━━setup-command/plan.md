# Plan 035.00 — Setup Command

## Backend

### U1 Runtime Brewfile
`Brewfile` at the gem root lists what the code shells out to: gh, git, imagemagick (`magick`), jq, just, redis, ripgrep, vips. The contributor's extras moved to `Brewfile.dev`, which the gem does not ship.

### U2 `OpenLanes::Setup` library
`lib/openlanes/setup.rb` (facade, `render`), `setup/check.rb`, `setup/machine.rb`: `brew bundle check`, `brew bundle --no-upgrade --file <gem>/Brewfile` when something is missing, then brew, Brewfile, claude, gh auth and Redis checks. Processes and the Redis ping are seams.

### U3 `openlanes setup` command
Standalone; `-n` installs nothing and lists what it would install and check; one ✓/✗ line per check on STDOUT, a fix under each ✗; exit 69 when any check fails. `--redis-url` overrides the URL checked.

### U4 `openlanes init` runs setup when needed
Init checks the machine first; only when a check fails does it run setup (dry-run under `-n`), report on STDERR, and carry on writing `.openlanes.yml`.

### U5 Packaging
The gemspec no longer ships `bin/*`; `bin/setup` bundles `Brewfile` and `Brewfile.dev`.

## Frontend

None: `starts: planning`, a command-line change.

## Decisions

- The spec said there was no `Brewfile`; there was one, a contributor's (sopsy, rbenv, circleci, …), already globbed into the gem. Shipping it would install those on every user's machine, so it became `Brewfile.dev` and the root `Brewfile` holds the runtime tools only.
- node is not in the Brewfile: the gem ships the built control room, and nothing at run time calls node.
- `init` continues after setup when a check still fails (e.g. gh logged out): writing `.openlanes.yml` needs none of them, and stopping would add a human step (M0).
- `brew bundle check` runs with `HOMEBREW_NO_AUTO_UPDATE=1` so a check does not update Homebrew.

## How to test

- `openlanes setup` from an empty directory installs nothing on a machine that has everything, and prints ✓ for every check.
- With `gh` logged out, the `gh` check is ✗ with `gh auth login` as the fix, and the exit status is non-zero.
- `openlanes setup -n` changes nothing and lists what it would do.
- The built gem contains `Brewfile` and no longer contains `bin/*`; `bin/setup` keeps working in a checkout.
- `openlanes init` on a machine missing a tool runs setup before its interview; on a ready machine it does not.
