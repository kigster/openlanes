---
depends_on: []
---

# App Runner and Preview

## What we are trying to achieve

The engine starts the app a plan builds, from `app.processes` in `.openlanes.yml`, gives each process a port from 11100, restarts it when its `restart_on` files change, and shows it in a Preview tab.

## Why it matters

Verification (M1) and a human checking a PR both need the app running, whatever its stack.

## What already exists

- Decisions M12 and M13 in `docs/decisions/decisions-on-merge-modes-and-verification.md:117-130`.
- `lib/openlanes/execution/child.rb:48` (`Child.spawn(argv, chdir:, env:)`, process group, TERM then KILL after `TERM_GRACE`), and the web control room in `web/` served by `lib/openlanes/web.rb`.

## What research needs to settle

- Readiness checks, port allocation and per-checkout isolation.
- Detecting an app that refuses to be framed.
- Mirroring a headless browser into the tab.

## How to tell it's working?

- A two-process app (API and web) starts in order; the tab shows the web process, labelled with plan, branch and port.
- Editing a `restart_on` file restarts only that process, and the toolbar says so.
- A framing-protected app opens in a separate window.

## Framings considered

1. **Process manager first.** A supervisor module (`Execution`-level) that owns start order, ports, readiness and restart, with the Preview tab a thin consumer of its status events.
1. **Tab first.** Start with the Preview tab and an iframe, and bolt supervision on as the tab needs it.

**Chosen: 1.** The three acceptance checks above are all supervisor behaviour (order, restart-only-one, framing refusal read from headers), and the tab can only show what the supervisor reports. Research confirms spawn code is reusable (`child.rb:48`) and that no `app:` config, port code or watcher exists, so the supervisor is the missing piece.

## Goal

A plan's app can be started, kept running and previewed by the engine from a declarative `app:` block, for any stack: processes start in declared order on engine-allocated ports, become ready by a check, restart individually when their `restart_on` files change, and one process marked `preview: true` appears in a Preview tab, or in a separate window when it refuses framing. Today nothing in `lib/` starts an app, allocates a port or watches a file.

## Non-Goals

- Writing `app:` for the user. luke or r2d2 writes it on the first build (M12); this plan only reads it.
- The stack questionnaire and `stack:` summary (M16).
- Driving the app: the headless browser, `## How to test` steps and the verdict belong to `chewie-verifier` (M1, M11), which does not exist in `agents/` yet.
- Production deployment, containers or remote hosts. Everything runs on 127.0.0.1.
- Per-plan configuration of port ranges beyond the 11100 floor.
- Mirroring a headless browser (M13 screenshots), see Out of scope.

## In scope

Each item has its check.

1. **Config.** `Config` accepts an `app:` key with `kind` and `processes[]` (`name`, `start`, `ready`, `restart_on`, `preview`). Check: spec loads a valid file; a file with an unknown key inside `app:` or a missing `name`/`start` is refused with the file named, as `config.rb:125-128` does today.
1. **Preview uniqueness.** At most one process has `preview: true`. Check: spec for two, and for zero (no tab, no error).
1. **Port allocation.** Each process gets the lowest free port at or above 11100, exported as `PORT_<NAME>` (name upcased, non-alphanumerics to `_`) to every process of the app, so a web process can find its API. Check: spec starting two processes sees 11100 and 11101 in their env; a port held by another listener is skipped.
1. **Port registry.** Allocation is recorded in one machine-wide registry, not per checkout, so two worktrees of one app never collide. Check: spec with two supervisors in different directories receives disjoint ports.
1. **Ordered start with readiness.** Processes start in declared order; the next starts only after the previous is ready. Ready is a TCP connect to its port, then, when `ready:` names an HTTP path, a 2xx or 3xx on that path. Check: a fixture whose second process records the time its first answered.
1. **Readiness failure.** A process that exits, or is not ready within a timeout, fails the app start; already-started processes are stopped. Check: spec asserts no live child remains.
1. **Port honoured.** After ready, the supervisor confirms the listener is on the allocated port; an app that moved elsewhere fails with a message naming the port it was given. Check: fixture server that binds a different port.
1. **Restart on change.** A change to a file matching one process's `restart_on` globs restarts that process only: TERM, wait for exit, start, wait ready; its siblings keep their pids. Check: spec records pids before and after.
1. **Status events.** The supervisor emits per-process states (starting, ready, restarting, stopped, failed) through the existing SSE events (`lib/openlanes/web/events.rb`). Check: events spec for each transition.
1. **Preview tab.** A tab per running app, labelled with plan, branch and port, with a toolbar showing ● running or restarting and Restart backend, Open in new window and Stop. Check: Cypress spec in `web/cypress`.
1. **Framing refusal.** Once ready, the engine requests the preview path itself and reads `X-Frame-Options` and `Content-Security-Policy: frame-ancestors`; any `DENY`, any `SAMEORIGIN` (the origins differ by port), or a `frame-ancestors` that excludes the control room origin sends the tab to a separate window. Check: specs for each header value, plus none, which frames.
1. **Stop.** Stopping the app, or the engine exiting, terminates every process group and releases its ports. Check: spec asserts the ports are free and no child lives.
1. **Opt-in.** A project without `app:` behaves exactly as today. Check: the full suite stays green (`bundle exec rspec`) with no Preview tab rendered.

