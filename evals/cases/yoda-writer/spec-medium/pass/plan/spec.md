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

A cart can only ever hold quantities the checkout will accept, so a customer learns about a bad quantity when they type it rather than at payment. Framed two ways, as a validation problem in `Cart#add` or as a contract shared with checkout, the second wins: the limit already lives in `lib/checkout.rb:12`, and copying it would let the two drift.

## Non-Goals

- Changing the checkout limit of 99.
- Per-product stock limits; stock is a separate system.
- Changing how the cart is persisted.
- Localising the error message beyond English.

## In scope

- `Cart#add` with a quantity below 1 raises `Cart::InvalidQuantity` and leaves the cart unchanged; a spec proves it.
- `Cart#add` with a quantity above the checkout limit raises the same error; the limit is read from `Checkout::MAX_QUANTITY`.
- The cart page shows the error next to the quantity field, and the field keeps the rejected value.

## Out of scope

- Bulk orders above 99: they need a sales contact flow, which is a product decision.
- Backfilling existing carts that already hold bad quantities: none exist in production per the research.

## Back end / front end

| Item | Half |
| --- | --- |
| `Cart#add` validation and the shared constant | luke-backend |
| Error display on the cart page | rey-frontend |

## Open questions

1. Whether zero removes the line or is rejected (leah could not settle it). Assumed: rejected.

## Risks

- The checkout constant is private today; making it public touches a file another team owns.

## Conclusion

When this ships, a cart cannot hold a quantity checkout would refuse, the limit is defined once, and the customer sees the problem on the cart page.

> [!NOTE]
>
> [2026-09-04 12:02:11 PM PDT] [ agent: yoda-writer   status: Started, round 1 ]
> [2026-09-04 12:09:40 PM PDT] [ agent: yoda-writer   status: Completed, round 1 ]
> [2026-09-04 12:09:41 PM PDT] [ next: luthen-rael-planner ]
