# Agent evals

Every agent is checked twice (decision D8 in `docs/decisions/decisions-on-agent-speed-lanes-and-adapters.md`):

1. **Did it finish the task?** State reached, artifacts present, ledger signed.
2. **Did it work at the depth requested?** Size and section bounds, sources cited, diff size, time and tokens, all bounded per depth (`fast`, `medium`, `deep`). Too shallow for `deep` fails; overdone or slow for `fast` fails too.

The code lives in `lib/openlanes/evals/` (`OpenLanes::Evals`).

## Running

```bash
just eval                                   # score every case's pass/ recording; exit 1 on any FAIL
exe/openlanes eval --recording fail         # score the fail/ recordings; every one should FAIL
exe/openlanes eval -a researcher --depth deep   # hold recordings to another depth's bounds
exe/openlanes eval --live -c research-fast --max-tokens 100000
```

- Offline (the default) runs no agent and spends nothing. CI runs it through the spec suite.
- `--live` builds a temp git repository from the fixture, stamps `depth:` into `spec.md`, runs the real agent through `Execution.executor` under a token cap (default 300 000), runs `resync dirs` as the runner does after a round, and scores the folder it finds by ordinal. The repository is deleted afterwards.

## A case

`cases/<agent>/<id>.yml`. Unknown keys are refused, so a misspelt check cannot silently never run.

```yaml
id: research-fast              # must match the file name
agent: researcher         # must match the directory
depth: fast                    # fast | medium | deep
description: What the case targets.
fixture:
  state: new                   # the status key the plan folder starts in
  slug: billing-retries        # default: the id
  files:   { spec.md: "..." }  # plan-folder files; spec.md is required
  repo:    { lib/a.rb: "..." } # repository files, for coding agents
expect:
  state: researched            # where the folder must end, and that state's invariant must hold
  signed: true                 # last ledger entry is Completed; a string also requires that note, e.g. rejected
  files_exist: [plan.md]
  files_absent: [blocked.md]
  sections: { spec.md: [Research] }          # headings, any level
  contains: { spec.md: [lib/a.rb, "/regex/"] }
  excludes: { spec.md: [TODO] }
  changed_paths: [lib/**/*.rb]               # each glob must match a changed path
  untouched: [Gemfile]                       # no changed path may match
  depth:                                     # only the case's depth applies
    fast:
      words: { file: spec.md, section: Research, min: 40, max: 180 }
      count: { file: spec.md, section: Research, pattern: 'https?://', min: 1, max: 3 }
      changed_files: { min: 1, max: 2 }
      changed_lines: { max: 20 }
      max_seconds: 300
      max_tokens: 80000
```

`words` and `count` take one mapping or a list. Ledger blocks are stripped before counting, so signing never pads a document. `max_seconds` and `max_tokens` fail when the run measured nothing.

Build agents (backend-coder, frontend-coder, chores-coder) and staff-reviewer check signatures and diffs, not `state`: their next state depends on a published pull request and a review verdict, which an eval never produces.

## Recordings

```
cases/<agent>/<id>/pass/plan/      the plan folder after a good run
cases/<agent>/<id>/pass/repo/      the whole repository after it (optional)
cases/<agent>/<id>/pass/run.json   {"seconds": 142, "tokens": 38150, "state": "researched"}
cases/<agent>/<id>/fail/...        the same, after a run that fails for the reason the case targets
```

`run.json` carries `state` because `plan/` has no status emoji in its name. Changed paths and lines are computed by comparing `repo/` with `fixture.repo`, so a recorded `repo/` must hold every file, changed or not. `spec/openlanes/evals/corpus_spec.rb` asserts every `pass/` passes and every `fail/` fails: the corpus is the scorers' test suite.

Keep recordings small and synthetic. No real names, emails or private source.

## Not covered yet

Ideas carried over from the earlier `cases.jsonl` draft, which never ran:

- spec-writer: a brief with an unresolved product choice must list it, not invent a policy.
- planner: two units writing one file must be ordered, not parallel.
- frontend-coder: a contract mismatch with the back end must be raised, not patched around.
- staff-reviewer: a clean patch must be approved (false-finding rate); a missing authorisation check must be found.
- unblocker: a partial answer folds one block and leaves the rest; contradictory answers fold nothing.
- Routing, scheduler and readiness evals belong to the engine, not to one agent, and need their own harness.
- Exporting scores and traces to an experiment tracker, and running each live case repeatedly to report variance.
