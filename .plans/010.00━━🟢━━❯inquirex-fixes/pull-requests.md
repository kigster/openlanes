# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 13 | [inquirex: Add Engine#back and a headless answer driver](https://github.com/inquirex/inquirex/pull/13) | OPEN |
| 8 | [inquirex-llm: Use current Claude model ids; bump to 0.12.0](https://github.com/inquirex/inquirex-llm/pull/8) | OPEN |
| 13 | [inquirex-tty: Ctrl-B back, headless runs, results on stdout; 0.12.0](https://github.com/inquirex/inquirex-tty/pull/13) | OPEN |

## What these pull requests did

- **inquirex/inquirex#13** (repository `inquirex/inquirex`, not openlanes): units B3 and B4. `Engine#back`, `#can_back?`, `#previous_answer`, `#current_default`, and `Inquirex::Headless` with `MissingAnswer`. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.11.0. No version bump.
- **https://github.com/inquirex/inquirex-llm/pull/8** (repository `inquirex/inquirex-llm`): unit B2 and B5's version part. `AnthropicAdapter::MODELS` with the Claude 5.x ids, no `temperature` for them, version 0.12.0 on `inquirex ~> 0.12`, CircleCI, gemspec spec. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.10.0.
- **https://github.com/inquirex/inquirex-tty/pull/13** (repository `inquirex/inquirex-tty`; not the core PR of the same number): units F1, F2, F3 and B5's version part. Ctrl-B back, `run --answers` / `--yes`, results on stdout (breaking), README samples, version 0.12.0 on `inquirex ~> 0.12` and `inquirex-llm ~> 0.12`, CircleCI, gemspec spec. Branch `kig/010.00-inquirex-fixes`, from `main` at 0.10.0.

CI on both resolves inquirex 0.12.0 from RubyGems, so it fails until the owner publishes inquirex, then inquirex-llm, then inquirex-tty.
