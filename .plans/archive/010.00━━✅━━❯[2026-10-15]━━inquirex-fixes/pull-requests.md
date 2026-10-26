# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 13 | [inquirex: Add Engine#back and a headless answer driver](https://github.com/inquirex/inquirex/pull/13) | Merged 🟣 |
| 8 | [inquirex-llm: Use current Claude model ids; bump to 0.12.0](https://github.com/inquirex/inquirex-llm/pull/8) | Merged 🟣 |
| 13 | [inquirex-tty: Ctrl-B back, headless runs, results on stdout; 0.12.0](https://github.com/inquirex/inquirex-tty/pull/13) | Merged 🟣 |

## What these pull requests did

- **inquirex/inquirex#13** (repository `inquirex/inquirex`, not openlanes): units B3 and B4. `Engine#back`, `#can_back?`, `#previous_answer`, `#current_default`, and `Inquirex::Headless` with `MissingAnswer`. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.11.0. No version bump.
- **https://github.com/inquirex/inquirex-llm/pull/8** (repository `inquirex/inquirex-llm`): unit B2 and B5's version part. `AnthropicAdapter::MODELS` with the Claude 5.x ids, no `temperature` for them, version 0.12.0 on `inquirex ~> 0.12`, CircleCI, gemspec spec. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.10.0.
- **https://github.com/inquirex/inquirex-tty/pull/13** (repository `inquirex/inquirex-tty`; not the core PR of the same number): units F1, F2, F3 and B5's version part. Ctrl-B back, `run --answers` / `--yes`, results on stdout (breaking), README samples, version 0.12.0 on `inquirex ~> 0.12` and `inquirex-llm ~> 0.12`, CircleCI, gemspec spec. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.10.0.

CI on both resolves inquirex 0.12.0 from RubyGems, so it fails until the owner publishes inquirex, then inquirex-llm, then inquirex-tty.

## Review round 1 (staff-reviewer, 2026-10-15)

Not reviewed: all three pull requests were already merged by `kigster` before this round started, so there is nothing left to approve or reject. No label was applied.

| Repository | PR | Merged at (UTC) | Merge commit | Commits |
| :--------- | -: | :-------------- | :----------- | ------: |
| inquirex/inquirex | 13 | 2026-10-14 20:46 | `a8def1f` | 6 |
| inquirex/inquirex-llm | 8 | 2026-10-15 08:01 | `ea7d08f` | 24 |
| inquirex/inquirex-tty | 13 | 2026-10-15 08:28 | `5aebdd6` | 13 |

- The Status column above still says OPEN; it is stale.
- `inquirex-tty` merged with commits beyond the plan (`fe15e41` Backspace-to-go-back with skip, help and abort; `69e8589` navigation keys docs), so the merged diff no longer matches `spec.md`'s Ctrl-B decision.
- Open for a human: whether to record that spec change, and whether the unreviewed merge needs a post-merge review. The folder should move on by hand (its work is on `main` in each repository).
