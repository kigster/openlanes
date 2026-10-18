# Pull Requests

## Integration proof (rey-frontend, round 1)

- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures. Real Runner round, real Unblocker, PrWatch/PrOutcomes with a GitHub double, then `exe/openlanes events report --format json` as a subprocess.
- `bundle exec rubocop` → 460 files, no offenses.
- `bundle exec rspec` → 3224 examples, 30 failures, all under `spec/openlanes/apps/` (Probe/Ports/Runner/Supervisor/Restart, `app_spec`). Cause in this sandbox: a closed port reads as listening (`probe_spec.rb:41`). No file under `apps/` is touched by this plan. Luke's baseline showed 1 failure in the same area.
