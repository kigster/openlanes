---
title: Lane note beta
starts: building
---

# Lane note beta

## Problem

The repository needs a small note file for the beta lane.

## Proposal

First run `sleep 90` in the shell, once: the lane-control test needs this plan to keep its agent busy while it checks that a second `/restart` is refused. Then write one text file, `notes/beta.txt`, containing the single line "beta was here". Nothing else changes: no tests, no tooling.

## Acceptance criteria

- `notes/beta.txt` exists and holds exactly that line.

## How to tell it's working?

- `cat notes/beta.txt` prints "beta was here".
