# Blocked: plan 014.00, round 2 (technical)

Requirement not met in this run: "`bundle exec rspec` and `bundle exec rubocop` each exit 0".

- `bundle exec rubocop`: 433 files, 0 offenses.
- `bundle exec rspec`: 3060 examples, 39 failures, 9 pending. Every failure needs a free localhost port: `spec/openlanes/apps/*` (012's merged supervisor, runner, restart, ports, probe specs, 27), `spec/openlanes/cli/app_spec.rb` (4), the two app-around examples in `spec/openlanes/engine/dispatcher_spec.rb`, `spec/openlanes/engine/verification/app_session_spec.rb` (3) and `spec/integration/verification_spec.rb` (3).
- Cause: inside the agent sandbox every TCP connect to 127.0.0.1 succeeds, on any port (checked on 11900, 23456, 41234 and 5, with and without the sandbox override). `Apps::Ports.free?` therefore finds no free port and `Apps::Probe` calls a silent process ready. 012's own specs, already on `main`, fail the same way here, so this is the environment, not this plan's code.
- With the registry's `free:` stubbed to true (a temporary local edit, since reverted), the integration spec's passing-PR and failing-step examples both pass: 👀 → 🧪, `final.png` committed by the engine, `ok-to-merge` after CI turns green; and `review-rejected`, one comment linking `step-02.png` by SHA, 🔴, mail to luke and rey. The app-never-starts example cannot pass here, because readiness is a connect probe.
- `bin/coverage-changed --files <this plan's lib files>`: all at 95% or above except `apps/supervisor.rb` (46%), `engine/dispatcher.rb` (94.05%) and `engine/verification/app_session.rb` (80.77%). The specs that cover those lines are the socket-dependent ones above.

## B1 Where the suite gets run

The code for B1 to B8 is in the worktree, and rubocop is clean. The only thing left is to show `bundle exec rspec` green and `bin/coverage-changed` passing, and that needs a machine where an unused localhost port refuses connections.

a) Run `bundle exec rspec` and `bin/coverage-changed` in the worktree from a normal terminal, then re-run luke to sign Completed if they are green. (Recommended)
b) Run the agent again with localhost networking allowed in its sandbox, so luke can run the suite and sign itself.
c) Tag the 39 socket-dependent examples to be skipped when localhost answers on a port nothing listens on, and accept that the app paths go unverified in agent runs.

## A1

Rebase onto the main branch first and retry

Answered by kig on 2026-10-17
<!-- cmd:01M55TRRW1DNPPMME39J31ARKF -->
