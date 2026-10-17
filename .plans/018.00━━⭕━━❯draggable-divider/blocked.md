# Blocked 018.00, round 1 (technical)

## B1 Full rspec never exits 0 under load

The requirement "`bundle exec rspec` exits 0" is unmet. Five full runs on 2026-10-16 (load average 6 to 14, rey running beside) each failed 1 to 4 examples, a different process/port spec every time: `spec/integration/restart_spec.rb:63`, `spec/integration/two_checkouts_spec.rb:70`, `spec/integration/control_room_spec.rb:73`, `spec/openlanes/apps/supervisor_spec.rb:74,86,133`, `spec/openlanes/apps/restart_spec.rb:77`. Each passes in isolation. This branch changes no Ruby, only `web/`; rubocop, `spec/openlanes/web` (167/0), `just web-build` and `just web-e2e` (divider 7/7) are green. Details in `pull-requests.md`.

a) Accept as environmental flakes and move the plan to review; rerun rspec on a quiet machine before merge. (Recommended)
b) Rerun the round when no other agent is running, and sign only on a 0-failure run.
c) Open a separate plan to harden the timing-sensitive integration specs first.

## A1

You must have run tests at the same time as another agent. We need to either make sure that each one uses a different redis db database or that only one plan can run tests at a time

To speed up the tests and ensure no clobbering between suites, suggest using https://github.com/guilleiguaran/fakeredis gem instead of the real one.



Answered by kig on 2026-10-16
<!-- cmd:01M53S429A7JGEB2QXHPVFNZ2B -->
