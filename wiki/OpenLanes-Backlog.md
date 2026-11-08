<!-- generated-by: bin/wiki-gen -->

# OpenLanes Backlog

**Up:** [Proposals and Research](Proposals-and-Research.md)

______________________________________________________________________

This is what the Review Team found when comparing OpenLanes and its `.plans` with the tools listed in issue #52, plus what came up in PR reviews #72–#84. Items are ordered by impact, most important first, and the team agreed on the order. Each one says why it matters and what "done" looks like.

## P0: Safe to run unattended

Until these are done, auto-merge with nobody watching isn't safe for anyone but the author.

1. **Rotate the leaked New Relic key and prevent the next leak.** A live license key sits in `config/newrelic.yml` in a public repo. Rotate it first; deleting the file isn't enough, because the key stays in git history. Then add `gitleaks`/`detect-secrets` pre-commit hooks, a CI secret scan, and SOPS or environment variables for config.
   *Done when* the old key is revoked and CI fails on a planted test secret.
1. **Stop the factory from committing run state.** PR branches commit `.plans/*/state.json` with local pids, hosts and sessions, and move plan folders into review or rejected states (#72, #78, #79, #80, #81, #82, #83). Separately, plans 014, 024 and 030 are merged but still say building or new, which is why agents keep writing second versions (#76, #78, #83).
   *Done when* a CI guard rejects committed run state, and a plan's status is set from its merged PR.
1. **Make cross-machine claims safe.** A plan's Redis claim must be held until the last agent has actually exited, not dropped when STOP is written (#80).
   *Done when* stopping a plan on one machine can't let another machine start a duplicate agent on the same branch.
1. **Add merge gates (plan 033).** Treat "no checks reported" or "skipped" as failing, and keep the merge token in the merge step only, where no agent can read it.
   *Done when* a PR with zero CI checks is never auto-merged, and no agent can read the merge token from its environment, files or tools.
1. **Set spend limits with a hard stop.** Add a budget per run and per lane, metered for every adapter rather than only Claude.
   *Done when* exceeding a budget stops dispatch, whichever provider the lane uses.
1. **Decouple from Claude with a sandbox that works for every provider.** Tool allow and deny lists and the Bash limits exist only in `claude.rb`, and `pi.rb` has no sandbox at all. Claude is also the default (`adapters.rb:82`), and `brief.rb:206` and the pinned verifier call `claude` directly. Add a model alias map per adapter. Resume, compaction and tool denial need an equivalent on codex, pi and OpenRouter, or the run should refuse to start.
   *Done when* the same denial specs pass for every adapter, or the adapter refuses to start.
1. **Put a login on the control room.** The board has no authentication, `GET /api/session` hands out the CSRF token openly, and plan 017 (#79) writes `spec.md`/`plan.md` when accessed from beyond loopback.
   *Done when* any request from beyond loopback without a session is refused, and writes require a session plus a CSRF token.

## P1: A gem people can install and trust

8. **Keep main green.** Fix the four known failing specs and the integration specs that only fail in a full local run.
1. **Make New Relic optional.** `newrelic_rpm` and `newrelic-infinite_tracing` are hard dependencies, and `lib/openlanes/web/app.rb:7-8` loads them unconditionally. Load them only when `NEW_RELIC_LICENSE_KEY` is set.
1. **Fix the Ruby version and gem hygiene.** The gemspec says Ruby `>= 4` but the README says 3, so most `gem install`s fail. Settle on one, pin the dependencies, and add a CHANGELOG.
1. **Make `init` and `setup` ask before installing, and check the configured adapter.** `init` runs `brew bundle` without asking, and setup checks only for `claude`. Ask before installing when a person is at the terminal, and only report when nobody is. Check the adapter `.openlanes.yml` selects. Keep the runtime `Brewfile` minimal (#82, #84), and add a Linux path.
1. **Finish the verdict-label migration.** Old `ready-to-merge`/`ok-to-merge` labels still sit next to `review-*`, and #78 does nothing on the live repo.
1. **Redact infrastructure from verification artifacts.** Committed verification output shows Redis hostnames and local paths (#82).

## P2: Gaps compared with the competition

14. **Keep running with the laptop closed.** Run on a server or in the cloud, and supervise from a phone.
01. **Revert in one step, and measure with evals.** Undo a bad merge with one command, and track whether agents actually get better.
01. **Take work from an issue tracker.** Pull work from GitHub Issues or Linear, not only from `.plans`.
01. **Support other code hosts and several repos.** Today it works only with GitHub through `gh`, and with one repo at a time, Redis keys and chat included.
01. **Export metrics.** The JSONL event log exists, but there's no OTel or Prometheus export and no alerting.

## P3: Maintainability

19. **Split `engine/dispatcher.rb`.** It's 1,954 lines. Split it by lifecycle stage, and do that before plan 033 adds merge logic to it (item 4).
01. **Decide what the `src/main.rs` stub is for**, or remove it.
01. **Memoize `brew bundle check` in setup.** Today it runs about five times per `init`.

<sub>Lifted verbatim from [`docs/decisions/suggestions-from-grok-on-general-improvements.md`](https://github.com/kigster/openlanes/blob/main/docs/decisions/suggestions-from-grok-on-general-improvements.md).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`docs/decisions/suggestions-from-grok-on-general-improvements.md`](https://github.com/kigster/openlanes/blob/main/docs/decisions/suggestions-from-grok-on-general-improvements.md)
