# Decisions on the web control room and review labels

Date: 2026-10-12. Taken in conversation with the author, without a separate grilling session. Items marked **(proposed)** were filled in by the agent and await the author's review.

Plans: `004.00` web control room, `005.00` review state labels.

## Web control room

### W1. The web is the only interactive view

`openlanes run` starts the web server and opens the browser. With no display (SSH, CI, no TTY), the URL is printed rather than opened, and `--no-open` forces that. There is no `--tui`: the terminal UI is removed (W22). OpenLanes is now a web-based software factory.

### W2. A `View` contract, not a virtual terminal

Every view implements `open`, `draw(board)`, `attach(console)` and `close`. After W22 there are two: the web view, and a headless view that writes one line per change to STDERR, for CI and for `--no-web`, so a run never needs a browser to finish. The views are decoupled at the level of data (`Engine::Board`), not terminal cells. Streaming a cell buffer to xterm.js would give a browser view for free, but no forms. With one viewer per run, `Board` keeps its per-viewer fields (`selected`, `dialog`, `help`), and `Console` remains the single gate through which every intent reaches the dispatcher.

### W3. Stack: Sinatra 4 + Puma, React + TypeScript + Vite, shadcn/ui, Motion

- Hanami 3 was considered and rejected. It expects to be the application, with its own root, container, settings and database scaffolding, and its guide covers no streaming, SSE or WebSockets. It also needs Node for assets, so it saves nothing over React.
- Sinatra's `stream` helper serves SSE on Puma. The server binds to `127.0.0.1` only, with a CSRF token on every write.
- The front end uses React with shadcn/ui (Tailwind) for widgets and Motion for animation. It is built with Vite, and the built `web/dist` ships inside the gem, so Node is needed only to build it and to run Cypress.

### W4. Animations follow the state machine

Each plan is a card that travels between agent lanes, then becomes a pull request node, then a review outcome (rejected, approved, approved with caveats, approved despite CI). The lanes and edges come from an API endpoint derived from `StateMachine` (`SPINE`, `FAMILIES`, `.edge?`) and `Agents::Registry`, never from a hand-written list in the front end.

The visual direction (a transit board: one horizontal line per plan through shared station columns, with agents hanging under the current station as cars that show live tokens in and out) is in `.plans/004.00-⚪️ → web-control-room/design/design.md`, with a working mockup beside it in `control-room.html`.

### W5. The frontmatter form is generated from a schema **(proposed)**

A JSON Schema for the `spec.md` frontmatter is published next to `schemas/plan-state.schema.json`. The server validates against it with `json_schemer`, and react-jsonschema-form renders the form from it. `Plans::Spec` and the schema must not diverge: a spec asserts they agree.

### W6. Redis holds the runtime, the filesystem holds the plan

Builds on plan `003.00` (inter-agent communication), whose D4 already made Redis a hard dependency, failing with a clear error when absent, and chose Streams over pub/sub.

- A plan's state remains its folder name and its `state.json`.
- **Redis is the live record of the run:** which agents are running, their PIDs, trace paths, inbox keys, session ids and why each was started. The engine and the API server read and write the run there, and nowhere else, while it is going.
- **The engine flushes that record to disk**, as `.plans/openlanes-state.json` through `Engine::StateFile`, for two reasons the author gave: a person can read it without `redis-cli`, and it is a backup if Redis loses its data. The flush is atomic (write a temporary file, then rename), happens at most every two seconds while something changed, and always on shutdown.
- **On start, the engine takes whichever copy is newer.** Both carry a sequence number that the engine increments on every change. Normally Redis wins; if Redis was flushed or restarted empty, the file is loaded back into it.
- This settles the conflict with plan 003's D7: the state file stays, with the PIDs and `last-known-state` in it, but it is a snapshot of Redis rather than a second source of truth. Only the engine writes it. (Settled by the author, 2026-10-12.)
- The board and the commands travel on Redis Streams (W13), not pub/sub. Pub/sub discards messages when nobody is subscribed, which is exactly the moment the other process is restarting.
- Redis is a seam with an in-memory fake, so the suite never reaches the network. There is no file-store fallback: plan 003's D4 rules it out.

### W7. Two processes: the engine and the API server

