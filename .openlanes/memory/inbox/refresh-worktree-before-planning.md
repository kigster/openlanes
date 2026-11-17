---
id: refresh-worktree-before-planning
title: Before planning, check the worktree is current with main, and re-measure from
  main when it is not
applies_to:
- planner
checked_by:
- staff-reviewer
kind: pitfall
severity: medium
status: candidate
proposed: 2026-11-17
source:
- plan: '002.00'
  finding: Planner round 1 blocked on three questions measured in a worktree four
    weeks behind main. Merged work had already made all three moot, and the spec had
    to be rewritten.
---

A stale worktree still holds the old code, so the counts and open questions taken from it describe a repository that no longer exists. Before sizing work or asking a person anything, compare the worktree with main: `git log HEAD..origin/main` shows what it lacks. If it lags, update it or take the measurements from main. Ask a person only about questions that are still open there.
