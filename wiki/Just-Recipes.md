<!-- generated-by: bin/wiki-gen -->

# Just Recipes

_Every `just` recipe in the justfile, with the comment that documents it._

**Up:** [Development](Development.md)

______________________________________________________________________

## [`justfile`](https://github.com/kigster/openlanes/blob/main/justfile)

| Recipe                     | Runs first           | Description                                                                                                                                           |
| -------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `just recipes`             | —                    | —                                                                                                                                                     |
| `just start`               | —                    | The engine, its API server and the page in mprocs, 4 agents at a time; the page reloads as you edit it                                                |
| `just run`                 | —                    | alias for `start`                                                                                                                                     |
| `just install`             | —                    | Sync all dependencies                                                                                                                                 |
| `just build`               | `install web-build`  | Sync dependencies and build the page the gem ships (web/dist)                                                                                         |
| `just web-install`         | —                    | Install the page's dependencies                                                                                                                       |
| `just web-build`           | —                    | Build the page into web/dist, which the gem ships and the API server serves                                                                           |
| `just web-dev`             | —                    | The page's dev server on 5173 beside this checkout's API server on 11000, which Vite proxies /api to                                                  |
| `just web-e2e`             | —                    | Cypress against two demo servers, the second as demo@second-machine; run `just web-build` first                                                       |
| `just preview-e2e`         | —                    | The Preview tab's Cypress run: a real app runner beside `openlanes web --demo` on 11050; run `just web-build` first                                   |
| `just factory-e2e`         | —                    | Real agents build a tic-tac-toe page through `openlanes start`; spends tokens, needs OPENLANES_FACTORY_E2E=1                                          |
| `just lanes-e2e`           | —                    | Real agents work three quick-lane plans while /concurrency, /stop and /restart are typed into the copilot; spends tokens, needs OPENLANES_LANES_E2E=1 |
| `just web-test`            | —                    | Lint, type-check and unit-test the page, with coverage                                                                                                |
| `just lint`                | —                    | rubocop                                                                                                                                               |
| `just format`              | —                    | Fix style with rubocop, then format the markdown                                                                                                      |
| `just update-workflow`     | —                    | —                                                                                                                                                     |
| `just update-architecture` | —                    | Regenerate the class diagrams of OpenLanes itself in docs/architecture                                                                                |
| `just test *args`          | `web-build`          | Run all the tests                                                                                                                                     |
| `just eval *args`          | —                    | Score every agent's eval cases against their recordings                                                                                               |
| `just test-coverage *args` | —                    | Run tests with coverage                                                                                                                               |
| `just ci`                  | `lint test-coverage` | —                                                                                                                                                     |
| `just check-all`           | —                    | alias for `ci`                                                                                                                                        |
| `just clean`               | —                    | —                                                                                                                                                     |
| `just lefthook`            | —                    | Run all lefthook pre-commit hooks                                                                                                                     |
| `just version`             | —                    | Print current gem version                                                                                                                             |
| `just clobber`             | —                    | Clobber                                                                                                                                               |
| `just doc`                 | —                    | Generate documentation                                                                                                                                |
| `just release`             | —                    | Tag v{{ version }}, publish the GH release, & refresh the Homebrew tap.                                                                               |

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`justfile`](https://github.com/kigster/openlanes/blob/main/justfile)
