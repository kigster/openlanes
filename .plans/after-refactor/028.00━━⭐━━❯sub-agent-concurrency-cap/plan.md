## How to test

- Front-matter `concurrency:` is read, and `.openlanes.yml` `agents.<name>.concurrency` overrides it.
- The drawer dropdown writes the override.
- A second concurrent sub-agent for a cap-1 agent triggers STOP, the kill after grace, and a new round.
