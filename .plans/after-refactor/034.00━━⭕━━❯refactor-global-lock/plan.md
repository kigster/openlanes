# Plan — 034.00 Refactor Global Lock

## Backend

### U1 Execution mode
- Owns: `lib/openlanes/plans/execution.rb`, `spec/openlanes/plans/execution_spec.rb`. Depends on: nothing.

### U2 Global lock gate
- Owns: `lib/openlanes/plans/global_lock.rb`, `spec/openlanes/plans/global_lock_spec.rb`. Depends on: U1.

### U3 Threshold setting
- Owns: `lib/openlanes/support/config.rb`, `spec/openlanes/config_spec.rb`. Depends on: U1.

### U4 Dispatcher and runner hooks (integration check)
- Owns: `lib/openlanes/engine/runner.rb`, `lib/openlanes/engine/dispatcher.rb`, `spec/openlanes/engine/dispatcher_spec.rb`. Depends on: U2.

### U5 Planner instructions
- Owns: `agents/planner.md`. Depends on: U3.

## Frontend

No front-end work in this plan.

## HTTP surface

No.

## How to test

- A refactor spec over the threshold gets `execution: global-lock-required`.
- The dispatcher starts no new plan while it waits, and the board names what it waits on.
- Nothing else starts until it is merged.
