# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 22 | [[001.00] Invoice tax](https://github.com/example/shop/pull/22) | Open 🟡 |

## Findings: design-reviewer

### F201 [critical] lib/invoice.rb:2

⛔️ The sales-tax rate is now written down twice: `Invoice::TAX_RATE` repeats `Tax::RATE` from `lib/tax.rb`. Failing scenario: the rate changes to 0.09 in `lib/tax.rb`; expected, every invoice charges 9%; actual, `Invoice.new(10_000).total` still returns 10_825. Call `Tax.on(@subtotal)` instead.

> [!NOTE]
>
> [2026-10-28 05:00:00 PM PDT] [ agent: design-reviewer    status: Started, round 1 ]
> [2026-10-28 05:02:10 PM PDT] [ agent: design-reviewer    status: Completed, round 1 (rejected 1/2) ]
