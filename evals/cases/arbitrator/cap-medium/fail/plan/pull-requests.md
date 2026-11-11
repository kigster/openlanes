# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 9 | [[001.00] Ledger append](https://github.com/example/shop/pull/9) | Open 🔴 |

## Findings

- F1 critical: `lib/ledger.rb` opens `ledger.log` with "w", so each append erases every earlier line. No spec writes twice.
- F2 minor: `append` could be named `<<`.

> [2026-10-20 09:00:00 AM PDT] [ agent: staff-reviewer     status: Completed, round 2 (rejected 2/2) ]