- **The engine** is the runner. It supervises the agents, spawning each with `Process.spawn(pgroup: true)` and sending its stream-json output straight to its trace file, so the agent does not depend on a pipe to its parent.
- **The API server** is a multi-threaded Puma process running Sinatra. It holds no run state of its own: everything it shows comes from Redis, and everything it is told to do goes back through Redis.
- `openlanes run` and `openlanes start` start both and open the browser. `openlanes run --no-web` starts only the engine, with the headless view (W2).
- **If the API server crashes,** nothing is lost. A restarted server reads the streams again, and an open tab reconnects by itself, because the port is fixed (default `11000`, `--port` to change it; it was 4747, which an installed agentilda still uses).
- **If the engine crashes,** agents keep running. The restarted engine reads the running set from Redis, checks each PID, tails each trace again, and carries on.
- Einhorn was considered and rejected. It keeps N copies of one long-lived program alive and stops its children when it exits, while these agents are all different, run once, and must outlive their parent.

### W8. Messages reach an agent at every tool call, through hooks

Plan `003.00` D6 already adds a `PostToolUse` hook (`openlanes mail poll`) passed through `--settings`, which injects waiting messages after each tool call. This plan reuses that channel for messages from the person and adds three things:

- **Message kinds:** `stop`, `shutdown`, `wrap_up`, `hold` ("more info is coming"), `message` and `answer`. They replace the bare words in `execution/control.rb`.
- **(proposed)** A `PreToolUse` hook beside 003's `PostToolUse` hook. On `stop` or `shutdown` it blocks the agent's next tool call and gives the reason. Injecting text after the fact cannot stop a tool from running; blocking it before it starts can.
- **`hold`** makes the agent run `openlanes mail wait --plan NNN`: one blocking tool call that checks every 10 s and returns when something new arrives. Waiting then costs one turn, not one per check.

Why not just ask the agent to check every 10 s: an agent only acts between turns, and a single `rspec` call can last minutes. The hooks fire at every turn boundary whether or not the agent remembers, and `Control::GRACE` with the harness's hard kill remain the final guarantee. Adapters without hooks (Codex, Pi) still get the instruction in their prompt.

### W9. Interrupt offers discard or keep

After an agent is interrupted, the page offers a choice:

- **Discard:** reset the plan's worktree and send the plan back one state through an `aasm` event. **Discard is plan-wide.** On the full lane luke and rey work in the same worktree at once, so resetting it would also wipe the partner's work in progress. Before the reset the engine stops every agent in that worktree, each with its grace period to leave a resume note, and the page says so before you confirm ("Discarding resets 001's worktree, which also stops rey-frontend"). There is no per-agent discard.
- **Keep:** resume from the agent's `last-known-state` record (plan `003.00` D7), with the person's feedback added to its mailbox.

The choice is made per interrupt and is never a global setting.

### W10. Talking to agents uses the existing channels first

A person's message to a running agent goes into the plan's mailbox (plan `003.00`) as a `human` entry, from which the hooks of W8 deliver it. The mailbox is also the record that outlives the run. Questions in `blocked.md` appear as answer forms, which run the unblocker on submit. Live stream-json input to `claude -p` (`--input-format stream-json`, `--resume`) is a later spike, not a prerequisite.

### W11. `-n` / `--dry-run` governs writes

PR #53 removes `--commit`: commands do their work when run and take `-n` / `--dry-run` for a preview (`docs/decisions/decisions-on-openlanes-skills-and-config.md`, decision 2). The web follows it: `openlanes run -n` and `openlanes start -n` show the page as a dry run with its write controls disabled, and without `-n` the page's buttons act.

### W13. The engine and the API server talk over Redis Streams, both ways

A direct bidirectional socket was considered. Streams won because they keep what the other side missed while it was down, which a socket does not, and because the agents' mailbox (plan `003.00` D4) is already on them, so there is one transport rather than two.

| Stream | Direction | Carries |
| --- | --- | --- |
| `board` | engine → API | one `Board` snapshot per tick, trimmed to the last few minutes |
| `commands` | API → engine | `kill`, `extend`, `interrupt`, `discard`, `keep`, `answer`, `message`, `create_plan`, `save_spec` |
| `replies` | engine → API | one reply per command id: accepted, refused (with the reason) or done |

