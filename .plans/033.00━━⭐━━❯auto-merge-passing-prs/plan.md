## How to test

- A passing, verified, green, clean PR is merged by the engine.
- A PR missing any one condition is not.
- After a merge, other open plan branches are rebased onto `main`, each queued until no agent is running in that checkout; a merge while another checkout is active leaves that checkout's `HEAD` alone and `Boundary` reports no violation, and uncommitted work is still protected.
