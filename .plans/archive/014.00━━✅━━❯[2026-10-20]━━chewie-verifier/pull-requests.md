# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 34 | [\[014.00\] Spec: Chewie Verifier](https://github.com/kigster/openlanes/pull/34) | Merged ✅ |
| 71 | [Add the chewie verifier and 🧪 Verifying](https://github.com/kigster/openlanes/pull/71) | Merged ✅ |

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

## Round 1, re-run on 2026-10-21, luke-backend

- The implementation already merged as PR #71 (`kig/014-chewie-verifier`, merged 2026-10-17T18:26:40Z). PR #34 was this branch's spec PR.
- The harness rebase onto `origin/main` skipped the merge commit 99c06924 that carried this branch's implementation, leaving `HEAD` equal to `origin/main` 1e417939. The commit is still reachable through the reflog.
- On that tree: `bundle exec rspec`: 4075 examples, 0 failures, 9 pending; `bundle exec rubocop`: 547 files inspected, no offenses detected.
- There is nothing to publish, so this round is Blocked (product) on B2 in `blocked.md`.

## Closed as merged, 2026-10-21, luke-backend (D2)

- Per D2 (kig, 2026-10-21), 014.00 closes as ✅ Merged. PR #71 carried the implementation (merged 2026-10-17T18:26:40Z), and PR #34 was the spec PR. GitHub shows both as `MERGED`.
- No code work this round. `kig/014.00-spec-chewie-verifier` equals `origin/main` 1e417939. Deleting the branch is left to the harness or a human, because agents may not push.
- On HEAD 1e417939: `bundle exec rspec`: 4123 examples, 0 failures, 9 pending; `bundle exec rubocop`: 556 files inspected, no offenses detected.
