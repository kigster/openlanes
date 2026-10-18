# Blocked: 020.01 Durable Run Events

## B1 The suite fails on this machine for a reason outside the plan

The requirement "`bundle exec rspec` exits 0" is not met: 3224 examples, 31 failures (2026-10-17, round 1 rerun). Every failure is in `spec/openlanes/apps/*` (26) or `spec/openlanes/cli/app_spec.rb` (4, plus `ports_spec.rb:32`), and every one is `Apps::Ports::Exhausted: every port from 11100 to 11999 is taken` or a readiness probe that never sees a closed port. The cause is the machine: a TCP connect to any unused `127.0.0.1` port succeeds right now with no listener behind it (`Socket.tcp("127.0.0.1", 11177)` connects; `lsof` shows no server), so `Ports.answering?` calls every port taken. It is not this plan's code: the same specs fail the same way on a pristine `git archive HEAD` copy without the events work, no file under `lib/openlanes/apps` or `spec/openlanes/apps` is changed, and the suite was 0 failures last round on this same diff. Excluding those 30 port-dependent examples, everything passes; `bundle exec rubocop` is clean (459 files).

a) Treat it as environmental: find and switch off whatever intercepts loopback connects (VPN, network extension, transparent proxy), rerun, and let the plan proceed to review. (Recommended)
b) Accept the plan as done now, with these port-dependent failures noted in the pull request, and rely on CI's clean environment.
c) Make `Ports.answering?` robust to an interceptor (e.g. require a real server reply) in a separate plan, and hold this one until it lands.

## A1

Rebase onto the main branch first and retry

Answered by kig on 2026-10-17
<!-- cmd:01M55TSZ15T42WHE9NMHT9NTTP -->
