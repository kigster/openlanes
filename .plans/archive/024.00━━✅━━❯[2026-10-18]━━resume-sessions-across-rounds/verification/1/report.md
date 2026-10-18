# Verification, round 1

Verdict: verified

## Steps

1. Every round's session id is stored in its stage in state.json: passed
2. Round 2 is invoked with --resume <round 1 session id>: passed
3. Moved plan or missing session starts fresh and the log says why: passed
4. An adapter that cannot resume starts fresh: passed

Note: no app declared; steps were checked through the shell by running the real-Runner/Executor integration spec (6 examples, 0 failures), one example group per step. Screenshots are text captures rendered to PNG.
