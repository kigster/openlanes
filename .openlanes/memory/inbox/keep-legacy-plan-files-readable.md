---
id: keep-legacy-plan-files-readable
title: When renaming plan files, keep reading the old names so existing plan folders
  still work
applies_to:
- build
checked_by:
- staff-reviewer
kind: decision
severity: medium
status: candidate
proposed: 2026-11-17
source:
- plan: '003.00'
  finding: The plan-file consolidation kept a fallback from plan.md sections to plan-<section>.md
    and implementation-plan.md (decision D3), since older folders, including this
    one, still use those names.
---

Plan folders on disk are never migrated, so a rename of a plan file or a ledger entry strands every older folder if the code reads only the new name. Keep a fallback to the old names in routing and in agent prompts, and derive it rather than listing it. Do not require an empty grep for the old name as a done-when.
