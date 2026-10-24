## How to test

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.

## Task completed when

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.

## Backend

### U1 Three levels in Config — done (round 1)

`Config::QUALITIES = %i[high standard mvp]`; `MAX_REJECTIONS_BY_QUALITY` gives standard 2.

### U2 Q1 asks three options, records the decision — done (round 1)

`QualityQuestion::CHOICES` holds a/b/c in the spec's words, read by the page, `openlanes init` and the live `answer` command. Every answer (and `init` with a quality) appends a section to `.plans/decisions.md` listing all three options, the chosen one marked.

### U3 Send-back under standard — done (round 3)

`standard` sends a `review-ok-not-perfect` PR back to 🟡 (`Outcome::SEND_BACK`), `high` to 🔴; both counted, the note names the quality, and the mail goes to whoever handles the destination. The state machine gains an `in_review → building` edge, and `Dispatcher#approved` takes a 🟡 after the hand-off as its result.

### U4 Block all work while the key is missing — done (round 2)

With no `desired_codebase_quality:`, `openlanes run` asks on a terminal before any agent starts (`QualityQuestion.settle!`: key, `decisions.md`, and any open page question settled). Without a terminal the dispatcher starts nobody (`Runner` `quality_gate:`, `Dispatcher#quality_awaited?`) and asks Q1 on the first plan in scope, where the page shows it; the answer lifts the gate on the next tick. Dry runs are not gated.

### U5 mvp: review-approved skips verification — done (round 3)

Under `mvp` a `review-approved` PR still moves to 🧪, but `Driver#skip` writes the round's report verified and publishes it in chewie's place, so the plan waits on CI and the coverage gate and chewie never starts (`Verification.skips_verification?`).

## Frontend

No units: the page already renders whatever options `QualityQuestion.questions` returns.