- The engine reads `commands` through a consumer group, so a command sent while the engine was restarting is executed when it comes back, and it is acked only once it has been applied.
- **Acking after applying is at-least-once, not exactly-once:** an engine that applies a command and dies before `XACK` gets it again. So every command carries a stable id (a ULID minted by the API server, also the idempotency key the page retries with), and the engine records it in `openlanes:<repo>:<node>:<checkout>:done` (a set, entries expiring after a day) **in the same `MULTI` as the effect's own Redis writes**. Effects outside Redis are idempotent by construction: a message is appended to the mailbox keyed by the command id, so a second append is a no-op; `kill`, `stop` and `discard` check the agent's and the worktree's state first and do nothing to an agent that is already gone. A redelivered command found in `done` is acked and answered with its first reply.
- In the engine, the web view is a `View` like the TUI (W2): its `draw(board)` appends to `board`, and its command reader feeds the same `Console` gate the keyboard uses.
- Key names carry the repository, the machine and the checkout (W26, plan `003.00` D4), so no two machines or checkouts write each other's streams: `openlanes:<repo>:<node>:<checkout>:board`.

### W14. One logging library, one log directory

- Every component logs through SemanticLogger: the engine, the API server and each CLI command. Agents' raw traces stay in `Dir.tmpdir/openlanes-traces`, for the reason `Executor::TRACE_DIR` gives.
- By default, logs go to `.openlanes/log/engine.log` and `.openlanes/log/api.log` in the project root, one file per process so two processes never interleave lines in one file. One line per entry by default; `--log-format json` for machines.
- `.openlanes/` is created when missing and added to `.gitignore`.
- This departs from the global `log/` convention on purpose: openlanes runs inside other people's projects, and their own `log/` belongs to them.
- `-l`/`--log`, `-L`/`--log-level` and `--log-format` work as the global CLI rules describe, with the paths above as defaults.

### W15. Every test run gets its own tab, fed by a tee

- While an agent runs a test command, the page shows a tab labelled with the plan (`001.00 tests`), with a live count of examples run. If two agents test the same plan at once, the agent's name is added to the label.
- The tab shows passed, failed and pending counts, a bar whose segments are proportional to how examples ended (green passed, yellow pending, red failed), the failures with `file:line`, and the output as it arrives. It stays after the run ends, showing ✓ or the number of failures, until it is closed. When the same agent tests again, the run reuses its tab.
- **Why a tee:** stream-json reports a Bash call's output only once the call has finished, so the engine cannot watch a test run live by reading the transcript. Agents run tests through `openlanes test -- <command>`, which tees the output to `.openlanes/log/tests/<plan>-<agent>.log` and appends progress to a Redis stream. The prompt asks for this, and **(proposed)** a `PreToolUse` hook rewrites known test commands (`rspec`, `just test`, `npm test`, `pytest`, `cypress run`) to go through the wrapper. Whether hooks can rewrite a tool's input is one of plan 004's research questions.
- Pass and fail counts come from the runner's structured output where one exists (RSpec's JSON formatter, JUnit XML), not from parsing human-readable text.

### W16. Redis is found the way agent-lock finds it

Revised by the author on 2026-10-12, reversing the first version of this decision, which ruled `REDIS_URL` out. OpenLanes and `agent-lock` (W20) are installed and run together, so they find Redis the same way, in this order:

1. `--redis-url` on the command line.
2. `redis_url:` in `.openlanes.yml`, the project's settings file from PR #53.
3. `$REDIS_URL`, when it is set, as agent-lock reads it.
4. `redis://localhost:6379/0`.

That Redis may be shared by several machines working on the same repository, so how keys are named, and what one machine may read or write of another's, is W26. Every key starts with `openlanes:`, so a `SCAN` for `openlanes:*` finds everything openlanes ever wrote, and it can be cleared without touching an application's keys.

On startup, the engine and the API server each log the address they use, with any password masked, and the node name they write under.

### W17. A copilot to talk to about the run: c3po-operator

The dispatcher is code, not an agent, so there is nothing there to chat with. The copilot is a new agent, **c3po-operator**, whose only job is to talk to the person about the run.

