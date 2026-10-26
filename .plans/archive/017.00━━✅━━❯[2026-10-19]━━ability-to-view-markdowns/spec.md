---
created: 2026-10-15
starts: research
---

# What This Is

## What this is

Whenever a plan is blocked, clicking on the bottom red pill currently opens up the big dialog at the top. 

## Proposal

Also open the drawer on the right with a dropdown of markdown files in the folder (filtered to the three that can be edited:  spec.md or plan.md or blocked.md). 

Selecting the file from the dropdown opens large modal popup, showing the markdown file rendered as HTML. 

On the bottom right of the drop down there are two buttons: [ Edit ] [ Close ]

Once the user clicks on [ Edit ] the preview is replaced with an editable textarea that has the same syntax highlighting for markdown as well as for the code blocks inside as we have elsewhere.

 There is only one popup window, so selecting another file replaces the contents. The pop up can be closed.

The popup should have an [EDIT] button and be able to switch to text area so that spec.md or plan.md can be edited.

In this mode, the [ Edit ] button is replaced with [ Save Changes ] [ Cancel ] [ Close ]

Clicking on [ Close ] after changes have been made to the file and not saved, and while still in the edit mode, pops up a confirmation: "You have unsaved changes. Save them before closing? Yes/No". 

After that the dialog closes. 

### blocked.md

In the case of blocked.md, upon saving the file the Ruby Code should check if there is any text after ## A1 answer header, and if so, it should start the unblocking agent on this plan.



<!-- cmd:01M5055EZANP1J1S8X1VSHB1CA -->

## What we are trying to achieve

We need to be able to effectively unblock technical blocks and sometimes that requires human editing of the 

For blocked.md specifically, we may want to 


## Why it matters


## What already exists


## What research needs to settle



The list is empty. The questions below are derived from the Proposal, for the author to confirm.

1. Which panel does a red pill open, and can it show files for a plan with no agent car?
2. Does a route already read plan files, and what may it read?
3. Is there a write path for `spec.md` or `plan.md`?
4. Which tests cover the path, and do they pass?

## Decisions

1. A plan with no agent car gets its file list from a new plan-level drawer. A red pill opens that drawer beside the `UnblockWidget` dialog.

   Decided 2026-10-15 by kig: the red pill opens a new plan-level drawer beside the dialog, so a plan with no car still has a file list.

2. The dropdown lists the six whitelisted names that exist in the plan folder. A new listing route provides the list. The read whitelist stays at six names.

   Decided 2026-10-15 by kig: keep the six whitelisted names, and list those that exist, through a new listing route.

3. `spec.md` and `plan.md` are editable. The body of `spec.md` is editable. Frontmatter is shown but locked, in both files.

   Decided 2026-10-15 by kig: `spec.md` and `plan.md` are editable; the body only for `spec.md`, frontmatter is shown but locked.

4. A save sends the hash of the content it read, and the server refuses the save on a mismatch. The Edit button is disabled while the plan has a live car.

   Decided 2026-10-15 by kig: the save sends the hash it read and the server refuses on mismatch; the Edit button is disabled while the plan has a live car.

5. Saves go through a new `PUT /api/plans/:ordinal/files/:name` route with the CSRF token. They do not go through a `Live::Command` kind.

   Decided 2026-10-15 by kig: a new `PUT /api/plans/:ordinal/files/:name` route with the CSRF token.

## Research

### Answers

**1. Red pill and drawer.** A red pill toggles `UnblockWidget`, the dialog docked at the top (`web/src/shell/StatusBar.tsx:17`, `web/src/App.tsx:158`, `web/src/panels/UnblockWidget.tsx:18`). It does not open a drawer. The right-hand `AgentDrawer` opens only from a car click, and it takes a required `car` prop (`web/src/App.tsx:147-148`, `web/src/panels/AgentDrawer.tsx:58`). A plan with no car therefore has no drawer to put the file list in. The proposal's "also open the drawer" needs either a new plan-level drawer or a rule that a red pill also opens the car drawer. Settled under Decisions, item 1.

**2. Read route already exists.** `GET /api/plans/:ordinal/files/:name` serves `spec.md`, `plan.md`, `contract.md`, `blocked.md`, `research.md`, `design.md` as `text/markdown` (`lib/openlanes/web/app.rb:17`, `lib/openlanes/web/app.rb:270-279`). The name is matched against that whitelist, not joined onto a path. `spec/openlanes/web/app_spec.rb:414-463` covers refusals and traversal. No frontend code calls it (`rg "files/" web/src` finds nothing). There is no listing endpoint, so the dropdown must either probe these six names or a new route must list the folder.

**3. Write path.** There is none for plan files. The only file writes from the web are command kinds posted to `POST /api/commands`, which need a CSRF token (`lib/openlanes/web/app.rb:167-168`). The `answer` kind appends to `blocked.md` (`lib/openlanes/live/commands.rb:227-232`). `KINDS` lists every accepted kind (`lib/openlanes/live/command.rb:43`). Saving `spec.md` or `plan.md` needs a new kind, or a new CSRF-protected route that reuses the `PLAN_FILES` whitelist.

