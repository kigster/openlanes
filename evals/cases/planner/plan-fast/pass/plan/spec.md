---
frontend: false
---
# Reject Empty Titles

## Goal

`create` refuses an empty title with exit 2 and creates no folder.

## In scope

- `Creator#create("")` raises; the CLI exits 2; a spec proves both.
