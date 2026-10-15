# Back-end units, plan 002.00

Every unit keeps each command's flags, output, exit codes and help text exactly as they are (Non-Goals). The existing CLI specs are the proof of that and pass unchanged, apart from the one example named in `plan.md` decision 6.

## B1 Refusal, `Base#unwrap`, credentials notice

- **Discipline:** back end.
- **Owns:** `lib/openlanes/support/refusal.rb` (new), `lib/openlanes/cli/base.rb`, `lib/openlanes/execution.rb`, `spec/openlanes/support/refusal_spec.rb` (new), `spec/openlanes/cli/base_spec.rb`.
- **Must not touch:** any command under `cli/<command>/`, `lifecycle.rb`, `engine.rb`.
- **Depends on:** nothing.
- **Builds:**
  - `OpenLanes::Refusal = Data.define(:message, :status)`.
  - `Base#unwrap(result)`: the `Success` value, or `refuse(refusal.message, refusal.status)`.
  - `Execution.credentials_notice` → `String` or `nil`: the text `Base#credentials_warning` draws today, so a workflow can draw it too. `Base#credentials_warning` draws it.
- **Done when:** `refusal_spec.rb` and `base_spec.rb` assert `unwrap` returns a success value and exits with the refusal's status and message.

## B2 `resync prs`

- **Discipline:** back end.
- **Owns:** `lib/openlanes/lifecycle.rb` (first), `lib/openlanes/presentation.rb`, `lib/openlanes/presentation/pr_changes.rb` (new), `lib/openlanes/cli/resync/subcommands/prs.rb`, `spec/openlanes/presentation/pr_changes_spec.rb` (new), `spec/openlanes/lifecycle/retitle_prs_spec.rb` (new).
- **Must not touch:** `lifecycle/resync.rb` internals beyond what the facade needs.
- **Depends on:** B1.
- **Builds:**
  - `Lifecycle.retitle_prs(tree:, github:, adopt:, root:, commit:)` → `Success(Array<Change>)`, or `Failure(Refusal)` with status 69 when GitHub refuses.
  - `Presentation::PrChanges.new(changes, dry_run:)`: `#lines` (the STDOUT rows), `#report` (the retitle list, adoptions, skipped rows, footer and the assumed-prefix warning, drawn on STDERR).
  - `CLI::Resync::Prs#call`: options, one `retitle_prs`, print, done.
- **Done when:** `pr_changes_spec.rb` covers an adopted, an assumed, a flagged and a dry-run report; `retitle_prs_spec.rb` covers success and the 69 failure through a `GitHub` double; `resync_commands_spec.rb` passes unchanged.

## B3 `unblock`

- **Discipline:** back end.
- **Owns:** `lib/openlanes/lifecycle.rb` (after B2), `lib/openlanes/lifecycle/unblock_workflow.rb` (new), `lib/openlanes/cli/unblock/unblock.rb`, `spec/openlanes/lifecycle/unblock_workflow_spec.rb` (new).
- **Must not touch:** `lifecycle/unblocker.rb`.
- **Depends on:** B1, then B2 (same facade file).
- **Builds:** `Lifecycle.unblock(tree:, agent:, root:, dry_run:, quiet:, executor:)` → `Lifecycle::UnblockWorkflow`; `#call(tokens)` → `Success(Integer)` (the exit status: 0, 1, 65 or 66, as `worst` computes today) or `Failure(Refusal)` for an unknown agent (65). Target resolution, the refusal rows, preflight, per-plan outcome rows, the footer and the exit status all live in it.
- **Done when:** `unblock_workflow_spec.rb`, on a real tree with an `Executor` double, covers an unknown agent, a missing plan (66), a plan not blocked (65), a dry run (0, nothing changed) and a folded answer (0); `unblock_spec.rb` and `unblock_edges_spec.rb` pass unchanged.

## B4 `create`

- **Discipline:** back end.
- **Owns:** `lib/openlanes/lifecycle.rb` (after B3), `lib/openlanes/lifecycle/create_workflow.rb` (new), `lib/openlanes/cli/create/create.rb`, `spec/openlanes/lifecycle/create_workflow_spec.rb` (new).
- **Must not touch:** `lifecycle/creator.rb`, `lifecycle/brief.rb`.
- **Depends on:** B1, then B3 (same facade file).
- **Builds:** `Lifecycle.create_plan(dir:, root:, **options)` → `Lifecycle::CreateWorkflow`; `#call(words)` → `Success(Created)` with `Created = Data.define(:path, :message, :spec)` (folder path, the success box text, the `spec.md` to open or `nil`), or `Failure(Refusal)` for every refusal `create` makes today (64, 65, 66). Seed parsing, PR fetching, synthesis, the brief and its draft, the `lane`/`depth` stamp, settling and the next step move into it.
- **Done when:** `create_workflow_spec.rb` covers words, `--from` (good, missing file, bad YAML, no title, with words), `--prs` without `--after`, and `--no-draft`, without constructing a dry-cli command; `create_spec.rb` passes unchanged.

## B5 `run` and `start`

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine.rb`, `lib/openlanes/engine/run_workflow.rb` (new), `lib/openlanes/engine/start_workflow.rb` (new), `lib/openlanes/cli/run/run.rb`, `lib/openlanes/cli/start/start.rb`, `spec/openlanes/engine/run_workflow_spec.rb` (new), `spec/openlanes/cli/run_spec.rb` (the publisher example moves out).
- **Must not touch:** `engine/dispatcher.rb`, `engine/runner.rb` (other open PRs change them).
- **Depends on:** B1.
- **Builds:** `Engine.run(tree:, root:, origin:, **options)` → `Engine::RunWorkflow`, `Engine.start(...)` → `Engine::StartWorkflow`; `#call` → `Success(Integer)` (the exit status) or `Failure(Refusal)`. Agent filtering, `--skip`, `--plan` scoping, the `--agent` assignability check, isolation, the progress log, the state file, the live board and control room, runner construction, the run and the closing report live in it. `StartWorkflow` overrides staying, the two "without" paths (now `Failure(Refusal(…, 69))`), the browser URL and the closing report. `PROMPT_PATH_LIMIT` moves with `instructions_from`.
- **Done when:** `run_workflow_spec.rb`, on a real tree, `--isolation shared`, an `Executor` double, covers an unknown `--agent`, an unknown `--plan`, `--agent` with `--skip` of the same name, a dry run returning 0, and the publisher examples; `run_spec.rb` (less the moved example) and `start_spec.rb` pass unchanged.

## B6 Integration check

- **Discipline:** back end.
- **Owns:** `spec/openlanes/integration/thin_commands_spec.rb` (new).
- **Must not touch:** anything under `lib/`.
- **Depends on:** B2–B5.
- **Builds:** spawns the real `exe/openlanes`, nothing stubbed, in a `PlansFixture` tree, with a fake `claude` that exits 1 first on `PATH` and `BUNDLER_ORIG_PATH`: `create --no-draft --no-open` (prints the folder, exit 0), `create --from missing.md` (exit 66), `unblock 999 -n` (exit 66), `unblock <blocked> -n` (exit 0, the open question listed), `run -n --isolation shared --no-web` (exit 0, `would invoke`), `run --agent nobody` (exit 65).
- **Done when:** that spec passes, and `wc -l` of the four command files is reported in `pull-requests.md`.
