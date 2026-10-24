---
lane: full
depends_on: ["034.00"]
---
# Expression Evaluator

`Calc::Evaluator.call(tree)` computes the value of the tree that
`Calc::Parser.parse` returns. The parser comes from plan 034.00; this plan
walks its output and computes the arithmetic.

> [!NOTE]
>
> [2026-10-16 09:00:00 AM PDT] [ agent: ewoki-linker   status: Started, round 1 ]
> [2026-10-16 09:00:40 AM PDT] [ agent: ewoki-linker   status: Completed, round 1 ]
> 034.00: the evaluator needs the parser 034 builds.