## Out of scope

- **Screenshot mirroring in the tab (M13, last bullet).** Needs the headless browser, which `chewie-verifier` owns and which is not chosen (research, mirroring section). Ship when chewie lands; the tab's image area and SSE event type are left to that plan.
- **CDP screencast.** Its ack protocol is unproven (research); the 2-second screenshot poll comes first.
- **Starting the app in the factory e2e harness (`bin/factory-e2e`).** It uses its own ports (4848, 4777); migrating it is separate.
- **Detecting defaults of Vite, Next.js, FastAPI.** Research did not check them; the header check reads the real response, so this plan does not depend on it.
- **Auto-patching a dev server's config (for example `strictPort`).** The start line is the author's; the supervisor only reports a moved port.

## Back end / front end

| Item | Built by |
| :--- | :--- |
| 1, 2 Config | `luke-backend` (`lib/openlanes/support/config.rb`) |
| 3, 4 Ports and registry | `luke-backend` |
| 5, 6, 7 Start, readiness, port check | `luke-backend`, on `Execution::Child` |
| 8 Restart on change | `luke-backend` |
| 9 Status events | `luke-backend` emits; `rey-frontend` consumes |
| 10 Preview tab | `rey-frontend` (`web/src`), against the event shape luke fixes first |
| 11 Framing refusal | `luke-backend` decides and sends a flag; `rey-frontend` opens the window |
| 12, 13 Stop, opt-in | `luke-backend`; `rey-frontend` for the hidden tab |

The pair agrees the event payload (process name, state, port, framing flag) before either builds against it.

## Open questions

Answered here by the recommendation in research; they are assumptions until a human objects:

