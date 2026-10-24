# Decisions on durable run events in PostgreSQL

Date: 2026-10-23. Asked by kig. Plans 020.01 (`durable-run-events`, #105) and 020.02.

## Why

Plan 020.01's spec first chose an append-only JSONL log with a CLI report. A later edit (D1) asked for an ActiveRecord sink on SQLite or PostgreSQL, four tables, a nav button and a web Reports page, in the same plan. #105 already shipped and verified the JSONL log, so D1 would have sent finished work back to planning. These decisions replace D1.

## Decisions

### D1. The JSONL log stays, and is the feature without PostgreSQL

Every run with `events.enabled` writes the append-only JSONL log, and `openlanes events report` reads it. A project with no PostgreSQL loses the Reports page and the other database-backed pages, and nothing else.

### D2. PostgreSQL is optional, and is plan 020.02

020.01 (#105) merges as it is. 020.02, `depends_on: 020.01`, adds the PostgreSQL side. When a database is configured, events land in it as well as in the log.

### D3. Four tables

- `events`: append-only, unique on `event_id`.
- `agents`: each agent with its markdown definition, imported from `agents/*.md`.
- `plans`: a UUIDv7 primary key, the `NNN.MM` ordinal (unique), the title without the state emoji.
- `tasks`: plans in flight.

### D4. `tasks` is filled from events, not from Redis

The writer updates `tasks` as it inserts each event. Redis pub/sub is not used, so Redis stays off the write path and an outage loses nothing.

### D5. PostgreSQL only

No SQLite. Without PostgreSQL, the JSONL log and the CLI report already cover a single machine, and one SQL dialect keeps UUIDv7, `jsonb` and partial indexes simple.

### D6. The PostgreSQL class is PG-lax

Run telemetry holds no money, PII or health records, and the JSONL log can rebuild it. 020.02 writes the class into `CLAUDE.md` before its first migration.

### D7. Reports page

A nav button switches between the Board and Reports pages; loading one closes the other. The page shows the reports the CLI prints, computed by the same classes, using shadcn components where they fit.
