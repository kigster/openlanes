---
created: 2026-10-24
starts: research
depends_on: [none]
---

# Remove New Relic

## What we are trying to achieve

`newrelic_rpm` and `newrelic-infinite_tracing` leave the Gemfile and `lib/openlanes/web/app.rb` (A5). Openlanes carries no vendor tracing gem; a user who wants one wraps the gem and adds their own.

## Why it matters

Every install pulls a vendor agent nobody configured, and it blocks the vendor-neutral OpenTelemetry instrumentation in A13.

## What already exists

`Gemfile` lines 31-32 and the two `require` lines at the top of `lib/openlanes/web/app.rb`; any `newrelic.yml` in the repository.

## What research needs to settle

- Whether anything else references New Relic (config, docs, CI).
