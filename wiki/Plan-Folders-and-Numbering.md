<!-- generated-by: bin/wiki-gen -->

# Plan Folders and Numbering

_How a plan is named, numbered, where it lives, and which files it may hold._

**Up:** [Core Concepts](Core-Concepts.md)

______________________________________________________________________

## Plan folders

Every feature is one folder under `.plans/` (override with `PLANS_DIR`), named `NNN.MM━━<emoji>━━❯<slug>`:

```text
.plans/000.00━━✅━━❯dev-foundation
.plans/001.00━━🟡━━❯tenancy-households
.plans/001.01━━⏪━━❯schedule-k1-backfill     # shipped first, documented afterwards
.plans/002.00━━⚪━━❯tax-rule-dsl
```

- **`NNN.MM`** is set once and never changes. Branches (`<user>/NNN.MM-slug`), pull request titles (`[NNN.MM] ...`) and `pull-requests.md` all join on it. `MM` is `00` for a normal plan; `01` to `99` marks a retroactive plan (`openlanes create --after 001`).
- **The emoji** is the state. A transition renames the folder (through `git mv`), and a folder may only claim a state its files prove.
- **The name has no spaces**, so Tab completion works and nothing needs quoting. Each state emoji is a single code point that terminals draw two cells wide; in iTerm, turn on Unicode version 9+ widths so the columns line up.
- **`openlanes resync dirs`** renames any folder whose name its contents contradict. It also migrates folders named before this convention (`NNN.MM-<emoji> → <slug>`, or with the older emoji ⚪️ ⭐️ ⭕️ 🅱️ ☢️ 🕰️), which are still read, and moves finished, deferred and discarded plans into their subfolders. Preview it with `-n`.

A plan that is no longer active moves into a subfolder, with the date it moved inserted before the slug:

```text
.plans/archive/002.00━━✅━━❯[2026-10-13]━━dev-foundation       # ✅ and 😎
.plans/deferred/018.00━━💤━━❯[2026-10-13]━━deploy-observability # 💤
.plans/discarded/024.00━━❌━━❯[2026-10-13]━━external-resources   # ❌
.plans/abandoned/031.00━━👎━━❯[2026-10-14]━━stalled-import       # 👎
.plans/trashed/037.00━━🚮━━❯[2026-10-15]━━built-elsewhere         # 🚮
```

`.plans/` itself then lists only the work still open. Plan numbers count every folder, so a number is never reused. Reviving a plan moves it back into `.plans/` and drops the date.

While an agent works on a plan, its lock (process id, host and start time) sits in the runtime state directory, `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<hash>/locks/<ordinal>.lock`, beside the run's `openlanes-state.json`. Nothing runtime is written under `.plans/`, and the folder name never changes for a lock. `plans` and the control room show the plan with 🔑, adding the host for a lock taken on another machine, which is never cleared automatically. `resync dirs` removes a lock whose process is gone on this host. A legacy `locked-by.pid` or `.plans/openlanes-state.json` from an older release is still read, for one release. See `docs/decisions/decisions-on-runtime-state.md`.

Each run also appends a progress journal beside it, `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<hash>/journal/<run id>.ndjson`: one fsync'd, schema-versioned JSON line per engine event (run, assignment, agent pid, start time, session id, trace file and offset, transitions, extensions, questions), validated by `schemas/journal-event.schema.json` and mirrored to Redis on `openlanes:<repo>:<node>:journal`. The file, not Redis, is the record that survives a killed engine. Read the agents still in flight with `jq -c 'select(.kind | startswith("agent_"))' <file>`, or in Ruby with `OpenLanes::Engine::EventJournal::Replay.call(path)`. See `docs/decisions/decisions-on-progress-journal.md`.

See [`docs/decisions/decisions-on-plan-folder-naming.md`](Decisions-on-plan-folder-naming-archiving-and-locks.md) for the decisions behind it.

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

## The number

A plan's number is its identity. It is set once, when the folder is created,
and never changes: branch names, pull request titles and every
`pull-requests.md` join on it, and renumbering breaks all of them silently.

The shape is always `NNN.MM`:

```
.plans/000.00━━⚪━━❯initial-spec
.plans/001.00━━🟡━━❯dev-foundation
.plans/001.01━━⏪━━❯schedule-k1-backfill   <- shipped between 001 and 002,
.plans/002.00━━⭐━━❯tenancy-households        specified afterwards
```

A folder name holds no space, so it needs no quoting in a shell, and every
state emoji is a single unicode code point, so it measures the same in every terminal.
Older spellings (`NNN.MM-<emoji> → <slug>`, `NNN-<emoji>--<slug>`) and the
emoji they used are still read; `openlanes resync dirs` renames them.

- **`NNN` counts from `000`.** The first plan of a project is `000.00`; after
  that it is the highest major plus one, zero-padded to three digits.
