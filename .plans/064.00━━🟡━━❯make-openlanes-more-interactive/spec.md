---
created: 2026-11-10
starts: planning
depends_on: [none]
---

# Make Openlanes More Interactive

## What needs to be done

- More interactive

  - Send board deltas, not full snapshots, over the existing event stream; full boards grow with plans and machines.
  - **Steer a running agent from its drawer.** The control file exists; expos**e "send a note", "extend time" and "stop after this step"** (check first: I only confirmed **set_concurrency**).
  - Show the diff and the reviewers' findings in the plan row, with accept or strike buttons that feed the arbitrator.
  - Show the cost and elapsed time per plan and per agent live, using the token meter you already stream.
