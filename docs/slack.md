# Questions in Slack

A running engine can ask its questions in a Slack channel as polls. Each question a plan is blocked on is posted once, with one numbered reaction per option. Click a number to choose that option, or reply in the message's thread to answer in your own words. The answer is written to the plan's `blocked.md` exactly as an answer given in the control room is, and the message is updated to say who answered.

The control room keeps working alongside it. A question answered there closes its poll in Slack, and the other way round.

## Set up

1. Create the Slack app. At <https://api.slack.com/apps> choose **Create New App**, then **From a manifest**, pick the workspace, and paste [`slack-app-manifest.yml`](slack-app-manifest.yml):

   ```yaml
   display_information:
     name: OpenLanes
     description: Asks the questions OpenLanes agents are blocked on
   features:
     bot_user:
       display_name: openlanes
       always_online: false
   oauth_config:
     scopes:
       bot:
         - chat:write
         - reactions:read
         - reactions:write
         - channels:history
         - groups:history
         - users:read
   settings:
     org_deploy_enabled: false
     socket_mode_enabled: false
     token_rotation_enabled: false
   ```

1. **Install to Workspace**, then copy the **Bot User OAuth Token** (`xoxb-…`) from **OAuth & Permissions**.

1. Put the token in the environment as `SLACK_BOT_TOKEN`. It is a secret, so it never goes in `.openlanes/config.yml`; keep it wherever the project keeps its others (`.env` through `sopsy`, for this repository).

1. Invite the app to the channel: `/invite @openlanes`.

1. Name the channel in `.openlanes/config.yml`:

   ```yaml
   slack:
     channel: "#openlanes-questions"   # or the channel's id, C0123ABCD; a private channel needs the id
     workspace: T0123ABCD              # optional: the team id the token must belong to (a name or subdomain works, but can be renamed)
     operators: [U012ABC, U034DEF]     # required: the only people whose answers count
     poll_seconds: 2                   # optional: seconds between two calls to Slack
   ```

1. Check it, before any plan depends on it:

   ```bash
   openlanes slack test
   ```

   It posts a sample poll, waits for an answer, and prints who gave it and what it was. Nothing in `.plans` is touched.

After that, `openlanes start` and `openlanes run` ask in Slack whenever they have a live board, which needs Redis.

## How it works

- **No public URL.** The engine reads answers by asking Slack for each open poll's reactions and thread, over HTTPS it starts itself. Slack never calls back, so there is no endpoint to expose, no Socket Mode and no signing secret. The price is latency: one poll is read every `poll_seconds`, so with five questions open an answer is heard within about ten seconds.
- **The workspace is checked, not chosen.** A bot token belongs to one workspace. `slack.workspace` names the one intended, and a token that belongs to another posts nothing. Give the team id (`T…`, which `openlanes slack test` prints): it is the only name that is unique and never changes. A team name or subdomain is accepted, but either can be renamed or shared.
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
