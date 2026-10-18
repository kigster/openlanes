 # rubocop:disable Naming/FileName,Lint/MissingCopEnableDirective
 # vim: ft=ruby # rubocop:disable Layout/CommentIndentation

# What openlanes shells out to at run time, read from the code rather than
# guessed. `openlanes setup` runs `brew bundle --no-upgrade` on this file, so
# it ships in the gem. A contributor's extras live in `Brewfile.dev`, which
# `bin/setup` bundles too and the gem does not ship.

# This allows storing dev secrets encrypted using a hardware private key
# Files affected: .env.encrypted, .sops*, if you run `just decrypt` then 
# also git-ignored .env, which if present will stop asking you for your thumb
# every time you cd into the folder.
#
# See https://sopsy-cli.dev/
brew 'sops'
brew 'age'
brew 'age-plugin-se'
brew 'sopsy'

# Pre-commit hooks to check for secrets
brew 'gitleaks'
brew 'detect-secrets'

# Multi-processor Manager (similar to foreman in ruby)
brew 'mprocs'
brew 'redis'

# Runs the recipes: just test, just lint, just run
brew 'just'

# Github and other utilities
brew 'rbenv'
brew 'gh'
brew 'mermaid-cli'
brew 'circleci'
brew 'git'         # worktrees, branches, the boundary's reflog check
brew 'imagemagick' # Verification::Screenshots recompresses each PNG with `magick`
brew 'jq'          # coverage report_command, and reading traces back (Executor::TRACE_DIR)
brew 'ripgrep'     # what the agents search with
brew 'vips'        # Verification::Screenshots tries `vips pngsave` before `magick`
brew 'just'        # Execution::Checks runs `just <recipe>` where a project has one
