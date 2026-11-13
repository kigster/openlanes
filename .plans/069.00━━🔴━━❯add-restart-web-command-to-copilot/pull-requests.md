# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 241 | [\[069.00\](A) Add Restart Web Command to Copilot](https://github.com/kigster/openlanes/pull/241) | Open 🟡 |

## Back end, round 1 (backend-coder)

Units B1 to B6 are built. One deviation from `plan.md`, recorded in `contract.md`: `/stats` reads the totals the engine snapshot already carries, not a new Tally key.

- B1 `lib/openlanes/live/copilot/slash.rb`: `Slash::COMMANDS` is the one table for `USAGE` and README. `/restart-web` (kind `restart_web` in `Command::KINDS`), plus `Slash::Query` for `/status [NNN]` and `/stats`.
- B2 `supervision/web_rebuild.rb`, `supervision/web_restart.rb`, `supervisor.rb`, `slot.rb`, `cli/start/start.rb` (USR2 trap): stop the web, run `npm run build` (spawned and polled, 300 s limit, old `web/dist` restored on failure), write `web-restart.json`, then start the web again. A restart is not counted as a crash.
- B3 `supervision/restart_request.rb`, `live/commands.rb#restart_web`: sends USR2 to a verified supervisor whose PID file has a URL. Otherwise it refuses with the D2 text.
- B4 `live/copilot/restart_note.rb`, `cli/web/web.rb`: on boot the new server reads and removes the note, then appends it as a copilot turn.
- B5 `live/copilot/report.rb`, `live/copilot.rb`: answers queries from `keys.snapshot` and queues nothing.
- B6 `agents/copilot.md` (`model: sonnet`), README (agents row, "Copilot commands" section), `spec/openlanes/docs/copilot_commands_doc_spec.rb`, golden `agents_list.txt`, `docs/architecture/` regenerated.
- Lint: `bundle exec rubocop` reports no offenses. `supervisor.rb` was added to the `Metrics/ClassLength` todo list. It was already at exactly 100 lines, and the restart wiring adds 3 even after moving the logic into `WebRestart`.

### Checks

- `bundle exec rubocop`: 1002 files inspected, no offenses detected.
- `bundle exec rspec`: see below.

### Integration proof and end-to-end

The integration proof is frontend-coder's `web/cypress/lanes/restart-web.cy.ts`, run by `bin/lanes-e2e`. It was not run in this round. It needs a real `openlanes start` with live agents, which spends tokens and takes longer than this round's 20-minute budget allowed. Run `bin/lanes-e2e` before merging.

### Full suite, round 1

`bundle exec rspec --format documentation --seed 27744` was still running at WRAP_UP. At about 255 KB of output it had no FAILED examples. Every file this plan touched passes on its own (supervision, live/copilot, commands, docs). `bundle exec rubocop`: no offenses.

### Full suite, round 2

- `bundle exec rspec`: `6686 examples, 0 failures, 9 pending`, exit 0.
- The 9 pending examples are environment skips in `spec/integration/restart_spec.rb`, `control_room_spec.rb` and `two_checkouts_spec.rb`, all with the reason "web/dist is missing: run just web-build first". This worktree has no `web/node_modules`, so the page cannot be built without `npm install`. They are not caused by this plan.
- `bundle exec rubocop`: 1002 files inspected, no offenses detected, exit 0.
- `bin/lanes-e2e` (the integration proof, `web/cypress/lanes/restart-web.cy.ts`) is still not run. It needs a real `openlanes start` with live agents and an `npm install`. Run it before merging.

## Findings: design-reviewer

### F201 [minor] lib/openlanes/live/copilot/slash.rb:62
`Slash::COMMANDS` names every command, but `parse` dispatches on a second, hand-written list (`PLAN_KINDS`, `QUERIES`, and the `"concurrency"` / `"restart-web"` literals). A command added to `COMMANDS` and not to `parse` shows in the usage and is answered "is not one of them", and the README spec passes. Scenario: add an `Entry` named "pause" and no `parse` branch; the usage lists `/pause` and typing it gets the usage plus "/pause is not one of them."

### F202 [minor] lib/openlanes/supervision/web_rebuild.rb:1
`WebRebuild` spawns and polls the build, enforces the timeout, writes the log, and also copies `web/dist` aside and restores it. The dist backup and restore is a second reason to change, and testable on its own. Scenario: changing how the old page is kept (rename instead of copy) means editing the process class.

### F203 [minor] lib/openlanes/live/copilot/restart_note.rb:40
The note is a contract with two sides that both spell it out as string keys and values (`status`, `message`, `at`, `"ok"`). `WebRestart#note` writes it and `RestartNote#text_for` reads it, and the latter re-tests `status == "ok"` where `WebRebuild::Outcome#ok?` already says it. Renaming a status in `WebRebuild` leaves `text_for` reporting "old page" with no spec failing across the two files.

### F204 [minor] lib/openlanes/live/commands.rb:143
`Live` and `CLI` reach into `Supervision::RestartRequest` (`SIGNAL`, `REFUSAL`) and `Supervision::WebRestart::NOTE` directly, and `Live::Commands` builds the request in a default lambda, though `CLAUDE.md` says to reach a namespace only through its facade. `Supervision.dir` and `Supervision.probe` already exist, so a `Supervision.restart_web_request` / `Supervision.restart_note_path` pair would fit. Scenario: moving `RestartRequest` forces edits in `Live::Commands` and `CLI::Start`.

