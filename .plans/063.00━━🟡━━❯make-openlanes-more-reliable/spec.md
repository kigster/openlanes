---
created: 2026-11-10
starts: planning
depends_on: [none]
---

# Make Openlanes More Reliable

## What needs to be done

- Fix the flaky keyboard.cy.ts model-picker test: it failed #195 yesterday on a PR with no web changes.
- Regenerate Gemfile.lock in the version-bump recipe: main says 4.0.0 under a 4.0.1 gem.
- Run just update-architecture in the pre-commit hook when lib/ changes; that is what broke #196.
