# Verification: 010.00 inquirex-fixes

Recorded by plan-010b, 2026-10-14. Answers the spec's "Whether the gems pass their suites on Ruby 4.1.0-preview1" and plan.md's "Done when".

## Ruby 4.1.0-preview1

| Gem | Command | Result |
| :-- | :------ | :----- |
| `inquirex` (inquirex/inquirex#13) | `just test` | 987 examples, 0 failures, 97.48% line coverage (recorded in `implementation-plan.md`) |
| `inquirex-llm` (https://github.com/inquirex/inquirex-llm/pull/8) | `just test` | 243 examples, 0 failures, 98.4% |
| `inquirex-tty` (https://github.com/inquirex/inquirex-tty/pull/13) | `just test` | 157 examples, 0 failures, 96.6% |

The same suites pass on Ruby 4.0.6, the version CI runs. `just lint` reports no offenses in either gem.

The research's Bundler-only failure on `inquirex-tty` (`NameError: uninitialized constant Pathname::SEPARATOR_PAT`, Bundler 4.0.10) is gone: its `Gemfile.lock` now names Bundler 4.0.16, and `bundle install` and the suite run under it on 4.1.0-preview1. No run without Bundler was needed.

Both gems were run against the unpublished core through `path:` lines in their Gemfiles, kept local and uncommitted.

## The three gems in one bundle

A throwaway consumer whose Gemfile names only the three gems, by `path:`:

```ruby
gem "inquirex",     path: "/Users/kig/github/inquirex/inquirex.worktrees/010.00-inquirex-fixes"
gem "inquirex-llm", path: "/Users/kig/github/inquirex/inquirex-llm.worktrees/010.00-inquirex-fixes"
gem "inquirex-tty", path: "/Users/kig/github/inquirex/inquirex-tty.worktrees/010.00-inquirex-fixes"
```

`bundle install`, then `bundle exec ruby check.rb`, which requires all three and runs a fixture flow through `Inquirex::Headless`:

```text
=== 4.1.0-preview1
ruby 4.1.0; loaded: inquirex 0.12.0, inquirex-llm 0.12.0, inquirex-tty 0.12.0, prism 1.9.0, ostruct 0.6.3
headless answers: {income_types: ["w2", "rental"], rental_count: 1, client_name: "Alan Turing", client_email: "alan.turing@manchester.edu"}
default model: claude-sonnet-5-5
=== 4.0.6
ruby 4.0.6; loaded: inquirex 0.12.0, inquirex-llm 0.12.0, inquirex-tty 0.12.0, prism 1.9.0, ostruct 0.6.3
headless answers: {income_types: ["w2", "rental"], rental_count: 1, client_name: "Alan Turing", client_email: "alan.turing@manchester.edu"}
default model: claude-sonnet-5-5
```

prism and ostruct reach the consumer as declared runtime dependencies, not through a development bundle.

## Headless run, results on stdout

`spec/integration/headless_run_spec.rb` in `inquirex-tty` spawns the real executable with STDIN closed: `--answers` (YAML and JSON) plus `--yes` exits 0 with every answer as JSON on stdout; `-o FILE` leaves stdout empty; `-o -` is stdout; `--answers` alone exits 1 naming `:rental_count` (the step it leaves to its default); `--yes` with an undefaulted required step exits 1 naming `:client_name`.

## Back in a real terminal

The executable under Ruby's `PTY.spawn`, keys `Alan⏎`, Ctrl-B (byte 0x02), `⏎`, Down, `⏎`: the name was asked again showing `(Alan)`, the tip line `Ctrl-B: back to the previous question` was drawn, and stdout held only the results, `name: "Alan"`, `color: "blue"`. Ctrl-B is a plain control character, which terminals send without any key mapping; no person pressed keys in iTerm2 or Terminal.app for this record.

## Not verified

- The Claude 5.x model ids against the live API (no key spent; out of scope per spec).
- CI: both pull requests resolve inquirex 0.12.0 from RubyGems, which does not have it yet.
