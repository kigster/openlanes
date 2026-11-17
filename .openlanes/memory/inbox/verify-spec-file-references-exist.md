---
id: verify-spec-file-references-exist
title: Check every file, page and line reference in a spec against the code before
  handing it to builders
applies_to:
- planner
- build
checked_by:
- staff-reviewer
kind: pitfall
severity: medium
status: candidate
proposed: 2026-11-17
source:
- plan: '003.00'
  finding: frontend-coder blocked in round 1 because the spec named a web plan page,
    view templates and a web.rb:25 file list that did not exist; the UI was a React
    app fed by the snapshot wire.
---

A spec that cites surfaces from memory sends builders to code that is not there, and they stop to ask. Before finalizing a spec, open each cited path and line and confirm it exists. If the spec and the code disagree, the code wins: record the correction in the spec.
