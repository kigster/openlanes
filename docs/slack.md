# Questions in Slack

A running engine can ask its questions in a Slack channel as polls. Each question a plan is blocked on is posted once, with one numbered reaction per option. Click a number to choose that option, or reply in the message's thread to answer in your own words. The answer is written to the plan's `blocked.md` exactly as an answer given in the control room is, and the message is updated to say who answered.

The control room keeps working alongside it. A question answered there closes its poll in Slack, and the other way round.

## Set up

```bash
openlanes slack connect U0123ABCD openlanes-questions
```

The first argument is who may answer: Slack user ids, separated by commas. Find one under a profile's **⋯ → Copy member ID**. The second is the channel, a public channel's name or any channel's id (a private channel needs the id). Leave it out for the channel already configured, or `#openlanes-questions`.

The command:

1. Asks for the bot token when there is none, with a link that opens Slack's new-app page filled in from [`slack-app-manifest.yml`](slack-app-manifest.yml). Create the app, **Install to Workspace**, and copy the **Bot User OAuth Token** (`xoxb-…`) from **OAuth & Permissions**. A token in `SLACK_BOT_TOKEN`, or in the file `--app-env` names, is used without asking.
1. Asks Slack which workspace the token belongs to, and pins it.
1. Writes the settings to the project's `.env`, which git must ignore.
1. Posts a test poll in the channel and prints who answered it. Invite the app first: `/invite @openlanes`. `--no-test` skips the poll, and `openlanes slack test` posts it again later.

`-n` prints what it would write and posts nothing. The engine reads the environment, so `.env` has to be loaded before `openlanes start`: direnv does it with `dotenv_if_exists` in `.envrc`.

After that, `openlanes start` and `openlanes run` ask in Slack whenever they have a live board, which needs Redis.

### Settings

| Environment | `.openlanes/config.yml` | What it is |
| :-- | :-- | :-- |
| `SLACK_BOT_TOKEN` | never | the bot token, a secret |
| `OPENLANES_SLACK_CHANNEL` | `slack.channel` | the channel's id, or a public channel's `#name` |
| `OPENLANES_SLACK_OPERATORS` | `slack.operators` | the only user ids whose answers count; required |
| `OPENLANES_SLACK_WORKSPACE` | `slack.workspace` | the team id the token must belong to |
| none | `slack.poll_seconds` | seconds between two calls to Slack, 2 by default |

The environment wins over the file. The control room's Settings page edits the file's `slack` section.

### No questions in the channel?

The engine logs a warning that starts with `slack:` when only part of this is set, naming the part that is missing. With no token and no channel it says nothing, because the project has not asked for Slack, and neither does a token on its own: one exported for another tool is not a request for Slack. A gem that has no `openlanes slack connect` is older than this feature: upgrade it.

## Commands from Slack

Asking for status, adding a plan or restarting one from Slack is a separate app, `openlanes-slack`, a client of the control room's HTTP API. It can use the same Slack app. It is meant to read the same `OPENLANES_SLACK_OPERATORS` and `OPENLANES_SLACK_WORKSPACE`, but does not yet: today it reads only `SLACK_*`, so `--app-env` writes names nothing there reads. It never asks the questions, so each is posted once. It needs Socket Mode and the `commands` scope, which the manifest here leaves out because the engine needs neither.

## How it works

- **No public URL.** The engine reads answers by asking Slack for each open poll's reactions and thread, over HTTPS it starts itself. Slack never calls back, so there is no endpoint to expose, no Socket Mode and no signing secret. The price is latency: one poll is read every `poll_seconds`, so with five questions open an answer is heard within about ten seconds.
- **The workspace is checked, not chosen.** A bot token belongs to one workspace. `slack.workspace` names the one intended, and a token that belongs to another posts nothing. Give the team id (`T…`, which `openlanes slack connect` writes): it is the only name that is unique and never changes. A team name or subdomain is accepted, but either can be renamed or shared.
- **Who may answer: only `operators`.** An answer becomes an agent's instructions, and the agents run with a shell in the repository, so a reaction or a reply counts only from a user id listed in `operators`. Without the list there is no bridge: the run says so once and asks in the control room only. "Anyone in the channel" would include whoever joins it, and a Slack Connect guest from another organisation. Find an id under a profile's **⋯ → Copy member ID**.
- **One decision per poll.** Slack does not say which reaction came first, so the lowest-numbered option an operator chose is the answer. A reaction wins over a thread reply.
- **What is posted is escaped.** Plan titles, headings, options and echoed replies have `&`, `<` and `>` escaped, so a heading cannot ping `<!channel>` or draw a link of its own.
- **A poll fails alone.** A poll whose message was deleted, or whose channel was archived, is forgotten and posted again while its question is still asked; any other refusal of one message skips that poll for the cycle. Only a refusal that holds for every poll (a token, scope or channel problem), a rate limit or the network pauses the rest.
- **The same questions as the page.** Prose questions the engine rewrites into choices are redrawn in place when the choices arrive. The engine's own questions (more time for an agent, the codebase quality) are polls too.
- **A failure costs the polls only.** A wrong token, a channel the app is not in or Slack being down is logged once as a warning and tried again thirty seconds later. The run goes on, and the questions stay answerable in the control room.

## Scopes

| Scope | Used for |
| :-- | :-- |
| `chat:write` | posting and updating the poll |
| `reactions:write` | putting the numbered reactions on it |
| `reactions:read`, `channels:history` | reading who clicked and who replied |
| `groups:history` | the same, in a private channel |
| `users:read` | signing the answer in `blocked.md` with a name; without it, the user's id |
