# Pull Requests

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
