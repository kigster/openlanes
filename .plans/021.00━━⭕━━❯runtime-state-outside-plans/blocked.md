# Blocked

## B1 The suite cannot exit 0 on this machine

The plan requires `bundle exec rspec` to exit 0. Every unit is done, rubocop is clean, and the suite has one failure this plan caused, now fixed (`spec/integration/restart_spec.rb` read the run record from `.plans/`). 30 failures are left, all in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb`, and a clean checkout of `HEAD` (0d0d99c) fails the same 30 out of 112. The cause is the machine: right now a TCP connect to a localhost port nobody listens on succeeds (`ruby -rsocket -e 'Socket.tcp("127.0.0.1", 58318, connect_timeout: 0.5)'` connects), probably through a VPN or a local proxy's network extension. So `Ports.free?` and `Probe.ready?` see every port as taken. None of those files is touched by this plan.

a) Turn off whatever intercepts localhost connects, re-run `bundle exec rspec`, and unblock once it exits 0. (Recommended)
b) Accept the 30 environmental failures as baseline and send the plan to review as it is.

## A1

Rebase onto the main branch first and retry

Answered by kig on 2026-10-17
<!-- cmd:01M55TT5NZZB3GT1ZZHJATS0N4 -->
