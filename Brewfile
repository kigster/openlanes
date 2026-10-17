# frozen_string_literal: true

# vim: ft=ruby
#
# What openlanes shells out to at run time, read from the code rather than
# guessed. `openlanes setup` runs `brew bundle --no-upgrade` on this file, so
# it ships in the gem. A contributor's extras live in `Brewfile.dev`, which
# `bin/setup` bundles too and the gem does not ship.

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

# Runs the recipes: just test, just lint, just start
brew 'just'
