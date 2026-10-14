# Using openlanes

The reference behind the [README](../README.md). For the state machine, numbering and plan files, see [`WORKFLOW.md`](WORKFLOW.md), which `openlanes docs` generates from the code. Every command also has `--help`.

## Project settings

### Finding the project root

Every command that reads or writes plans first finds the project root and works from there, so it does not matter which subdirectory you type it in. The search, nearest first:

1. a directory holding `.openlanes.yml` or `.plans/`;
1. failing that, a directory holding `.git`.

Your home directory counts only if it holds `.openlanes.yml`, so a dotfiles repository there cannot capture every project under it. When the root is not where you are, one line on STDERR says so (`-q` silences it); when there is none, the command exits 66. `-D` and `PLANS_DIR` resolve against the root. `version`, `states`, `docs`, `agents`, `describe`, `completion`, `eval` and `skills` need no project and skip the search.

### `openlanes init`

Writes `.openlanes.yml` at the nearest `.git` (else the current directory) and creates `.plans/`. It takes `--project`, `--lane`, `--[no-]frontend` and `--jobs`, asks on a terminal for whatever no flag gave, and confirms before writing. `-y` asks nothing, `-n` prints the file instead, and an existing file is kept unless `--overwrite`.

### `.openlanes.yml`

```yaml
project: Demo App         # heading for INDEX.md; default: the root's directory name
lane: full                # default lane for `openlanes create`: full | plan | quick
frontend: false           # a spec's `frontend:` when spec.md says nothing; omit to let each plan decide
jobs: 4                   # how many plans `openlanes run` works on at once
redis_url: redis://localhost:6379/0   # the Redis the live run shares
commands:                 # option defaults for any command, by the name you type it as
  run:
    timeout: 1800
  resync prs:
    adopt: false
```

- Precedence, highest first: a typed flag, the plan's `spec.md` frontmatter, `.openlanes.yml`, the built-in default.
- `jobs`, `lane` and `project` are the same settings as `commands.run.jobs`, `commands.create.lane` and `commands.index.project`. Set either spelling, not both.
- An unknown key, a bad value, or an option the command does not take is an error naming the file (exit 65). A setting silently ignored is a timeout that stops applying with no signal.
- `dry_run` cannot be a default.

## Writing a spec

### `spec.md` frontmatter

Every key is optional:

```yaml
---
lane: quick          # full (default) | plan | quick
frontend: false      # true forces rey-frontend; false keeps it out
depth: fast          # fast | medium | deep: the default effort for every phase
phases:              # per-phase overrides: research, specification, planning,
  build:             # build, frontend, review, unblock
    adapter: codex   # claude (default) | codex | pi
    model: gpt-5-codex
    effort: medium   # low | medium | high | xhigh | max
  review: { model: opus }
implementation_suggestions:   # text or a list: language, libraries, an approach
  - Ruby, with dry-cli for the command line
implementation_requirements:  # text or a list: binding, exactly as written
  - The database is PG-strict
task-completed-when:          # what must be true for the task to be finished
  - "`openlanes create` opens an editor and writes no draft"
how-to-verify:                # the commands or checks that show it
  - bundle exec rspec spec/openlanes/cli/create_spec.rb
---
```

- **`implementation_suggestions`** is advice. Every agent is shown it as "suggestions from the spec's author", prefers it when it fits, and may take a better route as long as it writes why in the document it owns.
- **`implementation_requirements`** is binding. An agent that cannot meet one signs `Blocked` instead of substituting its own, and `hansolo-reviewer` rejects work that does not meet them. Agents start without your personal skills (`run --user-config` restores them), so write the rule itself, not the name of a skill that holds it.
- **`task-completed-when`** and **`how-to-verify`** are copied into `plan.md` under `## Task completed when` and `## How to verify`. After a planner signs, the harness appends whichever section is missing and never touches one that is there. No agent signs `Completed` until the first holds, every agent runs each check in the second, and the reviewer rejects work that fails one.

Model and effort precedence, highest first: `run --model` (model only), `phases.<phase>`, `depth` (effort only), the agent's own frontmatter. The adapter has the last word: a Claude agent asked for anything above Opus runs on Opus.

### Lanes

| Lane    | Route                                            | For                                                                                       |
| :------ | :----------------------------------------------- | :---------------------------------------------------------------------------------------- |
| `full`  | leah → yoda → palpatine → luke (+ rey) → hansolo | features you want researched and specified                                                |
| `plan`  | palpatine → luke (+ rey) → hansolo               | a spec you already trust: the harness writes a blank `plan.md` and moves the plan to 📋   |
| `quick` | r2d2-mechanic → hansolo                          | a short mechanical task: the harness writes a one-unit `plan.md` and moves the plan to ⭐️ |

`openlanes create --lane quick split big migration` writes the frontmatter for you.

## Running the agents

### `openlanes start`: the factory with its control room

```bash
openlanes start                                # engine plus control room on http://127.0.0.1:11000
openlanes start --no-open --port 4848          # print the URL instead of opening it, on another port
openlanes start --rescan 10                    # look for new or hand-edited plans every 10 s while idle
openlanes start --plan 005                     # only plan 005, until stopped
```