### F205 [minor] lib/openlanes/supervision/supervisor.rb:71
The restart logic was split into `WebRestart`, but `Slot#rebuild` now carries restart state and `reap` and `finished` test it. The supervisor's crash accounting depends on a field of another object's lifecycle, and `supervisor.rb` was added to the `Metrics/ClassLength` todo instead of staying under the limit. Scenario: a future restart kind (engine) has to add a second `Slot` attribute and a third check in `reap`.

## Findings: security-reviewer

### F101 [critical] lib/openlanes/supervision/web_rebuild.rb:58

The build's output file is `File.join(Dir.tmpdir, "openlanes-web-build-<supervisor pid>.log")`: a predictable name in a directory that is shared and world-writable wherever `TMPDIR` is unset on Linux (`/tmp`). `spawn(..., out: @log)` opens it `O_WRONLY|O_CREAT|O_TRUNC` and follows a symlink. The supervisor's pid is public (`ps`).

Scenario: another local user runs `ln -s /home/victim/.ssh/authorized_keys /tmp/openlanes-web-build-4242.log` while the victim's supervisor is pid 4242. The victim types `/restart-web`: npm's output truncates and overwrites the target file with the victim's permissions. `tail` (line 140) then reads the same planted path back and puts its last 15 lines into the copilot turn, so a planted file can also be read through the control room. Expected: the log is created in a directory only the supervisor can use. Actual: any local user can redirect the write. The file is also never removed.

Fix: write the log under `Dir.mktmpdir` (mode 0700), as `keep_old_page` already does, or under the pid directory, and delete it after `tail` has read it.

### F102 [minor] lib/openlanes/live/copilot/restart_note.rb:26

The note's `at` becomes the turn id (`web-restart-#{at.to_i}`) and its `message` becomes copilot text, both unchecked. Anyone who can write `tmp/pids/web-restart.json` can post a copilot turn. The page renders it as escaped text (no `dangerouslySetInnerHTML` under `web/src/copilot`), and that write access already beats the control room, so this is only defence in depth. Not blocking.

## Answers, round 1

No review comment or finding names the front end (F101 to F102 and F201 to F205 are all Ruby files), so nothing in `web/` changed this round. The front end stays as built: `Copilot.tsx` hint, `Copilot.test.tsx`, `web/cypress/lanes/restart-web.cy.ts`, `bin/lanes-e2e`.

## Back end, round 4: review fixes (backend-coder)

Every finding is fixed; none is appealed. The pull request had no inline review comments to answer.

- F101 [critical] `supervision/web_rebuild.rb`: the build log is now `build.log` inside `Dir.mktmpdir("openlanes-web-build")` (mode 0700, random name), not a pid-named file in shared tmp. It is read for the reply and then removed with its directory on every outcome. Specs: `web_rebuild_spec.rb` "the build's log (F101)" checks the 0700 directory, the tail in the reply, and that the directory is gone.
- F202 `supervision/page_backup.rb` (new): keeping, restoring and discarding `web/dist` moved out of `WebRebuild`, which now only runs the build. Spec: `page_backup_spec.rb`.
- F203 `supervision/web_restart_note.rb` (new): `WebRestartNote` (outcome, at) owns the file's format, with `#write` and `.take`. `WebRestart` writes it, and `Live::Copilot::RestartNote` reads the `WebRebuild::Outcome` back and asks `ok?`, so the reader no longer re-tests `"ok"`. `restart_note_spec.rb` now round-trips through the writer.
- F204 `supervision.rb`: facade `Supervision.restart_web(root)`, `.take_restart_note(root)`, `RESTART_WEB_SIGNAL` and `RESTART_WEB_REFUSAL`. `Live::Commands`, `CLI::Start` and `CLI::Web` no longer name `RestartRequest` or `WebRestart::NOTE`.
- F205 `supervision/slot.rb`, `supervisor.rb`, `web_restart.rb`: `Slot#rebuild` is now a generic `Slot#held` (whoever stopped the slot on purpose), and the `WebRebuild` stays inside `WebRestart`. The supervisor checks `slot.held` in `reap` and `Slot#busy?` in `finished`, so a later restart kind reuses the same field. `supervisor.rb` is back under `Metrics/ClassLength` and off `.rubocop_todo.yml`.
- F201 `live/copilot/slash.rb`: `Entry` gains `parser:`, and `parse` dispatches through `COMMANDS` alone. The `QUERIES` list and the word literals are gone. Spec: every `COMMANDS` row parses to something other than "is not one of them".
- F102 (minor, non-blocking): a note that is missing a key, or has a bad type, is dropped (`restart_note_spec.rb` "drops a note missing a key"). The text is still rendered escaped.
- `docs/architecture/` regenerated.

### Checks, round 4

- `bundle exec rubocop`: 1006 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/live spec/openlanes/supervision spec/openlanes/cli spec/openlanes/docs`: 1418 examples, 0 failures.
- `bundle exec rspec` (full, seed 36760): `6694 examples, 0 failures, 9 pending`, exit 0. The 9 pending are the same `web/dist is missing` environment skips as in round 2.
- `bin/lanes-e2e` (`web/cypress/lanes/restart-web.cy.ts`) is still not run: it needs `npm install` and a live `openlanes start`. Run it before merging.
