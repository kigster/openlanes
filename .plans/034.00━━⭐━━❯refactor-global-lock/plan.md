## How to test

- A refactor spec over the threshold gets `execution: global-lock-required`.
- The dispatcher starts no new plan while it waits, and the board names what it waits on.
- Nothing else starts until it is merged.