**4. Editor and preview already exist.** `MarkdownEditor` has an Edit | Preview switch (`web/src/panels/MarkdownEditor.tsx:1-3`). It renders through `marked` and `DOMPurify` (`web/src/panels/markdown.ts:7-9`). The popup can reuse it. The app already has Radix dialogs (`web/src/panels/dialogs.tsx:3`), which give a single modal with Esc-to-close.

**Tests.** `bundle exec rspec spec/openlanes/web/app_spec.rb` gives 60 examples, 0 failures, run on this checkout. The web tests were not run: `web/node_modules` is absent, so `vitest` cannot start without an install. That install was not done here.

### Contradictions

- **Drawer scope.** The Proposal puts the file list in "the drawer on the right". Production has one drawer per car, and it does not open from a red pill (`web/src/App.tsx:147-148`). Production runs the car drawer.
- **Read-only route, editing wanted.** `app.rb:14-16` says the drawer and preview "may read" plan files. The Proposal wants them edited. Production has no write route, so the Proposal is not yet met.
- **Whitelist versus folder.** The route whitelist has six names (`app.rb:17`). The Proposal says "markdown files in the folder", which is wider. Production shows only the six.

### Not settled

1. **Web tests.** Not run here. Needs `npm install` in `web/`.

### Findings, Conclusion & References

**Conclusion.** The read side is nearly built: one route, one reusable editor, one dialog primitive. The write side is absent. The main design gap is that a red pill has no drawer to hold the file list when no agent car exists.

**References** (all local, no web sources used):

- `lib/openlanes/web/app.rb:14-17, 113, 167-168, 270-279`
- `lib/openlanes/live/command.rb:43`
- `lib/openlanes/live/commands.rb:227-232`
- `web/src/App.tsx:147-148, 158`
- `web/src/shell/StatusBar.tsx:17`
- `web/src/panels/AgentDrawer.tsx:58, 116`
- `web/src/panels/UnblockWidget.tsx:18`
- `web/src/panels/MarkdownEditor.tsx:1-3`
- `web/src/panels/markdown.ts:7-9`
- `web/src/panels/dialogs.tsx:3`
- `spec/openlanes/web/app_spec.rb:414-463`

## Framing

Two ways to frame the problem:

1. **A missing viewer.** A blocked plan shows a question dialog, but the files that explain the block (`spec.md`, `blocked.md`, `research.md`) cannot be read in the web UI. Fix: a file list plus a preview popup.
1. **A missing editor.** The human who unblocks a plan often needs to correct `spec.md` or `plan.md`, and today they leave the browser. Fix: make those two files editable in place.

Chosen: framing 1 as the base, with framing 2 as its second half. The read route and editor component already exist (Research, answers 2 and 4), so the viewer is the cheap part. Editing is what changes who writes to plan folders, so it gets its own guards (Decisions 3 and 4).

## Goal

From the web UI, a person looking at a blocked plan can open a plan-level drawer, pick one of the plan's markdown files from a dropdown, read it in a single popup, and, for `spec.md` and `plan.md`, edit and save it without leaving the browser. Today the red pill opens only the question dialog, and no frontend code reads plan files (Research, answers 1 and 2).

## Non-Goals

1. Listing or reading arbitrary files in the plan folder. The read whitelist stays at six names (Decision 2).
1. Editing `blocked.md`, `contract.md`, `research.md` or `design.md`. Only `spec.md` and `plan.md` are editable (Decision 3).
1. Editing frontmatter. It is shown and locked (Decision 3).
1. A `Live::Command` kind for saves (Decision 5).
1. Changing the car-click `AgentDrawer` or the `UnblockWidget` dialog beyond opening the new drawer beside them.
1. Multiple popups, tabs or side-by-side diffing. There is one popup.
1. Real-time merge of an agent's concurrent edits. A stale save is refused, not merged (Decision 4).

## In scope

Each item has its check.

1. **Red pill opens the plan-level drawer** next to `UnblockWidget`, for any blocked plan, with or without a car. Check: a web test clicks the pill on a plan with no car and finds the drawer.
1. **Listing route** `GET /api/plans/:ordinal/files` returns the names, from the six-name whitelist, that exist in the plan folder. Check: request specs for a folder with some files, none, and an unknown ordinal.
1. **Dropdown** in the drawer shows exactly the listed names. Check: web test.
1. **Single preview popup** renders the selected file through the existing `marked` + `DOMPurify` path; selecting another file replaces the content; it closes on a close button and Esc. Check: web test selecting two files finds one popup.
1. **Edit button** switches the popup to a textarea, for `spec.md` and `plan.md` only. Check: web test that it is absent for `blocked.md`.
1. **Frontmatter locked**: shown read-only; the body of the file is the editable part, in both files (Decision 3). Check: web test that a changed frontmatter never reaches the request body; request spec that a PUT altering frontmatter is refused.
1. **Save route** `PUT /api/plans/:ordinal/files/:name` requires the CSRF token, accepts only `spec.md` and `plan.md`, and writes the file. Check: request specs for missing CSRF, a non-editable name, traversal, and success (the pattern at `spec/openlanes/web/app_spec.rb:414-463`).
1. **Hash guard**: the GET response carries a content hash; the PUT sends it back; a mismatch is refused with a conflict status and writes nothing. Check: request spec.
1. **Live-car guard**: Edit is disabled while the plan has a live car, and the server also refuses a PUT in that state. Check: web test and request spec.

