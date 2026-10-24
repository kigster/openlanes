 # rubocop:disable Naming/FileName,Lint/MissingCopEnableDirective
 # vim: ft=ruby # rubocop:disable Layout/CommentIndentation

# The one Brewfile: what openlanes shells out to at run time, read from the
# code rather than guessed, and the tools a contributor works with. It ships
# in the gem, and both `openlanes setup` and `bin/setup` run
# `brew bundle --no-upgrade` on it.

# sopsy is not in homebrew-core; without its tap `brew bundle` fails outright.
tap 'kigster/tap'

# This allows storing dev secrets encrypted using a hardware private key
# Files affected: .env.encrypted, .sops*, if you run `just decrypt` then
# also git-ignored .env, which if present will stop asking you for your thumb
# every time you cd into the folder.
#
# See https://sopsy-cli.dev/
brew 'sops'
brew 'age'
brew 'age-plugin-se' if OS.mac? # the Secure Enclave plugin exists only on macOS
brew 'kigster/tap/sopsy'

# Pre-commit hooks to check for secrets
brew 'gitleaks'
brew 'detect-secrets'
brew 'lefthook'

# Multi-processor Manager (similar to foreman in ruby)
brew 'mprocs'
brew 'redis'

# Github and other utilities
brew 'rbenv'
brew 'gh'
brew 'mermaid-cli'
brew 'circleci'
brew 'gawk'        # bin/ol-tee stamps each line with strftime, which BSD awk lacks
brew 'git'         # worktrees, branches, the boundary's reflog check
brew 'imagemagick' # Verification::Screenshots recompresses each PNG with `magick`
brew 'jq'          # coverage report_command, and reading traces back (Executor::TRACE_DIR)
brew 'ripgrep'     # what the agents search with
brew 'vips'        # Verification::Screenshots tries `vips pngsave` before `magick`
brew 'just'        # runs the recipes, and Execution::Checks runs `just <recipe>` where a project has one
