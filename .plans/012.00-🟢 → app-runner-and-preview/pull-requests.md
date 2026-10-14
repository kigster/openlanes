# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 38 | [\[012.00\] App Runner and Preview](https://github.com/kigster/openlanes/pull/38) | Open 🟡 |

## Verification (luke-backend and rey-frontend, 2026-10-14)

```
$ just lint
330 files inspected, no offenses detected

$ just test
2344 examples, 0 failures        (baseline: 2214 examples, 0 failures)
Coverage: 98.57%

$ cd web && npx vitest run && npx eslint . && npm run typecheck
Test Files  30 passed (30)
     Tests  316 passed (316)
(eslint and tsc clean)

$ just web-build && just preview-e2e      # openlanes web --demo on 11050, Redis db 13
  ✓ starts the API before the web page, shows the web page labelled with plan, branch and port, and restarts only the API
  ✓ opens an app that refuses framing in a window of its own
  2 passing

$ npx cypress run --config baseUrl=http://127.0.0.1:11051   # the existing demo suite, against this branch's build
  16 passing (actions, board, chat, needs-you)
```

What the Cypress run proves, with nothing intercepted (a real `openlanes app start --demo` on `spec/fixtures/apps/preview_project`):

- The web process found the API answering when it started (`#sibling` reads `answered <port>`), so processes start in declared order, each once the previous is ready.
- The Preview tab is labelled `▶ 012 · <branch> · :<port>` and frames `http://127.0.0.1:<port>/`; the framed page reports that same port.
- Touching `api/handler.rb` shows `◐ restarting` then `● running`, and the framed web process keeps its pid: only the API restarted.
- An app sending `X-Frame-Options: DENY` gets no iframe, and its button calls `window.open(url, "_blank", "noopener")`.

Manual: `openlanes app start` / `status` / `stop` on the fixture project; `stop` ends the runner cleanly (it once died with "can't be called from trap context", fixed in 9a415c8).

Note: `just test` rewrites `docs/badges/coverage_badge.svg`; it was reverted before each commit.