## Out of scope

| Item | Reason |
| :--- | :----- |
| Folder-wide file listing | Decision 2 keeps the whitelist at six; widening it widens what the web can read. |
| Editing other plan files | Decision 3. `blocked.md` is appended through the `answer` command (`lib/openlanes/live/commands.rb:227-232`). |
| Saving through `POST /api/commands` | Decision 5. |
| Renaming plan folders or changing state from the editor | State moves belong to the harness; the folder name is the state. |
| Committing the edit | The harness owns commits; the web writes the file only. |

## Back end / front end

`backend-coder` and `frontend-coder` build these as a pair.

| Item | Half | Notes |
| :--- | :--- | :---- |
| Listing route | backend-coder | `lib/openlanes/web/app.rb`, beside the route at `:270-279` |
| Content hash on GET | backend-coder | Response header or JSON wrapper: see open question 2 |
| Save route, whitelist, CSRF, hash check, live-car refusal, frontmatter check | backend-coder | CSRF as at `app.rb:167-168` |
| Plan-level drawer opened by the red pill | frontend-coder | `web/src/shell/StatusBar.tsx:17`, `web/src/App.tsx:158` |
| Dropdown, single popup, close | frontend-coder | Radix dialog from `web/src/panels/dialogs.tsx:3` |
| Edit toggle, locked frontmatter, hash round-trip, conflict message | frontend-coder | Reuse `MarkdownEditor` (`web/src/panels/MarkdownEditor.tsx:1-3`) |
| Edit disabled with a live car | both | UI disables; server refuses |

The contract between them is the three routes and the hash. backend-coder defines it first.

## Open questions

Everything below was assumed or left open; none blocks the split.

1. **Live car, defined.** What counts as "a live car" on the server, for the refusal in Decision 4? Assumed: the same notion the UI uses to draw a car for that plan. Not verified.
1. **Hash transport.** Header (`ETag`) or JSON field? Assumed `ETag` on GET and `If-Match` on PUT. Not decided.
1. **Hash algorithm.** Assumed SHA-256 of the raw bytes.
1. **Frontmatter on save.** Does the client send the whole file or only the body? Assumed the whole file, with the server comparing frontmatter byte-for-byte against disk. Not decided.
1. **Frontmatter in `plan.md`.** Decision 3 says frontmatter is locked in both files. Whether `plan.md` has frontmatter today was not checked; the rule is a no-op if it has none.
1. **Drawer versus popup layout.** The drawer holds the dropdown; the popup holds the content (Proposal). Placement relative to `UnblockWidget` on narrow screens is not specified.
1. **Plan with no listed files.** Assumed the dropdown shows an empty state. Not specified.
1. **Web tests not run.** `web/node_modules` was absent, so `vitest` was never run on this checkout (Research, Not settled 1). The baseline of the web suite is unknown.
1. **Endpoint comment.** `app.rb:14-16` says the drawer and preview "may read" plan files; this plan adds a write path, so the comment must change with it.

## Risks to planning or execution

- **Agent and human write the same file.** An agent may rewrite `spec.md` or `plan.md` while the popup is open. The hash guard and the live-car refusal cover it, but a plan with no live car and a harness round about to start is a window the hash alone covers.
- **Uncommitted edits.** A web save leaves a dirty tree. The harness's HEAD-unmoved check is unaffected, but a following `git mv` rename of the folder carries the edit; this was not tested.
- **Unrun web suite.** Without an install of `web/node_modules`, frontend-coder's work has no known green baseline.
- **Frontmatter locking is client plus server.** If only the client enforces it, a crafted PUT edits `lane` or other fields that route agents (`plans/spec.rb`). The server check is required, not optional.
- **Scope drift into a general file editor.** The whitelist is the boundary; widening it is a separate plan.

## Conclusion

When this ships, a red pill on any blocked plan opens a drawer beside the question dialog, listing the plan's existing `spec.md`, `plan.md`, `contract.md`, `blocked.md`, `research.md` and `design.md`. Choosing one opens a single popup with the rendered markdown; choosing another replaces it. For `spec.md` and `plan.md` an Edit button switches to a textarea over the body, with frontmatter shown and locked. Save goes through a CSRF-protected `PUT`, is refused if the file changed since it was read or if the plan has a live car, and the six-name read whitelist is unchanged.