- **Where:** a pop-up in the bottom right of the page. Closing it shrinks it to a small tab fixed to the right edge of the screen, which shows a dot when the copilot has said something you have not seen.
- **What it reads:** the board, the logs, each plan's `state.json`, the mailboxes and the agents' transcripts. It runs only the `openlanes` commands that read state.
- **What it does:** it answers questions ("why has 002 not moved?"), drafts answers to blocked agents, and summarises. Actions go through the same command gate as the page's buttons (W13), so it can never do anything the page cannot. Reversible ones (message, hold, extend) can be sent directly. **Stop, discard and stop run** appear in the chat as a card that the person confirms.
- **What it never does:** edit code or plan documents. That is the other agents' job, and two writers on one file is the race plan `003.00` D8 is about.
- **How it runs:** one `claude -p` session, resumed on each message (`--resume`), on a cheap model by default. Its tokens are shown in its header, as a car's are on the board.
- **When:** after W8 to W10, whose channels it reuses.

### W18. The header names the project, not the directory

The page's title is the project being worked on; "openlanes" shrinks to a small wordmark beside it. Below the title: the project's one-line description and its path, abbreviated with `~`.

The title comes from the first of these that exists in the project root **(proposed order)**:

1. `project:` in `.openlanes.yml` (PR #53), which already names the project for `INDEX.md`, plus a `description:` key added beside it.
2. A manifest: `package.json` (`displayName` or `name`, plus `description`), `Cargo.toml` (`[package] name` and `description`), `*.gemspec` (`name` and `summary`), `pyproject.toml` (`[project] name` and `description`), `go.mod` (the module path's last segment).
3. The first `# ` heading of `README.md`.
4. The directory name.

A slug from a manifest is passed through `Plans::Feature.titleize`, so `openlanes` becomes "OpenLanes" with the same acronym rules plan folders use. The path's tooltip names the file the title came from. When the project is openlanes itself, the title is left out, because the logo beside it already says it. Here, `openlanes.gemspec` gives "OpenLanes" and "Agentic specification-driven development: spec, plan, build, review".

### W19. `openlanes start`: from an idea to accepted plans

`openlanes run` drives plans that already exist. `openlanes start` is for when there are none yet, or when the person has a new idea: it boots the engine and the API server exactly as `run` does, opens the page at `#start`, and starts no agents until plans are confirmed. During a run, **New idea** in the top bar opens the same dialog.

1. **The idea.** A modal asks "What is the product or feature you'd like to build?" over a Markdown editor with syntax highlighting. Above the editor, lane, front end and depth controls set the defaults every plan from this idea starts with. The draft is kept as it is typed, so closing the tab loses nothing.
2. **The split.** A short idea (under about 120 words and at most one `##` section) becomes one plan directly. A longer one goes to **palpatine-planner**, which returns the plans as JSON, validated against a schema before the page shows them **(the threshold is proposed)**. This is a new job for palpatine, which today turns one signed-off spec into work units; the agent definition gains it as a second mode.
3. **The confirmation.** The dialog becomes "Here is your idea broken up into plans. Confirm?" and lists each plan as `[001 Set up a scaffold for the application] [Accept] [Modify]`. Sub-plans are indented under their parent, with their own **Accept** and **Modify**, because each becomes a plan of its own. **Accept all** is offered while any are left.
4. **Modify** opens the same editor on the body of that plan's opening `spec.md`, with its frontmatter as controls above it (see below), and the dialog's title becomes "Editing 001: Set up a scaffold for the application". **Revert ↶** discards the edit and goes back to the list; **Save ✔** keeps it, and saving also accepts the plan. Esc steps back one view and never throws work away.
5. **Create N plans** is enabled once every plan is accepted. It creates each folder through `Lifecycle.create`, in order, as ⚪️ New. Clicking it writes the folders; under `-n` it is disabled (W11).

**Frontmatter is never typed.** The editor holds only the body of `spec.md`. Its frontmatter is a form above the editor, generated from the schema in W5: lane, front end and depth as segmented controls, and under "More settings" the per-phase adapter, model and effort plus the four lists (`implementation_suggestions`, `implementation_requirements`, `task-completed-when`, `how-to-verify`, one item per line). When the plan is created, the form is written as YAML at the top of `spec.md`, holding only the values that differ from the defaults, so `Plans::Spec` reads it unchanged. Settled by the author on 2026-10-12.

A sub-plan is an ordinary plan with its own number. Its frontmatter names its parent (`part_of: "002"`), and it depends on the plans before it in the list **(the field name is proposed)**.

**Amended 2026-10-13: `openlanes start` stays up.** The command now exists, as the factory running as a service: `run` with the control room required, idling instead of ending at a fixed point. A blocked plan (palpatine-planner's questions included) waits in Needs You, the answer from the page is drained, and the plan goes back to its agent, all without a restart. It opens the page at `#start` only when no plan is unfinished; otherwise on the board, and it starts agents on existing plans at once rather than waiting for a confirmation. It ends on its own once every plan in scope is ✅, 😎 or ❌, and on Ctrl-C or SIGTERM. Without Redis it refuses (exit 69); it has no `-n` and no `--no-web`. Stop All stops the agents and keeps the engine up. The idea dialog's split and confirmation (steps 2 to 4) are unchanged and still to come.

### W20. `openlanes init` ends in `openlanes start`

`openlanes init` arrives in PR #53, where it writes `.openlanes.yml` and creates `.plans/`. This decision extends it: it also checks that Redis answers, and installs the `agent-lock` gem when `alock` is missing or older than the version openlanes needs, so the two always arrive together (settled by the author, 2026-10-12). It then runs `openlanes start`, so a new project goes straight from setup to the idea dialog. `--no-start` stops after setup, for scripts and CI.

### W21. Plan numbers are plain `NNN`

Settled by the author on 2026-10-12. The `.MM` suffix goes: plans are `001`, `002`, and so on. Today `.MM` marks a retroactive sibling (`002.01` is work that shipped between 002 and 003 and was documented afterwards); a retroactive plan now takes the next free number like any other, and its 🕰️ status already says it is retroactive. Sub-plans from W19 were never going to use `.MM`, because `Ordinal` defines it as a sibling and not as containment.

Existing trees keep working: `Ordinal.parse` still reads `NNN.MM` folder names, branch names and PR titles, and everything new is written as `NNN`. The change reaches about 17 files under `lib/`, so it is its own plan rather than part of 004.

### W22. The terminal UI is removed

Settled by the author on 2026-10-12, after seeing the web mockup. The ratatui screen, the keyboard handling only it uses, and the `ratatui` dependency go, and with it the Rust toolchain that building the gem needed. The `View` seam stays (W2), with the web view and a headless view behind it. This ships in its own pull request, ahead of the web view, since nothing in the web work depends on the TUI.

### W23. Research is opt-in, and every choice explains itself

Settled by the author on 2026-10-12.

- **A spec says whether leah-researcher runs**, with `research: true` in its frontmatter. The default is **no**: research is not useful for every feature, and it is the slowest phase. The form shows it as "Research? Yes | No" beside the lane.
- It only means something on the full lane; the plan and quick lanes skip research already, so there the control is disabled and says so.
- **The mechanism exists already.** leah-researcher gets `toggle: research`, as rey-frontend has `toggle: frontend`, and `Agents::Routing` reads the switch. With research off nothing handles ⚪️ New, so `Lifecycle::Lanes` moves a full-lane plan from ⚪️ to the state after research, the same way it moves plan-lane plans today, writing whatever that state's invariant requires. This changes what a full-lane plan does when its spec says nothing: today it is always researched.
- `.openlanes.yml` may set a project default (`research: true`), with the same precedence as `frontend:` in PR #53: the spec, then `.openlanes.yml`, then no.
- **Under each control, two lines say what the current choice means**, and they change with it. The copy:

| Control | Choice | Says |
| --- | --- | --- |
| Lane | Full | Complex feature engaging all agents; costs the most in tokens. |
| | Plan | A spec you already trust: skip research and go straight to the plan. |
| | Quick | A small task for a junior engineer, not a feature. Cheapest and fastest. |
| Research? | Yes | Yes adds a research section to the spec. It takes more time, but provides additional context when needed. |
| | No | No sends the spec straight to the copywriter, with no additional research. For when you know what you are doing. |
| Front end | Plan decides | Plans UI work automatically, when it improves the final result. |
| | Yes | A full-stack feature with a front-end component. |
| | No | A back-end-only feature or task. |
| Depth | Default | Maps to the model's effort; the default comes from the plan. |
| | Fast | Low effort. |
| | Medium | High effort. |
| | Deep | xHigh effort. |

### W24. Each agent's model can be changed from its car

Settled by the author on 2026-10-12.

- **Every car shows its model as a small dropdown.** It lists the models the agent's adapter offers, most capable first, with the current one selected. For now the only adapter is Claude, so the list is about seven Claude models, from Fable at the top to Haiku at the bottom; the list comes from the adapter, not from the front end, so codex and pi bring their own when they arrive.
- **A change applies from the agent's next invocation.** A running `claude -p` cannot switch model, so the choice is queued: the car marks it, the drawer says "Sonnet 5.5, Fable 5.1 from its next round", and the agent's transcript records it. It is a `set_model` command through the API (W9), and it lands in the plan's `phases:` override for that agent's phase, so a restart keeps it.
- Choosing the current model again cancels a queued change. A blocked car hides the dropdown, since the agent is not going to run until someone answers it.

### W25. Depth maps to effort through a table `.openlanes.yml` can replace

Settled by the author on 2026-10-12.

The mapping changes to Fast → `low`, Medium → `high`, Deep → `xhigh`. Today `Plans::Spec::EFFORT_FOR_DEPTH` says medium → `medium` and deep → `high`. Default leaves the effort to the agent's own frontmatter and the plan.

Later, `.openlanes.yml` will accept a `depth:` table that replaces those three values for one project (`depth: { medium: medium }`). That is not built yet; the form's help text reads from the same table, so it will show the project's mapping when it is.

### W26. Machines sharing one Redis see each other, and never work the same plan

Settled by the author on 2026-10-12. This replaces the 4-hex-digit hostname prefix the revised W16 briefly had.

Several machines, say three, may run openlanes on the same repository against one shared `$REDIS_URL`. Each sees what the others are working on, read-only, and **no two machines ever work on the same plan**. That one rule is the whole lock.

**Names.**

- **The node** is this machine and user: the SHA-256 of `username@hostname` (`Etc.getlogin`, falling back to `$USER`, and `Socket.gethostname`), cut to its first 96 bits, 24 hex digits. Everything this machine writes lives under it: "our" state.
- **The repository** is what the machines have in common: its GitHub URL, normalised to `github.com/<owner>/<repo>` (from `git remote get-url origin`, with `git@github.com:` and `https://` spellings, a trailing `.git` and letter case all folded together). It goes into keys as is, readable rather than hashed, so `redis-cli` shows whose repository a key belongs to. There is no override (W29). A tree with no GitHub remote uses the checkout's path instead, which means it shares with nobody. *Changed on 2026-10-13; this was the root commit's digest.*
- **The checkout** stays below the node (plan `003.00` D4), so two checkouts on one machine still keep apart.

**Keys.**

| Key | Holds | Written by |
| --- | --- | --- |
| `openlanes:<repo>:nodes` | a set of the node ids that have run on this repository | each node adds itself |
| `openlanes:<repo>:<node>:meta` | a hash: `username`, `hostname`, `ip`, the checkout path, openlanes's version, `started_at`, `seen_at`. It expires after 60 s and the engine refreshes it every 15 s, so a machine that dies drops out within a minute | that node only |
| `openlanes:<repo>:<node>:<checkout>:…` | the board, streams and mail of W13 and plan `003.00` D4 | that node only |
| `openlanes:<repo>:claim:<plan>` | the id of the node working on the plan | `SET NX`, see below |

`ip` is the local address of this node's connection to Redis, which is the interface the other machines share with it; when that cannot be read, the first non-loopback address (`Socket.ip_address_list`). It is shown, never used to identify the node: addresses change with DHCP and VPNs, while `username@hostname` does not. `username` and `hostname` are stored in plain text beside the digest, because the digest exists to make keys short and uniform, not to hide anyone: the page shows `username@hostname` in its header for this machine, and in the other machines' tab for each of the rest.

**Read-only.** The store a node writes through is scoped to its own prefix and to `claim:` keys. Other nodes' keys are read and never written. The API server serves them for display and accepts no command naming another node; a kill, message or model change for a plan on another machine is refused with 403.

**The plan lock.**

- `<plan>` is the plan's number and slug (`008-ledger-export`), not the number alone, so two machines that each minted an `008` do not block each other by accident.
- Before the dispatcher hands a plan to an agent, the node claims it: `SET openlanes:<repo>:claim:<plan> <node> NX EX 60`. If the key exists and names another node, the plan is stepped around, as a blocked plan is, and the round reports it as "on `user@host`".
- The node keeps the claim for as long as its run includes the plan, renewing the expiry with each 15-second heartbeat, between rounds too, so another machine cannot pick the plan up between two of this one's rounds. It releases the claim when the plan reaches a terminal state or the run ends, with a compare-and-delete script so it can only ever delete its own claim. A crashed machine's claims expire within 60 seconds.
- This is advisory between well-behaved openlanes processes, like agent-lock. It is not a guard against someone editing a plan folder by hand.

**On the page.**

- The header shows this machine as `username@hostname` under the project's path, with the node digest, its IP and the masked Redis address on hover.
- **Each other machine gets a tab of its own**, labelled `username@hostname` with a 🖥️, at the far right of the tab bar. It draws that machine's plans as the board draws ours (stations, lines, agents, tokens, elapsed time) with a line naming its checkout path and when it was last seen. Nothing on it is a control: no drawer, no model dropdown, no answer box.
- **All machines**, a toggle in the header, merges everything onto the Board tab: our plans first, as usual, then each other machine's under a heading naming it, read-only and at 85% opacity, so they stay readable while ours stay first. Each machine's section, ours included, opens with a band in the highlight colour, the logo's orange `#D35728`, RGB (211, 87, 40): `username@hostname` in larger type, then its IP, plan count, and for other machines "read only" and when it was last seen. The choice is remembered per browser. Off, the Board shows only this machine's plans.

**Known gap.** Plan folders move by renames in each machine's own checkout, so a plan's state reaches the other machines' trees only through git, when the branch is pushed and pulled. Redis shows the live state; the folders catch up later. Making the claim the source of truth for which state a plan is in is not part of this decision.

### W27. The agent drawer switches one agent's model now, and compacts it

Settled by the author on 2026-10-13.

- The drawer an agent opens into carries a model dropdown at the top. Choosing a model switches **that agent only**, at once rather than from its next round, and runs `/compact` on its session straight after.
- The harness does it as a `switch_model` command (W9): stop the agent at its next safe point (between tool calls, never mid-edit), resume the same session with `--resume <session-id> --model <id>`, and send `/compact` as the first input. A blocked agent is already at a safe point, which is the case this exists for: a stuck agent gets a stronger model and a smaller context in one move.
- It also records the model in the plan's `phases:` override, as W24's queued change does, so a restart keeps it. The car's dropdown is unchanged: it still queues for the next round.
- Research must confirm that a resumed `claude -p` session accepts `--model` and a leading `/compact`; codex and pi need their own equivalent through their adapters.

### W28. Every agent autocompacts at 40% of its context

Settled by the author on 2026-10-13.

- Every agent the harness starts compacts automatically once its context reaches 40% of the model's window, instead of the CLI's default near the limit. Agents work in long sessions over large files, and the quality of a session drops well before the window is full.
- For Claude the executor sets the threshold in the child's environment (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=40`; research confirms the name and that headless runs honour it). Other adapters map it to their own setting, or report that they cannot.
- `.openlanes.yml` may override it later (`autocompact: 50`); 40 is the default.
- The drawer shows the agent's context as a bar with the 40% mark, and each autocompaction is written to the transcript and the log.

### W29. Joining is sharing `$REDIS_URL`; everyone is trusted

Settled by the author on 2026-10-13.

- **openlanes is a distributed software factory, and the only way in is the Redis address.** A machine that connects to the shared `$REDIS_URL` from a clone of the same GitHub repository is part of the factory: it appears on everyone's board and takes part in the plan claims of W26. There is no invitation, account, allow-list or handshake, and none is planned.
- **Nobody can be kept out or removed.** There is no kick, ban or eviction; anyone with the address and the repository is in, and leaves by stopping.
- **This is not a policy enforcement system.** It assumes everyone around is friendly. Read-only views and plan claims are agreements between well-behaved openlanes processes, not security: a hostile client with the Redis address can write anything. Access control is whoever controls the Redis password and network.
- The repository key is the GitHub URL itself (W26), so the repository you cloned decides which factory you join, and nothing else does.
- **Stop All Local** (formerly Stop run) says what it can do: stop this machine's agents. The page's **?** pill explains all of the above; its copy is the author's to write (`design.md`, "Help dialog").

### W30. Yes/no questions are answered with buttons, and the agent says which questions they are

Settled by the author on 2026-10-13.

- A question an agent asks may carry `answers: [yes, no]` in its mailbox message (plan `003.00`). The page then offers **Yes** and **No** buttons in place of the text box, in the drawer, Needs you and the unblock widget, with **Answer in words** to fall back to the text box.
- The agent declares it; the page never guesses from the wording. "Should I start it, or skip the integration specs?" starts with "Should I" and is not a yes/no question, and a guess that offers Yes to it would send an answer that means nothing.
- The answer reaches the agent as the plain word (`yes` or `no`), so an agent can branch on it without parsing prose. The agents' prompts gain one line: ask yes/no questions as yes/no, and mark them.

### W12. Order of work

0. Plan `003.00` lands first, or at least its phases B and C: the JSON mailbox, Redis Streams, the hook and `last-known-state`.
1. Remove the TUI (W22), leaving the `View` contract with a headless view behind it.
2. SemanticLogger and `.openlanes/log/` (W14), then the Redis run registry, the engine/API split and its streams, and detached agents (W6, W7, W13).
3. The web board: read-only, then kill, extend and interrupt (W9).
4. Message kinds, the `PreToolUse` hook and `mail wait` (W8), human messages and `blocked.md` answers (W10).
5. Animations (W4).
6. The new-feature form and the spec editor (W5, W23, W25), then `openlanes start` and the idea dialog (W19), then `openlanes init` (W20).
7. The model dropdown on each car (W24), once commands reach the engine (W9).
8. Machines sharing one Redis (W26): the node and repository names land with the Redis store in step 2, since they are its key layout; the claim lands with the dispatcher's next change; the Other machines tab comes after the read-only board.
9. Autocompact at 40% (W28) with the executor's next change, since it is one environment variable; the drawer's model switch (W27) after W24, once a session can be resumed on another model.

## Review labels

### L1. Six labels, one at a time

The author asked for "three labels" and then listed five. With `approved-despite-ci`, that makes six:

| Label | Colour (hex) |
| --- | --- |
| `ready-for-review` | `b7ebc6` light green |
| `review-in-progress` | `fff3b0` light yellow |
| `approved` | `0b6e2e` deep green |
| `approved-with-caveats` | `e4c200` yellow |
| `rejected` | `d73a4a` red |
| `approved-despite-ci` | `e8590c` orange **(proposed: no colour was given)** |

A PR carries exactly one of these at a time; moving to a new state removes the previous state's label. Any label missing from the repo is created before first use, and a label that already exists is left alone, colour included.

### L2. The harness applies `ready-for-review` **(proposed)**

The author wanted hansolo-reviewer to do all the labelling. But `ready-for-review` only matters while hansolo is not running, so hansolo cannot be the one to apply it. `Vcs::Publisher` applies it when it opens the PR. hansolo applies every label after that, starting with `review-in-progress` the moment it picks the PR up.

### L3. Verdicts go through an `openlanes review` command, not raw `gh` **(proposed)**

Labels are set with `gh pr edit`, which is in `FORBIDDEN_COMMANDS`. Granting it would also let hansolo rewrite PR titles and bodies, because Bash permission specifiers match by prefix. So hansolo calls `openlanes review start|approve|caveats|reject --pr N`, which creates the labels if missing, swaps them, posts the review and checks CI. `gh pr review` is removed from hansolo's `may:`, so the CI rule (L4) cannot be bypassed by calling `gh` directly.

### L4. No approval over red CI without a label and an explanation

`openlanes review approve` refuses while any check is failing, unless it is given `--despite-ci "<reason>"`. In that case it posts the reason as a top-level PR comment, then applies `approved-despite-ci`. The rule is enforced in code; the prompt explains it but does not have to be trusted.

### L5. Pending CI waits **(proposed)**

If checks are still running, hansolo does not approve. It leaves the PR on `review-in-progress` and exits with a **parked** result rather than a verdict.

- Parking is a harness state, not a reviewer round: the dispatcher records the plan as parked on CI in the run state (W6) and does **not** count the attempt against hansolo's rounds, which default to one.
- A parked plan is stepped around, as a blocked one is, while the engine polls `gh pr checks` with the run's heartbeat. When the checks settle, pass or fail, it unparks the plan and hansolo runs again with its round intact.
- A plan parked longer than an hour is reported on the board as "waiting on CI for 1 h", so a stuck check is visible rather than silent.

### L6. Separate from the emoji-review labels

`ready for merge` and `do not merge` belong to the human emoji-review convention and are left untouched. The six labels in L1 record the agent review's state; those two record a reviewer's verdict.

### L7. Ships independently

Plan `005.00` does not depend on the web control room. The control room's animations (W4) read these labels once both exist.
