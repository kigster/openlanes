# Cart Quantity Limits

Customers of Example Corp's shop can add negative or absurd quantities to a cart.

## What research needs to settle

1. Where is quantity validated today?

## Research

1. Nowhere. `lib/cart.rb:4` stores whatever `add` receives.
2. The checkout service rejects quantities above 99 with a 422 (`lib/checkout.rb:12`).

### Could not settle

1. Whether zero should remove the line or be rejected.

## Goal

Validate quantities in the cart.

## Non-Goals

- Changing the checkout limit.

## In scope

- Handles errors.

## Out of scope

- Bulk orders.

## Back end / front end

All back end.

## Open questions

None.

> [!NOTE]
>
> [2026-09-04 12:02:11 PM PDT] [ agent: spec-writer   status: Started, round 1 ]
> [2026-09-04 12:04:02 PM PDT] [ agent: spec-writer   status: Completed, round 1 ]
