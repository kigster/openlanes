# Starting an app with OpenLanes

How to get from an empty directory, or a ready-made example, to `ol start` building your app. Items marked _(planned)_ are decided but not built yet; see [`decisions/decisions-on-example-apps.md`](decisions/decisions-on-example-apps.md).

## 1. Pick a starting point

**From scratch:** make a directory and turn it into a git repository.

```bash
mkdir ~/src/my-app && cd ~/src/my-app
git init
```

**From an example** _(planned, plan 047.00)_: the [`openlanes-examples`](https://github.com/kigster/openlanes-examples) repository holds `macos-clipboard`, `rust-logtail`, `rails-habits` and `astro-blog`, and takes pull requests for templates of other stacks. `ol new` copies one out into a fresh repository of its own. Never run `ol start` inside the examples checkout: the agents would rewrite the template itself.

```bash
ol new --example rust-logtail ~/src/logtail   # copies, runs git init and ol init -y
cd ~/src/logtail
```

An example already ships the files from steps 3 to 5, so skip to step 6.

## 2. Install and configure

```bash
ol setup      # brew bundle, checks claude, gh auth and Redis
ol init       # writes .openlanes.yml and creates .plans/
```

`ol init` asks where plans start, how good the code should be, which CI checks pull requests and who merges. `ol init -y` takes the defaults.

## 3. Write `.plans/APPLICATION.md`

Copy [`application-template.md`](application-template.md) to `.plans/APPLICATION.md` (`ol init` will write it for you, _planned, plan 048.00_). Fill in its five headings: what it is, goals, non-goals, stack and constraints, and what done looks like.

The non-goals do the most work: they are what a plan gets sent back for drifting into. Agents read the file _(planned, plan 048.00: leah, yoda and palpatine get it in their prompts)_.

## 4. Grill it into `.plans/BACKLOG.md` _(planned, plan 048.00)_

A grilling session reads `APPLICATION.md`, asks you one question at a time, and writes `BACKLOG.md`: detailed candidates, each sized to one plan. Until it lands, write `BACKLOG.md` by hand or skip to step 5.

## 5. Create the first plans

```bash
ol create user can add a habit             # mints .plans/001.00━━⚪━━❯user-can-add-a-habit with a spec.md
ol create --from-backlog add-a-habit       # (planned) the same, from a BACKLOG.md item, which it removes
```

Edit each `spec.md` before the agents start; [`spec-template.md`](spec-template.md) explains its four headings.

## 6. Start the factory

```bash
ol start              # engine plus control room, until Stop All Local or Ctrl-C
ol start --no-git-push   # keep everything local: no pushes, no pull requests
```

Answer the questions agents raise on the control-room page. Run it inside `tmux` or `screen` so it survives a closed terminal.

## What a fresh project contains

```
my-app/
  README.md             what the app is and how to build and run it
  .openlanes.yml        written by ol init
  .plans/
    APPLICATION.md      what it is, goals, non-goals (step 3)
    BACKLOG.md          candidates that are not plans yet (step 4)
    001.00━━⚪━━❯slug/       one folder per plan, spec.md inside (step 5)
```
