# Cart Retention

Delete abandoned carts automatically.

## Research

1. Carts are never deleted today (`lib/cart_store.rb:9`).

## Constraints

- Deletion runs nightly.
- An abandoned cart is kept for ninety days, counted from the last change to the cart, then deleted.
  Decided 2026-09-01 by the product owner: retention is ninety days from the last change.

> [!NOTE]
>
> [2026-09-04 06:00:00 PM PDT] [ agent: unblocker   status: Started, round 1 ]
> [2026-09-04 06:00:41 PM PDT] [ agent: unblocker   status: Completed, round 1 ]
