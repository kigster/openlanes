# Tell 'just' to run bash, source our setup script, then execute the recipe
set shell := ["bash", "-c"]

version := `grep VERSION lib/openlanes/version.rb | awk '{print $3}' | tr -d '"' | tr -d '\n'`
repo := 'git@github.com:kigster/openlanes.git'

rbenv := 'eval "$(rbenv init - bash 2>/dev/null || true)"; bundle exec '

# 1Password secret reference for the RubyGems TOTP, and the full path to `op`
# because a recipe does not inherit an interactive shell's PATH.
# The account is NOT named here: it is a private 1Password address and this
# file is public. `op` reads it from OP_ACCOUNT, exported by the ecosystem
# root's .envrc, which lives outside every repo. Two accounts are
# registered and only one holds the open-source-repos vault, so without
# OP_ACCOUNT the read can resolve against the wrong one, return nothing,
# and publish silently falls back to prompting mid-release.
op := '/opt/homebrew/bin/op'
otp_ref := 'op://open-source-repos/ruby-gems/one-time password?attribute=otp'

gem_name := 'openlanes'
gem_file := 'pkg/' + gem_name + '-' + version + '.gem'
gem_url := 'https://rubygems.org/gems/' + gem_name

[no-exit-message]
recipes:
    just --choose

# Start both the engine and control room with 4 concurrent workers
run:
    @mprocs

# Sync all dependencies
install:
    bin/setup

# Sync dependencies and build the page the gem ships (web/dist)
build: install web-build

# Install the page's dependencies
web-install:
    cd web && npm ci

# Build the page into web/dist, which the gem ships and the API server serves
web-build:
    cd web && npm run build

# The page's dev server beside `openlanes web --demo`; Vite proxies /api to it
web-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(rbenv init - bash 2>/dev/null || true)"
    bundle exec exe/openlanes web --demo --no-open &
    trap 'kill %1 2>/dev/null || true' EXIT
    cd web && npm run dev

# The API server over the demo engine, serving the built page on 127.0.0.1:11000
web-demo *args:
    {{ rbenv }} exe/openlanes web --demo {{ args }}

# Cypress against two demo servers, the second as demo@second-machine; run `just web-build` first
web-e2e:
    bin/web-e2e

# The Preview tab's Cypress run: a real app runner beside `openlanes web --demo` on 11050; run `just web-build` first
preview-e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(rbenv init - bash 2>/dev/null || true)"
    export E2E_REDIS_URL="${E2E_REDIS_URL:-redis://localhost:6379/13}"
    bin/require-local-redis "$E2E_REDIS_URL"
    export PREVIEW_E2E_PORT="${PREVIEW_E2E_PORT:-11050}"
    export OPENLANES_PORTS_FILE="$(mktemp -d)/ports.json"
    bundle exec exe/openlanes web --demo --no-open --port "$PREVIEW_E2E_PORT" --redis-url "$E2E_REDIS_URL" &
    trap 'kill %1 2>/dev/null || true' EXIT
    until curl -sf "http://127.0.0.1:$PREVIEW_E2E_PORT/healthz" >/dev/null; do sleep 0.2; done
    cd web && npx cypress run --config-file cypress.preview.config.ts

# Real agents build a tic-tac-toe page through `openlanes start`; spends tokens, needs OPENLANES_FACTORY_E2E=1
factory-e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${OPENLANES_FACTORY_E2E:-}" != "1" ]]; then
        echo "factory-e2e runs real agents and spends real tokens; run it as OPENLANES_FACTORY_E2E=1 just factory-e2e" >&2
        exit 64
    fi
    (cd web && npm run build)
    unset BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB
    eval "$(rbenv init - bash 2>/dev/null || true)"
    bin/factory-e2e

# Real agents work three quick-lane plans while /concurrency, /stop and /restart are typed into the copilot; spends tokens, needs OPENLANES_LANES_E2E=1
lanes-e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${OPENLANES_LANES_E2E:-}" != "1" ]]; then
        echo "lanes-e2e runs real agents and spends real tokens; run it as OPENLANES_LANES_E2E=1 just lanes-e2e" >&2
        exit 64
    fi
    (cd web && npm run build)
    unset BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB
    eval "$(rbenv init - bash 2>/dev/null || true)"
    bin/lanes-e2e

# Lint, type-check and unit-test the page, with coverage
web-test:
    cd web && npm run lint && npm run typecheck && npm run coverage

# rubocop
lint:
    {{ rbenv }} rubocop

# Fix style with rubocop, then format the markdown
format:
    {{ rbenv }} rubocop -a
    /usr/bin/find . -name '*.md' -exec mdformat --wrap no {} \; -print

update-workflow:
    bundle exec openlanes docs -o docs/WORKFLOW.md

# Run all the tests
test *args:
    export ENVIRONMENT=test; {{ rbenv }} rspec {{ args }}

# Score every agent's eval cases against their recordings
eval *args:
    {{ rbenv }} exe/openlanes eval {{ args }}

# Run tests with coverage
test-coverage *args:
    export ENVIRONMENT=test; export COVERAGE=true; {{ rbenv }} rspec {{ args }}

ci: lint test-coverage

alias check-all := ci

clean:
    #!/usr/bin/env bash
    @find . -name .DS_Store -delete -print || true
    @rm -rf tmp/*

# Run all lefthook pre-commit hooks
lefthook:
    {{ rbenv }} lefthook run pre-commit --all-files

# Print current gem version
version:
    @echo "{{ version }}"

# Clobber
clobber:
    {{ rbenv }} rake clobber

# Generate documentation
doc:
    #!/usr/bin/env bash
    {{ rbenv }} rake doc

# `gem push` rather than `rake release`: release also guards the tree, tags and
# pushes git — which `just release` does deliberately and separately — and it
# gives no way to pass a 2FA code, so it always stopped to prompt.
#
# The code comes from 1Password unless one is passed in:
#
#   just publish            # read the code from 1Password
#   just publish 123456     # use this code
#
# `just publish-all` in openlanes-tools passes one, because a TOTP is single-use:
# four gems reading the same 30-second window would have the second push
# rejected as a replay.
#
# Build the .gem and push it to RubyGems, non-interactively
publish otp="": build
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(rbenv init - bash 2>/dev/null || true)"

    mkdir -p pkg
    gem build {{ gem_name }}.gemspec --output "{{ gem_file }}"

    # `|| true` is load-bearing: under `set -e` a failed `op read` — not signed
    # in to 1Password, item renamed, op not installed — would abort the recipe
    # before the prompting fallback below could run.
    otp="{{ otp }}"
    [[ -n "${otp}" ]] || otp=$({{ op }} read "{{ otp_ref }}" 2>/dev/null || true)

    if [[ -n "${otp}" ]]; then
        {{ rbenv }} gem push "{{ gem_file }}" --otp "${otp}"
    else
        echo "rubygems: no OTP available — gem push will prompt if 2FA is required."
        {{ rbenv }} gem push "{{ gem_file }}" --no-document
    fi

    # Only reachable when the push succeeded: `set -e` aborts the recipe on a
    # non-zero `gem push`, so the page never opens for a release that failed.
    echo "published {{ gem_name }} {{ version }} → {{ gem_url }}"
    open "{{ gem_url }}" 2>/dev/null || xdg-open "{{ gem_url }}" 2>/dev/null || true

# Tag v{{ version }}, publish the GH release, & refresh the Homebrew tap.
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