`openlanes start` is `openlanes run` that does not stop at a fixed point. When a plan blocks, it idles, puts the questions in **Needs You** on the page, takes your answer from there, folds it in and hands the plan back to its agent, with no restart. Plans created on the page, by `openlanes create` in another terminal, or edited by hand are picked up on the next rescan (every 5 s by default, or at once after anything you do on the page).

Every decision goes through the page: answers, hold, wrap up and stop on an agent, model changes, new plans. **Stop All Local** stops this machine's agents, then its engine and the page. The page also hosts `c3po-operator`, a read-only copilot that talks about the run, drafts answers to blocked agents and proposes stops for you to confirm.

It never ends on its own, not even once every plan is finished, since the page can create the next one. Stop All Local, Ctrl-C or `SIGTERM` ends it. It takes `run`'s flags except `-n`, `--no-web` and `--until-settled`, and needs Redis: without it, it refuses (exit 69) rather than going headless.

`openlanes web` serves the page on its own; `openlanes web --demo` replays a sample run with no agents.

### `openlanes run`: headless, or to a fixed point

`openlanes run` serves the control room too when Redis answers, and then stays up like `start`. Pass `--until-settled` (CI, scripts, agents) to end at the first fixed point anyway, or `--no-web` to run headless, which always ends there.

```bash
openlanes run -n                               # dry run: who would take what
openlanes run                                  # the whole tree, one worktree per plan, in parallel
openlanes run -j 4                             # at most four agents at once
openlanes run --plan 003,005.01                # only these plans
openlanes run --agent yoda-writer --prompt "Rework the risks section first"
openlanes run --skip hansolo-reviewer          # everyone but the reviewer; its plans wait
openlanes run --model opus                     # one model for every agent
openlanes run --user-config                    # agents load your personal plugins and skills too
openlanes run --timeout 600                    # at most ten minutes per agent
openlanes run --rounds 1                       # at most one round per agent per plan
openlanes run --max-tokens 200000              # token budget per agent invocation
openlanes run --isolation shared               # one checkout, one agent at a time, no git needed
```

- If you just created several plans, run them with a single `--plan` list. Separate bare `run` calls each loop over the whole tree, so their worktrees would overlap.
- The loop stops when a full round changes no plan's state, or when every plan in scope is done, blocked, or out of rounds.
- Agents start without your personal plugins, skills, hooks and MCP servers, which saves context and start-up time on every turn. `--user-config` lets them back in.

![A terminal view of a run: luke-backend and rey-frontend building plan 001.00 together while leah-researcher reads the spec of plan 002.00, each with its model, tokens, elapsed time and time left](img/openlanes-running.avif)

![Two plans in different phases in a terminal view: luke-backend self-checking plan 000.00 while palpatine-planner, luke-backend and rey-frontend work on plan 001.00](img/openlanes-two-plan-work.png)

### Limits

| Limit  | Declared by the agent         | Flag           | Default         |
| :----- | :---------------------------- | :------------- | :-------------- |
| Clock  | `timeout:` in its frontmatter | `--timeout`    | 900 seconds     |
| Rounds | `rounds:` (at most 5)         | `--rounds`     | the agent's own |
| Tokens | none                          | `--max-tokens` | unmetered       |

Flags can only tighten what an agent declares, never loosen it. Each agent is told its clock and its token budget in its prompt. As its time runs out, the agent is warned at 10, 5 and 1 minute left, then asked to stop; if it is still running 60 seconds after that, it is killed. The token meter aborts an agent once it goes over its budget.

### Following a run, and stopping it

- `run` and `start` print one line per event on STDERR (an agent started or finished, a plan changed state, a command came from the page, the reason the engine idles). `--quiet` silences them. Progress also goes to a log file (`--log`).
- `unblock` and `create` show each agent as a spinner line on a terminal.
- Ctrl-C once asks each running agent to leave a `RESUME:` note in its plan's mailbox and sign `Interrupted`. Every agent reads its mail before it starts, so a later run picks up where this one stopped. A second Ctrl-C aborts immediately.

### Unblocking a plan

The loop never assigns a blocked plan (⭕️ or 🅱️). Write your answers into the plan's `blocked.md` under `## Answers`, dated and attributed, then:

```bash
openlanes unblock 003 -n         # what is 003 still waiting on?
openlanes unblock 003            # fold the answered questions into spec.md and plan.md
```

Partial answers are fine. The plan stays blocked until the last question is answered. Under `openlanes start`, answer in **Needs You** on the page instead.

## How agents hand off

An agent never renames its plan folder. It signs the plan's `state.json`, and the harness moves the folder based on the signature:

```bash
openlanes state sign --plan 003 --agent leah-researcher --round 1 --status Started
openlanes state sign --plan 003 --agent leah-researcher --round 1 --status Completed --next yoda-writer
openlanes state show --plan 003 | jq '.stages[] | {agent, round, status, model, seconds}'
```

