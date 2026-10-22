# Verification, round 1

Verdict: rejected

## Steps

1. `just web-install`: passed
2. `just web-test`: passed
3. `just web-build`: passed
4. `just web-e2e`: passed
5. `bundle exec rspec spec/openlanes/web`: passed
6. `bundle exec rubocop`: passed
7. By hand: `just web-demo`: failed

## Failing step

- Step: 7
- What: By hand: `just web-demo`, then open `http://127.0.0.1:11000`
- Expected: the recipe starts the demo server so the divider can be exercised
- Seen: `error: justfile does not contain recipe 'web-demo'` (`Did you mean 'web-dev'?`). Recipes available: build, preview-e2e, web-build, web-dev, web-e2e, web-install, web-test. Fix the step (e.g. `./exe/openlanes web --demo`) or add the recipe. The manual drag, focus, reload and 960px checks need a browser and could not be run in this shell; divider.cy.ts (7/7) covers the same behaviour.

Screenshots are kept as step-NN.txt: magick cannot load a font here.
