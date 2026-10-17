---
created: 2026-10-16
lane: plan
frontend: true
---

# Lanes with No Active Agents

## Lanes With No Active Agents

After a temporary glitch with Redis connection, it appears that some of the lanes lost their agents. 

## What this plan is about?

This plan is about providing several specific commands to the side copilot that break "read-only" access and allow it to perform certain actions. 

Actions allowed and commands:

- `/stop plan-number`: sends the message to the dispatcher to stop the agent executing a specific plan and remove that plan from the "currently being worked on" board.
- `/restart plan-number` : only does something if the plan does not have an active agent attached, but is on the board. This sends the message to the dispatcher that it must effectively "run <plan-number>" so that the plan restarts.
- `/concurrency N` : changes the parameters provided in the beginning with -j. For example if the server was started with -j 4, and the command is `/concurrency 3` it communicates to the dispatcher the new concurrency limit. The dispatcher is allowed to wait for the agents to finish before reducing concurrency.

## How to test

In Cypress create a sample project with three simple plans and start the backend with concurrency -j 3. The use the web UI to open copilot and execute the commands, and verify their effect. Make sure that the specs for each plan are simple enough that they would take only a few minutes to complete.

<!-- cmd:01M53PEK85EPV76CQCGVT3QGMG -->

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