`state.json` lives in every plan folder and is committed with it. It holds the harness's record of each round (adapter, model, effort, tokens, seconds), the agents' signatures, and the messages between them (`openlanes mail send`, `openlanes mail read`). Its shape is [`schemas/plan-state.schema.json`](../schemas/plan-state.schema.json). Writes go through a lock, so two agents on one plan cannot overwrite each other.

| Status                            | What the harness does                                               |
| :-------------------------------- | :------------------------------------------------------------------ |
| `Completed`                       | moves the folder on, if the files the next state requires are there |
| `Blocked`                         | parks the folder at ⭕️, or at 🅱️ when the note says `product`       |
| `Almost completed`, `Interrupted` | gives the agent another round, up to its limit                      |

An agent that stops without signing (crashed, timed out, killed) is signed `Interrupted` by the harness, and also `Completed` if the work is on disk anyway. A round left `Started` by a harness that has since died is marked `Interrupted` and picked up by the next run.

`luke-backend` and `rey-frontend` work at the same time, in the same worktree, toward one pull request, and talk through `openlanes mail`. Rey only starts when `plan-frontend.md` has work units, so a back-end-only plan costs one builder.

## Safety rails

- **Isolation.** By default every plan gets its own git worktree and branch, `<user>/NNN.MM-slug`. `--isolation shared` runs one agent at a time in one checkout.
- **Agents cannot publish.** `git commit`, `git push`, `gh pr create`, `gh pr edit`, `gh pr merge`, `gh pr review`, `gh pr comment` and `gh release create` are withheld from every agent. An agent's `may:` frontmatter can lift some of these (the reviewer may `gh pr review` and `gh pr comment`), but never `git push` or `gh pr merge`. `WebFetch` and `WebSearch` are withheld unless the agent declares `network: true`.
- **Checked afterwards.** The harness verifies that `HEAD` did not move and that no remote-tracking ref was moved by a push (a `git fetch` is fine). A breach is reported as a failed attempt.
- **The harness publishes.** When a plan finishes, the harness commits the branch, pushes it and opens a pull request titled `[NNN.MM](X) Title`. `--no-git-push` leaves the work uncommitted in its worktree.
- **The plan travels with its pull request.** Before each commit, the publisher copies the plan folder from the main checkout into the worktree under its current name. The main checkout's folder stays the only one the tool reads or writes.
- **Nothing merges automatically.** An approval leaves the plan at 👀 until you merge.
- **Disk over claims.** A plan moves only when the files its new state requires exist. An agent that reports success but wrote nothing is recorded as interrupted.

## GitHub and Linear

- **`resync dirs`** renames folders whose emoji their contents contradict. For example, a ⚪️ with a `plan.md` becomes ⭐️. Safe to run repeatedly.
- **`resync prs`** adds the `[NNN.MM]` prefix to pull request titles, working from the branch name first and the diff second. It reports anything ambiguous and never guesses. By default it adopts an orphan pull request as a retroactive plan; `--no-adopt` flags it instead. Needs `gh`.
- **`linear import TEAM -p PROJECT`** creates one Linear issue per plan and one child issue per work unit. It only goes one way: nothing edited in Linear comes back. `--format json` emits the arguments the Linear MCP tools take. `--update-unchanged` includes plans that have not changed since the last import. `linear projects TEAM` lists a team's projects and which plans they cover.

## From Claude Code

The `/plan-create`, `/plan-run`, `/plan-status` and other `/plan-*` slash commands wrap this same binary and add checks, such as previewing the scope with `-n` before a run. They ship with [agentilda-ai-setup](https://github.com/kigster/agentilda-ai-setup). The bundled skills (`openlanes skills install`) teach any agent how to drive the factory.

## Factory integration test

`just factory-e2e` proves the whole factory through the page. It makes a throwaway git repository with no remote, runs `openlanes init` and `openlanes start --isolation shared` there (port 4777, Redis db 11), and Cypress (`web/cypress/factory/`) then:

1. types a tic-tac-toe idea into the New idea dialog, in the quick lane at depth fast, with no front end;
1. watches the board, answering any question under Needs You from a canned list;
1. waits for `r2d2-mechanic` to finish the build. With no remote there is no pull request, so the plan stays at 🟡 Building;
1. serves the `index.html` the agent wrote, plays a game X wins, checks the win is announced, and checks Restart clears the board.

It runs real `claude` agents, so it costs tokens (one Haiku build). It refuses to run without `OPENLANES_FACTORY_E2E=1`, and nothing in `just test`, `just web-e2e` or CI runs it:

```bash
OPENLANES_FACTORY_E2E=1 just factory-e2e
```

`FACTORY_PORT`, `FACTORY_REDIS_URL`, `FACTORY_MODEL` (default `haiku`), `FACTORY_TIMEOUT` (seconds per agent, default 600) and `FACTORY_MINUTES` (the wait for the build, default 15) override the defaults. The temp repository and its `openlanes start` are removed on every exit; the board, each plan's `state.json`, the progress log, the built page and the tail of each agent's trace are kept in `log/factory-e2e/`.
