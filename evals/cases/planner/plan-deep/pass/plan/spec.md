---
frontend: false
---
# Duplicate Job IDs

## Goal

The job queue refuses a job whose ID is already queued, and says which job holds it.

## In scope

- `Queue#push` rejects a duplicate ID with `Queue::Duplicate`.
- The worker logs the rejected ID and the holder.
- `config/queue.yml` gains `dedupe: true`, read by both.
