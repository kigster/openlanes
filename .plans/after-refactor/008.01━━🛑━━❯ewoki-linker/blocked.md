# Blocked, round 1 after 🔴 (backend-coder, 2026-10-23)

## B2 Which linking model the spec and PR #114 should share

staff-reviewer rejected PR #114 (round 1 of 2) mainly because the PR and `spec.md` describe different designs. The PR adds a 🔗 `ready_for_linking` state that `ewoki-linker` handles. Its `agents list` row reads `Ready for Linking → Ready for Planning`, and plans already at 📋/⭐️ are never linked by `run`. The spec forbids a new state (Non-Goal 5) and asks for `precedes ready_for_planning, planned`, `Registry#preceding`, a tsort in `run` and a `$USER/plan-linking-NNN.MM` branch. Grok's 💩 on `dispatcher.rb:1735` (🔗→📋 passes without `depends_on:`) applies only to the state model. Which design is right is a product call, not mine.

a) Keep #114's 🔗 state. Amend `spec.md` (Non-Goal 5, items 6 and the tsort/plan-linking text, the How-to-test lines), then fix the code findings: gate 🔗→📋 on `Spec#linked?`, make `linked?` accept only valid ordinals or `none`, report `unchanged` and malformed specs from `link`, scope the cycle check, confine `rg`/`git` flags, make the `newrelic` require optional and add `ruby`/`x86_64-linux` to `Gemfile.lock`. (Recommended)
b) Rework #114 to the spec's `precedes:` model: remove the 🔗 state, build `Registry#preceding`, the tsort in `run` and the plan-linking branch, then fix the remaining findings.
c) Drop #114's linker and publish `kig/008.01-ewoki-linker` (`0398136d`), which already builds the spec's `precedes:` model (`agents list` showed `precedes ready_for_planning, planned`, and evals were 3/3), after #122 merges.

## B3 Where fixes to PR #114 should be committed

This plan's worktree (`openlanes.worktrees/008.01-ewoki-linker`) is on `kig/eval-agent-positional`, the head of PR #122. The harness commits and pushes whatever I change here, so a fix for #114 would land on #122. `kig/ewoki-linker` is checked out in `openlanes.worktrees/ewoki-linker`, so git will not check it out here as well. staff-reviewer's finding 4 (scope creep: README, gemspec, Brewfile, `bin/ol-tee`, web board, `lanes.rb`, `github.rb`/`label_sync.rb`) also asks for #114 to be split, and only the branch owner can do that. #114 is labelled `human-should-merge-this`.

a) Remove `openlanes.worktrees/ewoki-linker` (its tree is clean, on `36c8f690`) and switch this worktree to `kig/ewoki-linker`, so the harness's commit and push go to #114. The split stays with kig. (Recommended)
b) kig makes the fixes in `openlanes.worktrees/ewoki-linker` outside the pipeline, and this plan waits at 🔴 for the next review.
c) I edit `openlanes.worktrees/ewoki-linker` directly next round and kig commits and pushes by hand.
