---
created: 2026-11-14
starts: planning
frontend: false
depth: medium
depends_on: [none]
phases:
  planning:
    adapter: claude
    model: claude-fable-5-1
  build:
    adapter: claude
    model: claude-sonnet-5-5
  review:
    adapter: grok
    model: grok-4.7-build-fast
  verification:
    adapter: codex
    model: gpt-6-astra
  completion:
    adapter: claude
    model: claude-fable-5-1
---

# An Action Strip per Lane

# an action strip per lane

On the left of each visible lane, where lane details are, on the bottom of the lane add a new dropdown visible only when the lane is in expanded form, not in the narrow form. That dropdown will contains several actions that pertain to this lane only.

at the moment each dropdowm action renders a modal thats has a 10% vertical margin to the visible screen: while width is maximum 1000px, and if the screen shrinks to a width of 1200px or less the modal starts shrinking also maintaining 15% horizomgal margin.

As soon as the page width drops below 600px, the modals margins switch to 5%, and for width < 450px the margin is 1px. The modal is a react component thst receives a markdown input and it renders it on the modal. The top of the modal right has a `[x]` to close it. The bottom had a action pane that has one button "Close".

So we settled that this feature about showing a modal component with the rendering of a given documents, and ideallh it would support images and mermaid diagrams.

## Wiring up actions

Each lane fully expanded features a dropdown that's small, similar to how the cars have a LLM model dropdown, something like that. And in that dropdown, we effectively list every markdowm document in this plans folder. The top one should always be the "Specification". And we do not call it as a file name like lowercase spec.md. The actions are effectively English words that are mapped to the file names. The first one is the specification, the second one is the plan, the third one is if there are any back-end or front-end specific plans, then it says "front-end plan" and "back-end plan". Beyond that, there is a "Block" action menu if there is a blocked.md file. And the final one is “pull requests”, which exists only if the file pull-requests.md exists in that folder. That's basically it.

## how it's rendered

Show me rendered markdown with admonitions, syntax highlighting and mermaid diagrams. 

The frontmatter should be rendered ad a YAML block, at the top. syntax highlighted as YAML.

<!-- cmd:01M7DPCZ3GF7F44YQ2F2MFK0F2 -->

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

