# Pull Requests

## Integration proof (rey-frontend, round 1)

- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures. Real Runner round, real Unblocker, PrWatch/PrOutcomes with a GitHub double, then `exe/openlanes events report --format json` as a subprocess.
- `bundle exec rubocop` → 460 files, no offenses.
- `bundle exec rspec` → 3224 examples, 30 failures, all under `spec/openlanes/apps/` (Probe/Ports/Runner/Supervisor/Restart, `app_spec`). Cause in this sandbox: a closed port reads as listening (`probe_spec.rb:41`). No file under `apps/` is touched by this plan. Luke's baseline showed 1 failure in the same area.

## Integration proof (luke-backend, last, round 1, 2026-10-20)

B1 was answered "rebase onto main and retry". `git rebase` is withheld from agents, and the harness had not rebased (the branch is still at `9a87460d`), so the main fix the answer points at, `ff03ca48` ("Fixing a bug in port detection": `Probe.listening?` asks the socket for its peer), is applied verbatim to `lib/openlanes/apps/{ports,probe}.rb`, `spec/fixtures/apps/servers/server.rb`, `spec/openlanes/apps/{probe,supervisor}_spec.rb` and `spec/openlanes/cli/app_spec.rb`. The hunks are identical to main's, so the rebase drops them cleanly.

- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures.
- `bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb` → 113 examples, 0 failures.
- `bundle exec rspec` → 3225 examples, 0 failures, 9 pending. The 9 pending specs skip themselves with "web/dist is missing: run just web-build first".
- `bundle exec rubocop` → 460 files inspected, no offenses detected.
- `just web-e2e` (Cypress) was not run. This plan changes no file under `web/`, and this worktree has no `web/node_modules` or `web/dist`. Building them takes an `npm` install.

## Integration proof (rey-frontend, re-run)

- `bundle exec rspec` → 3225 examples, 0 failures, 9 pending; `bundle exec rubocop` → no offenses; events CLI, presentation, integration and docs specs → 15 examples, 0 failures.
