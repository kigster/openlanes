# Verification, round 1

Verdict: rejected

## Steps

1. Web suite (lint, typecheck, coverage): passed
2. Ruby suite (rspec, rubocop): passed
3. By eye: `just web-build && just web-demo`: failed

## Failing step

- Step: 3
- What: `just web-build && just web-demo`, open http://127.0.0.1:11000
- Expected: the demo board is served and running cars show a turning gear
- Seen: `just web-build` succeeds, but `just web-demo` fails with "justfile does not contain recipe `web-demo`" (justfile suggests `web-dev`). The recipe the How to test names does not exist, so the step cannot be run. Either add the recipe or change the How to test (e.g. `openlanes web --demo`). Steps 4 and 5 were not run. Screenshots are step-NN.txt: `magick` hung rendering PNGs.
