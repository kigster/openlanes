# Blocked, round 2 (technical)

Requirement not met: "`bundle exec rspec` and `bundle exec rubocop` each exit 0". Rubocop does. Rspec does not, and the failures are in files this plan does not own and did not change.

## B1 The app specs fail on this machine's Ruby and macOS, outside this plan

`bundle exec rspec` reports 3107 examples, 30 failures, all of them in `spec/openlanes/apps/` (ports, probe, restart, runner, supervisor) and `spec/openlanes/cli/app_spec.rb`. Round 1 ran the same suite with 0 failures. The cause is a call that behaves differently on this host (Darwin 27, Ruby 4.0.6): `Socket.tcp("127.0.0.1", port, connect_timeout: 0.2)` returns a socket for a port nothing listens on, where `Socket.tcp` with no timeout and `TCPSocket.new` both raise `Errno::ECONNREFUSED`. So `Apps::Ports#answering?` sees every port from 11100 to 11999 as taken, and `Apps::Probe.listening?` (and so `ready?`) sees closed ports as open. It happens both inside and outside the sandbox. Without the app specs the suite is clean: 2995 examples, 0 failures, 9 pending. This plan's own specs run 146 examples with 0 failures. `git status` shows nothing changed under `lib/openlanes/apps` or `spec/openlanes/apps`.

a) Fix the probe in its own small PR (a non-blocking connect that checks `SO_ERROR`, in `apps/ports.rb` and `apps/probe.rb`), merge it, then re-run this plan's checks unchanged. (Recommended)
b) Let luke-backend fix the probe inside this plan. The PR then reaches beyond `init`.
c) Accept this plan as it stands: judge it on the suite without the app specs, with the failures and their cause written in `pull-requests.md`.

## A1

Rebase onto main.

Answered by kig on 2026-10-17
<!-- cmd:01M55TQQZZYYQF69554D3967FK -->
