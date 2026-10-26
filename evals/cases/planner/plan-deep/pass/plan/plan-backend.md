## U1 Dedupe setting

- **Discipline:** back end
- **Owns:** `config/queue.yml`, `lib/queue/config.rb`, `spec/queue/config_spec.rb`
- **Must not touch:** `lib/queue.rb`, `lib/worker.rb`
- **Depends on:** nothing
- **Done when:** `spec/queue/config_spec.rb` passes

## U2 Reject duplicates

- **Discipline:** back end
- **Owns:** `lib/queue.rb`, `spec/queue_spec.rb`
- **Must not touch:** `config/queue.yml`, `lib/worker.rb`
- **Depends on:** U1
- **Done when:** `spec/queue_spec.rb` "rejects a duplicate id" passes

## U3 Worker logging

- **Discipline:** back end
- **Owns:** `lib/worker.rb`, `spec/worker_spec.rb`
- **Must not touch:** `config/queue.yml`, `lib/queue.rb`
- **Depends on:** U1
- **Done when:** `spec/worker_spec.rb` "logs the holder" passes

## U4 Integration check

- **Discipline:** back end
- **Owns:** `spec/integration/dedupe_spec.rb`
- **Must not touch:** every other file
- **Depends on:** U2, U3
- **Done when:** `spec/integration/dedupe_spec.rb` passes with nothing stubbed

