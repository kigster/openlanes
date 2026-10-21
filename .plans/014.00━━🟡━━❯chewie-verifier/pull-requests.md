# Pull Requests

## Integration check (B8), luke-backend, round 1

No front-end units in this plan, so luke-backend owns the whole plan and ran the checks last.

- `bundle exec rspec spec/integration/verification_spec.rb`: 3 examples, 0 failures (bullets 1, 4, 5: verified + ok-to-merge once CI green; failing step rejected with step-02.png linked by SHA and on the PR branch, mailed to luke and rey; app that never starts rejected with 20 lines of its output).
- `bundle exec rspec`: 3060 examples, 0 failures, 9 pending (the pending are the Redis/web e2e examples that skip without `web/dist`).
- `bundle exec rubocop`: 433 files inspected, no offenses detected.
- `bin/coverage-changed --files <lib files changed or added against HEAD>`: every file 014 adds or changes (engine/verification*, runner, dispatcher, run_workflow, apps/supervisor, vcs/github, vcs/publisher) is at or above 95%. The gate still exits 1 on two files the staged merge of origin/main brings in, not 014 work: `lib/openlanes/plans/lock.rb` 93.33% and `lib/openlanes/vcs/rename_date.rb` 92.00%. Plain `bin/coverage-changed` reports "no changed files" because the work is staged, not committed.

Fixes this round:

- `Runner#verification` mails a rejection to every agent defined, not the run's roster (a run limited to hansolo and chewie mailed nobody).
- The spec read origin's tree without `-z` (emoji paths came back quoted) and read ports from the wrong field of `Ports#entries`.
- The spec reserves ports from 11900 up: the 012 app specs also start at 11100 with their own registry files, and one of their servers still shutting down answered the silent app's port.

Known flake, not from this plan: `spec/openlanes/apps/supervisor_spec.rb:128` and `spec/openlanes/cli/app_spec.rb:88` (both 012, both on `main`) failed once each in about eight runs, from the same cross-spec port overlap. Not fixed here.

## Integration check, luke-backend, round 1 retry (after B1: "rebase onto main and retry")

The localhost failures behind B1 were the port-detection bug `main` already fixed in ff03ca48 (`Probe.listening?` asks the socket for its peer, because behind a network filter `Socket.tcp` with `connect_timeout` hands back a socket for a refused connect). The harness forbids `git rebase`, so that commit's changes to `lib/openlanes/apps/{ports,probe}.rb`, `spec/fixtures/apps/servers/server.rb` and the probe, supervisor and app specs were applied to the working tree as-is (identical to `main`, so the harness's rebase takes them cleanly). 014's own `connectable?` helpers in `spec/integration/verification_spec.rb` and `spec/openlanes/engine/verification/app_session_spec.rb` now use `Probe.listening?` the same way.

- `bundle exec rspec spec/integration/verification_spec.rb`: 3 examples, 0 failures.
- `bundle exec rspec`: 3061 examples, 0 failures, 9 pending (control-room e2e, skipped without `web/dist`).
- `bundle exec rubocop`: 433 files inspected, no offenses detected.
- `bin/coverage-changed --files <lib files changed against MERGE_HEAD aee4ccd, plus untracked lib>`: 15 files, all at or above 95%.