- **`MM` is `00` for an ordinary plan** — one specified before it was built.
- **`MM` from `01` to `99` marks a retroactive plan**: work that shipped with no
  specification, documented after the fact. `openlanes create --after 001`
  takes the next free slot in the gap after 001.
- **A number is taken if any branch holds it.** "Highest" counts the primary
  checkout's `.plans` (archived plans included) and `.plans` on every local
  branch and every `origin/*` branch, read without a fetch, so a plan on an
  unmerged branch keeps its number.
- **Plans are created only in the primary checkout, on its default branch**
  (origin's HEAD, else `main`). In a linked worktree, or on any other branch,
  `openlanes create`, the page's new plan and `resync prs` adoption refuse and
  say why. The same holds for an opening `spec.md` and for `depends_on:`;
  every other file in a plan folder may be written from a worktree. Numbers are handed out under a lock in the shared git directory,
  so two creates at once cannot take the same one.

`001.01` is a **sibling of 001 that arrived later, not a part of 001**. The dot
reads as containment in almost every other numbering scheme, and here it does
not — which is worth saying wherever the scheme is described, because the
containment reading is the one a new reader brings.

Two digits, always. One would sort into the middle of the two-digit range —
`001.09` < `001.1` < `001.10` — so a single mixed-width folder silently
reorders the index. Two digits also retire the question of running out: 99
slots per gap, against a gap that closes the moment the next plan is created.

> [!NOTE]
> Padding every plan to `NNN.MM` is a deliberate choice, and it costs something.
> A bare `018` next to `018.01` would have told you at a glance which plan was
> specified in advance and which was written afterwards. With uniform padding
> that distinction is no longer readable from the number alone — it is carried
> by `MM > 0`, which you have to know to look for. What padding buys is
> alignment and one shape to parse everywhere.

**A retroactive `spec.md` must open with a dated line saying so**, naming the
pull requests it describes. It documents what exists; it does not pretend to
have decided anything in advance. Anchor by *when the work merged*, not by what
it is about — compare merge dates against folder creation dates
(`git log --diff-filter=A`). Anchoring by topic invites an argument nobody can
settle, and the number is a slot, not a claim about subject matter.

<sub>Lifted verbatim from the output of `openlanes docs`, generated from [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb) and [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb).</sub>

## Where a plan lives

The top of `.plans` holds only plans somebody may still work on.
A plan in one of these states moves into a subfolder, and its name gains the
date it got there:

| Folder              | States                            |
| ------------------- | --------------------------------- |
| `.plans/archive/`   | ✅ Approved & Merged, 😎 Deployed |
| `.plans/deferred/`  | 💤 Deferred                       |
| `.plans/abandoned/` | 👎 Abandoned                      |
| `.plans/discarded/` | ❌ Discarded                      |
| `.plans/trashed/`   | 🚮 Trashed                        |

```
.plans/archive/001.00━━✅━━❯[2026-09-01]━━dev-foundation
```

`openlanes resync dirs` does the moving, with `git mv`, and moves a plan back
to the top, undated, once its state is open again. The date is the folder's
last rename in git, else `state.json`'s `updated_at`, else today. Numbers span
the subfolders: a number in `archive/` is never handed out again.
`openlanes plans` shows the open plans; `--all` adds the rest.

While an agent works in a plan, its lock (pid, host, start time) sits in the
runtime state directory outside the repository (a legacy
`locked-by.pid` in the folder is still read), and `plans`
shows 🔑. The folder is never renamed while it is locked. `resync dirs` clears a
lock whose process is gone from this machine, and only reports one from another.

<sub>Lifted verbatim from the output of `openlanes docs`, generated from [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb) and [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb).</sub>

## Starting a feature that does not exist yet

`openlanes create <two to five words>` mints the folder at ⚪ New
and, for a genuinely new feature, scaffolds `spec.md` with a title and four
headings, verbatim:

- `## What we are trying to achieve`
- `## Why it matters`
- `## What already exists`
- `## What research needs to settle`

`anakin-briefster` — a half-agent: it runs only inside `create` and
holds no roster entry — then makes a best-effort attempt at each from what
the project already has on disk — its own docs, `.plans/BACKLOG.md` when
the project keeps one, anything already downloaded or already built that
bears on the topic — and opens the result for a human to finish.
`--no-draft` skips the attempt and leaves the headings bare; `--no-open`
leaves the file for you to open.

**Nothing else belongs in that first pass.** It writes no `## Goals`, no
`## Non-Goals`, no conclusions — deciding those before `researcher` and
`spec-writer` have looked is choosing the answer before the research runs.
Above all, it writes no heading beginning with the word "Research": that
heading is not decoration, it is the 🔎 Researched invariant, so writing
one — even empty — flips the folder's state out from under whoever reads it
next, and the research nobody did gets skipped rather than assigned.

This is only for work that does not exist yet. `create --after <plan> --prs <n,...>` is the other path — the work already shipped, so `spec-writer`
reconstructs the specification from the pull requests instead of guessing at
a feature that has no facts yet to guess from.

<sub>Lifted verbatim from the output of `openlanes docs`, generated from [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb) and [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb).</sub>

## Files allowed in a plan folder

| File               | Required by                                                                                               |
| :----------------- | :-------------------------------------------------------------------------------------------------------- |
| `spec.md`          | the specification; written first                                                                          |
| `plan.md`          | the execution plan; written from the spec                                                                 |
| `contract.md`      | the contract between the two halves of building                                                           |
| `openapi.yaml`     | the HTTP surface, when the plan has one                                                                   |
| `pull-requests.md` | 🟢 Ready for Review, 👀 In Review, 🧪 Verifying, 🏁 Completed, 🔴 Changes Requested, ✅ Approved & Merged |
| `deployed.md`      | 😎 Deployed                                                                                               |
| `rollback.md`      | 😱 Rolled Back                                                                                            |
| `rewrite.md`       | 🚫 Scrapped by Review                                                                                     |
| `blocked.md`       | ⭕ Technical Block, 🛑 Product Block, 💣 Bomb                                                             |
| `delayed.md`       | 💤 Deferred                                                                                               |

`contract.md` is the one file no state requires. `backend-coder` writes it
before it writes code, and `frontend-coder` builds from it a round later: the
interfaces the back end landed, their shapes and their errors, which files
each half owns, which units may run concurrently, and the one test that
proves the halves are joined rather than merely both present. No state
requires it because a plan with no back-end work never needs one. When
`plan.md` says the plan has an HTTP surface, `openapi.yaml` sits beside it,
linked from it, and `openlanes api docs` lists every one in the project.

The units themselves live in `plan.md`, under `## Backend` and
`## Frontend`. `frontend-coder` is started only when `## Frontend` holds a
unit heading.

Nothing else belongs there. A folder holding notes, diagrams or scratch files
is a folder nobody can audit at a glance.

<sub>Lifted verbatim from the output of `openlanes docs`, generated from [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb) and [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb).</sub>

## Pull requests carry the number

A pull request that implements a plan says so in its title, and is added to the table of the
pull requests file `pull-requests.md` added to the `.plans` directory. Here is an example with
just one pull request (but there may be several):

| Pull Request Number | Pull Request Name                                                                                                                |  Status |
| ------------------: | :------------------------------------------------------------------------------------------------------------------------------- | ------: |
|                 105 | \[[020.01](https://github.com/kigster/openlanes/blob/main/A) Durable Run Events\](https://github.com/kigster/openlanes/pull/105) | Open 🟡 |

`pull-requests.md` is generated from these titles, so the prefix is the join key
between a pull request and a plan, not decoration. Name branches
`<user>/NNN.MM-slug` and the number carries itself from branch creation through
to a merged, squashed pull request with nobody having to remember it.

`openlanes resync prs` fills in missing prefixes. It reads the branch name
first and falls back to the diff only when that touches exactly one plan folder.
**It refuses rather than guessing.** A wrong number does not announce itself: it
files the work under a plan that did not do it, and leaves the plan that did
looking untouched.

### `[dev]` when there is no plan

Not every pull request implements a feature. Dependency bumps, CI configuration,
hotfixes and developer tooling implement no plan, and forcing a number onto them
produces a number chosen to satisfy the rule. Those are titled:

```
[dev] Bump json from 2.21.1 to 2.21.2
```

`dev` means **"this deliberately belongs to no specification"**, and it
exists so that "no plan" is *asserted* rather than merely absent. A title with no
prefix is ambiguous between "no plan applies" and "nobody looked".

`resync prs` will propose it, but marks every such title as **assumed** and never
applies one without you seeing it. Emitting it silently on a failed lookup would
launder "I could not tell" into "there is definitely none", which is the same
lie as guessing a number, told in the other direction.

### What does not deserve a retroactive plan

Most unmatched pull requests. The test is whether **somebody would need to read
it** — a capability with behaviour, an interface, or invariants that are not
obvious from the code. "Fix a typo", "remove dead code" and "bump a dependency"
are `[dev]` and always were. Backfilling those produces an index that is
longer without being more informative, which makes the real plans harder to find.

<sub>Lifted verbatim from the output of `openlanes docs`, generated from [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb) and [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb).</sub>

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md)
- [`lib/openlanes/plans/status.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/status.rb)
- [`lib/openlanes/plans/state_machine.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/state_machine.rb)
- [`lib/openlanes/plans/ordinal.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/plans/ordinal.rb)
- [`lib/openlanes/presentation/documentation.rb`](https://github.com/kigster/openlanes/blob/main/lib/openlanes/presentation/documentation.rb)
