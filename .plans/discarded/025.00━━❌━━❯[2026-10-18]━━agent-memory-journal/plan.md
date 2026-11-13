## How to test

- An entry printed by the agent appears in `state.json` under its agent and round, in order, and validates against the schema.
- An `override` names the entry number it overturns.
- A killed agent's already-printed entries are kept.
- Round n+1's prompt contains round n's journal, with or without `--resume`.
- Reviewers (031) and backend-coder and frontend-coder answering a review journal the same way.