1. **Readiness**: TCP connect, then optional HTTP path from `ready:` (research, recommended). Assumed.
1. **Registry location**: machine-wide, in a file under the user's state directory with a lock, because worktrees on one machine collide otherwise (research, judgement). Exact path is unsettled: decide in planning.
1. **App ignores its port**: the plan fails with a message; the harness does not follow the app's chosen port. Assumed, because the Preview URL and `PORT_<NAME>` must agree. Not sourced.
1. **Framing check**: once at ready and again after each restart, on the preview path; not on every reload. Assumed.
1. **File watcher**: no mechanism exists (research searched `lib/`). Library versus polling is unsettled; plan picks the smaller dependency. A restart waits for the old process to exit (TERM, then KILL after `TERM_GRACE`, `child.rb:28`). Assumed.
1. **Browser and mirroring** (leah's 6): deferred with chewie, see Out of scope.
1. **Default dev-server headers** (leah's 7): not checked and not needed.
1. **Vite `--strictPort` flag** (leah's 8): unconfirmed; only matters to what luke writes in `start`, not to this plan.
1. **Restart backend button**: which process it restarts when several are non-preview. Assumed: every non-preview process, in declared order. Not specified in M13.
1. **Readiness timeout default** and the glob dialect of `restart_on` are not specified anywhere; the planner picks and documents them.

## Risks to planning or execution

- **Port race.** Probe-then-spawn leaves a gap (research); the registry must reserve, and retry on `EADDRINUSE`.
- **Orphaned grandchildren.** Dev servers spawn children that outlive TERM; `Child` already warns of it (`child.rb:80`). The supervisor must lean on the group kill.
- **Cross-pair coupling.** `rey-frontend` depends on luke's event shape; the planner should sequence the event contract as the first unit.
- **No production precedent.** M12 and M13 are design only (research), so the `app:` schema is new surface and hard to change once luke starts writing it into projects.
- **Watcher flakiness in specs.** File-event timing makes restart specs slow or flaky; prefer an injectable clock/poller, as the suite already injects doubles.
- **Dependency on `chewie-verifier`.** M1 verification cannot run until both land; this plan must stand alone and must not block on it.

## Conclusion

When this ships, `.openlanes.yml` can declare an `app:` of ordered processes. The engine starts them on ports from 11100 from a machine-wide registry, waits for readiness, restarts only the process whose files changed, and stops them all cleanly. The Preview tab shows the `preview: true` process labelled with plan, branch and port, or opens a separate window when response headers refuse framing. Mirroring chewie's browser and the verification itself are left to the plan that adds `chewie-verifier`.

## Research

Gathered 2026-10-14. Repository claims cite `file:line`; upstream claims cite a URL.

### Readiness, ports and isolation

- **No `app:` support exists.** `lib/openlanes/support/config.rb` rejects unknown keys ("Anything unknown is an error"), so `app:` fails today until `Config` learns it.
- **Ports.** Nothing in `lib/` reads `PORT` or allocates ports. Taken already: 11000 for the control room (`lib/openlanes/web.rb:26`), 4848 and 4777 in examples and `bin/factory-e2e:36`. M12's 11100-upward range is free.
- **The app may ignore the port.** Vite, without `server.strictPort`, moves to the next free port, so the port it reports can differ from the one given. With `strictPort` it exits instead ([Vite server options](https://vite.dev/config/server-options.html), read 2026-10-14). So the harness cannot assume `$PORT_<NAME>` is honoured: it must confirm the port the process listens on, and a `start` line may need `strictPort` set. Whether Vite accepts `--strictPort` as a CLI flag is not confirmed by the official page.
- **Probe-then-spawn races.** Checking a port is free and then starting the app leaves a gap in which another process takes it. Recommended: the engine holds the reservation in its own state and retries on `EADDRINUSE`, rather than trusting one probe. This is a judgement, not sourced.
- **Per-checkout isolation.** A worktree isolates files, not ports: two checkouts of one app both asking for 11100 collide. Ports must come from one registry per machine, not per checkout. Judgement, not sourced.
- **Process supervision is reusable.** `Execution::Child.spawn(argv, chdir:, env:)` (`lib/openlanes/execution/child.rb`) already takes an env hash, starts a process group, and stops the group with TERM then KILL. `PORT_<NAME>` needs no new spawn code.
- **Readiness.** The repo has no readiness probe. Options: TCP connect to the port (proves a listener, not a working app), or an HTTP status on a path, or a log pattern. Recommended: TCP connect, then an optional HTTP path from `ready:`. Judgement.
- **Restart on file change.** I searched for `restart_on`, `watch` and `Listen` in `lib/`; no watcher code exists. Mechanism is undecided.

### Detecting an app that refuses to be framed

- **Headers, not the DOM.** `X-Frame-Options: DENY` blocks framing even from the same site; `SAMEORIGIN` allows it only from the same origin as the embedding page; `ALLOW-FROM` is obsolete ([MDN X-Frame-Options, mirror](https://docs.w3cub.com/http/headers/x-frame-options), [MDN, ko](https://developer.mozilla.org/ko-KR/docs/Web/HTTP/Headers/X-Frame-Options), read 2026-10-14). The CSP `frame-ancestors` directive supersedes it in supporting browsers, is checked for every ancestor, has no `default-src` fallback, and cannot be set by `<meta>` ([MDN frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors), read 2026-10-14).
- **Our embedding is cross-origin.** The control room (127.0.0.1:11000) and an app (127.0.0.1:11100+) differ by port, so a `SAMEORIGIN` header refuses them too. Any of the three values refuses the tab.
- **The page cannot see it.** A parent page cannot read a cross-origin frame's DOM, and a blocked frame typically still fires `load`, so an `onerror` check does not work. Judgement from the origin rules above; not tested in a browser.
- **Recommended detection:** the engine requests the preview URL itself once the process is ready, and reads `X-Frame-Options` and `Content-Security-Policy` (`frame-ancestors`). If either refuses the control room's origin, the tab opens the window instead (M13). Caveat: a route can send different headers, so the check should use the path the tab opens. Whether Vite, Next.js or FastAPI send these headers by default is not checked.

### Mirroring a headless browser into the tab

- **Decided so far:** M13 specifies a screenshot about every 2 seconds.
- **Transport already exists.** The control room streams over SSE through Sinatra's `stream` helper on 127.0.0.1 (`docs/decisions/decisions-on-web-ui-and-review-labels.md:20`). `lib/openlanes/web/events.rb:97` frames each event as JSON, so a base64 image fits inside an existing event.
- **Screencast is possible but unproven here.** `Page.startScreencast` sends `Page.screencastFrame` events. Unofficial sources report that the client must send `Page.screencastFrameAck` for each frame, or capture stalls on an animating page ([browser-use/browsercode PR 124](https://github.com/browser-use/browsercode/pull/124), read 2026-10-14; [MacMyths](https://macmyths.com/how-to-fix-low-fps-chrome-devtools-protocol-screencasts/), read 2026-10-14). I did not retrieve the official CDP reference, so treat the ack rule as one test run, not a spec.
- **The browser is not chosen.** `chewie-verifier` does not exist in `agents/` yet. Searches of `lib/`, `web/src`, `agents/` and `docs/` for Playwright, Puppeteer and CDP found nothing.
- **Recommended:** ship the M13 screenshot poll first, since it needs no ack protocol and reuses SSE. Screencast is a later upgrade only if the 2-second poll is too slow to watch.

### Findings, Conclusion & References

**Contradictions**

- None between the spec, M12 and M13: both say 11100 and a `preview: true` process.
- Production runs none of this. No `app:` key, no port code, no watcher, no preview tab. M12 and M13 describe a design only.
- This spec repeats the empty template headings at its foot ("What we are trying to achieve" and the rest, after "How to tell it's working?"). Yoda should drop the duplicates.

**Open questions** (for yoda to lift)

1. Is readiness a TCP connect, an HTTP status on a path, or both?
2. Does the port registry live in the engine state, or per machine across runs?
3. When an app ignores `$PORT_<NAME>`, does the plan fail, or does the harness read the port the app chose?
4. Is the framing check done once at ready, or on every reload?
5. What watches `restart_on` files, and does a restart wait for the old process to exit?
6. Which headless browser does `chewie-verifier` drive, and is the tab fed by screenshot poll or by screencast?
7. Do the default dev servers (Vite, Next.js, FastAPI) send `X-Frame-Options` or `frame-ancestors`? Not checked.
8. Confirm whether Vite accepts `--strictPort` as a CLI flag (only a third-party blog says so).

**Checks run**

- `bundle exec rspec` in this worktree: `2214 examples, 0 failures`, 34.7 s, coverage 98.63%.

**Sources**

- [MDN X-Frame-Options (w3cub mirror)](https://docs.w3cub.com/http/headers/x-frame-options), read 2026-10-14, public
- [MDN X-Frame-Options (ko-KR)](https://developer.mozilla.org/ko-KR/docs/Web/HTTP/Headers/X-Frame-Options), read 2026-10-14, public
- [MDN frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors), read 2026-10-14, public
- [Vite server options](https://vite.dev/config/server-options.html), read 2026-10-14, public
- [browser-use/browsercode PR 124](https://github.com/browser-use/browsercode/pull/124), read 2026-10-14, public (one test run, Chrome 150 headless)
- [MacMyths, low-fps screencasts](https://macmyths.com/how-to-fix-low-fps-chrome-devtools-protocol-screencasts/), read 2026-10-14, public (unofficial)

No paywalled or licensed sources were cited.
