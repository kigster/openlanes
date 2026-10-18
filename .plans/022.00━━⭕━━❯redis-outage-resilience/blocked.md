# Blocked: 022.00 Redis Outage Resilience

## B1 The suite cannot exit 0 on this machine, and none of the failures are this plan's

Every back-end unit (B1 to B7) is built and tested, and `bundle exec rubocop` is clean. The implementation requirement says `bundle exec rspec` must exit 0. It exits 1 with 30 failures, all in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb`. The same 30 fail on a clean checkout of `7186635`, and this plan touches no file under `lib/openlanes/apps/`. The cause is the host: a TCP connect to `127.0.0.1` on a port that was just bound and closed succeeds, so `Apps::Probe.ready?` sees a listener where there is none (`probe_spec.rb:42`). Something on this machine, such as a VPN, proxy or network extension, accepts connects on every closed local port. Details are in `contract.md`, Baseline.

a) Find and stop whatever accepts connects on closed local ports, then re-run `bundle exec rspec`; the plan goes on unchanged. (Recommended)
b) Accept the 30 as an environmental baseline for this plan, and let luke-backend sign Completed.
c) Have the `apps` specs skip, with the reason, when a closed local port accepts a connect. This is a change outside this plan, and it hides the gap on any machine with the same setup.
