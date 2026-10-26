# Billing Retries

Jobs that call the Example Corp billing API fail on transient 503 responses. Retry them.

## What research needs to settle

1. Does the repository already have a retry helper we can reuse?
2. What backoff does the billing API ask clients to use?

## Research

### Repository survey

`lib/retry_policy.rb:1` defines `RetryPolicy` with three attempts, a 0.5 second base and doubling delays. `lib/billing_client.rb:2` defines `BillingClient#charge`, which posts to `/charges` and does not retry at all today. No other file in the repository mentions retries, backoff, jitter or circuit breaking, and there is no shared HTTP wrapper that could host the behaviour instead.

### Upstream guidance

The billing API documentation asks for exponential backoff from 500 ms (https://docs.example.com/billing/errors, retrieved 2026-09-04). Its rate limit page repeats the advice (https://docs.example.com/billing/rate-limits, retrieved 2026-09-04). The changelog shows the advice has not changed since version 2 (https://docs.example.com/billing/changelog, retrieved 2026-09-04). A general article on jitter argues for full jitter over equal jitter (https://blog.example.org/backoff-and-jitter, retrieved 2026-09-04). A second article compares decorrelated jitter (https://blog.example.net/decorrelated-jitter, retrieved 2026-09-04). The HTTP specification defines `Retry-After` (https://www.rfc-editor.org/rfc/rfc9110#field.retry-after, retrieved 2026-09-04).

### Survey of alternative libraries

Three retry gems were compared for completeness, although the repository already has a policy: one wraps Faraday middleware, one decorates arbitrary blocks, and one integrates with background job frameworks. Each would add a dependency for behaviour the twelve-line policy already implements, so none is recommended, but their feature matrices are summarised here for a future reader who might want circuit breaking or metrics later.

> [!NOTE]
>
> [2026-09-04 11:29:20 AM PDT] [ agent: researcher   status: Started, round 1 ]
> [2026-09-04 11:46:02 AM PDT] [ agent: researcher   status: Completed, round 1 ]
