# Billing Retries

Jobs that call the Example Corp billing API fail on transient 503 responses. Retry them.

## What research needs to settle

1. Does the repository already have a retry helper we can reuse?
2. What backoff does the billing API ask clients to use?

## Research

### Reuse in this repo

- `lib/retry_policy.rb:2`: `RetryPolicy`, bounded exponential backoff (three attempts, 0.5 s base, doubling). `BillingClient#charge` (`lib/billing_client.rb:2`) does not use it yet.

### Existing components

- [retriable](https://github.com/kamui/retriable): block-level retries with exponential backoff and jitter; fits if the policy should grow jitter, otherwise the repository's own policy is enough.

### Open questions for yoda

1. What backoff does the billing API ask clients to use, and does it send `Retry-After` on 503?
2. Is `charge` idempotent on retry?

> [!NOTE]
>
> [2026-10-24 11:29:20 AM PDT] [ agent: leah-researcher   status: Started, round 1 ]
> [2026-10-24 11:30:42 AM PDT] [ agent: leah-researcher   status: Completed, round 1 ]
> [2026-10-24 11:30:43 AM PDT] [ next: yoda-writer ]
