# frozen_string_literal: true

# vim: ft=ruby
#
# What openlanes shells out to at run time, read from the code rather than
# guessed. `openlanes setup` runs `brew bundle --no-upgrade` on this file, so
# it ships in the gem. A contributor's extras live in `Brewfile.dev`, which
# `bin/setup` bundles too and the gem does not ship.

brew 'gh'          # Vcs::GitHub: pull requests, reviews, CI looks; agents read PR comments
brew 'git'         # worktrees, branches, the boundary's reflog check
brew 'imagemagick' # Verification::Screenshots recompresses each PNG with `magick`
brew 'jq'          # coverage report_command, and reading traces back (Executor::TRACE_DIR)
brew 'just'        # Execution::Checks runs `just <recipe>` where a project has one
brew 'redis'       # the live run: board, commands, plan claims (Live)
brew 'ripgrep'     # what the agents search with
brew 'vips'        # Verification::Screenshots tries `vips pngsave` before `magick`
