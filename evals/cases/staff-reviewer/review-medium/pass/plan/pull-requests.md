# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 12 | [[001.00] Quantity floor](https://github.com/example/shop/pull/12) | Open 🟡 |

## Findings

1. `lib/cart.rb:5` rejects only negatives, so `add("A1", 0)` returns 0 instead of raising. The spec says zero included. Failing scenario: `expect { cart.add("A1", 0) }.to raise_error(Cart::InvalidQuantity)`.
2. `spec/cart_spec.rb` has no example for zero, which is how the defect got past CI.

> [!NOTE]
>
> [2026-09-04 05:00:00 PM PDT] [ agent: staff-reviewer   status: Started, round 1 ]
> [2026-09-04 05:03:10 PM PDT] [ agent: staff-reviewer   status: Completed, round 1 (rejected 1/2) ]
