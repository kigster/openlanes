# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 14 | [[001.00] Cart total](https://github.com/example/shop/pull/14) | Open 🟡 |

## Findings

1. `.openlanes.yml:5` lowers `coverage.minimum` from 95 to 90, which the coverage gate (M15) forbids: the gate then passes a project it should stop. Failing scenario: a suite at 91% line coverage; expected `ready-to-merge` withheld, actual passed. Restore `minimum: 95`.
2. `spec/cart_spec.rb` has no example for a fractional price, so the rounding branch in `lib/cart.rb:8` is the untested line the minimum was lowered to hide. Failing scenario: `cart.add(0.5, 3)`; expected a test pinning `total` to 2, actual no test reaches it.

> [!NOTE]
>
> [2026-10-14 10:00:00 AM PDT] [ agent: hansolo-reviewer   status: Started, round 1 ]
> [2026-10-14 10:03:20 AM PDT] [ agent: hansolo-reviewer   status: Completed, round 1 (rejected 1/2) ]
