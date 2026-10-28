# frozen_string_literal: true

require_relative "lib/openlanes/version"

Gem::Specification.new do |spec|
  spec.name = "openlanes"
  spec.version = OpenLanes::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "A command-line software factory: brief, spec, plan, build, review, merge"
  spec.description = <<~TEXT
    OpenLanes turns a short feature brief into reviewed pull requests. Specialist
    agents research the brief, write the specification, break it into a plan,
    build the back end and the front end in parallel, review the diff, and run
    the plan's own verification steps. The harness then pushes the branch and
    opens the pull request. You merge.

    Each feature is a folder under .plans, and the folder name is its state. A
    transition renames the directory through git mv. A folder cannot enter a
    phase whose required document is missing. One plan number ties the folder,
    the branch, the pull request title and pull-requests.md together.

    Three lanes choose how far that pipeline runs. Full starts from a brief and
    walks research, specification, planning, implementation, review and
    verification. Plan starts from a specification you already trust. Quick
    hands one mechanical change to a single builder and a reviewer.

    Several plans run at once, each in its own git worktree, coordinated through
    Redis. A second checkout on the same Redis and the same GitHub repository
    joins the same board. openlanes start opens a local control room that shows
    every plan, the agent on it, and token use. From that page you answer an
    agent that has stopped to ask a question, or start another idea.

    Agents write code, tests and plan documents. They do not commit, push or
    merge. After every run the harness checks that HEAD did not move and nothing
    was pushed, then publishes the branch itself. Claude Code is the default
    adapter. Codex, Pi and Grok can stand in for a phase. The same plans export one
    way to Linear, and the agents ship with deterministic evals.

    The gem installs three names for one executable: openlanes, ol and lanes.
  TEXT
  spec.homepage = "https://github.com/kigster/openlanes"

  spec.required_ruby_version = ">= 4" # rubocop:disable Gemspec/RequiredRubyVersion -- the floor users get, not the Ruby the cops lint for

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Globbed rather than taken from `git ls-files`, so building the gem does not
  # require a git checkout — the same reason the executables resolve their own
  # bundle rather than trusting the caller's working directory.
  spec.files = Dir.chdir(__dir__) do
    # web/dist is the built page the API server serves; board.json is what
    # `openlanes web --demo` replays.
    # Source maps stay out: they double the page's size for nobody who installs it.
    globbed = Dir.glob(["*.gemspec", "lib/**/*.rb", "agents/*.md", "schemas/*.json",
                        "evals/cases/**/*", "skills/**/*",
                        "exe/*", "libexec/*", "web/dist/**/*", "web/src/api/fixtures/board.json",
                        "Brewfile",
                        "bin/ol-tee"])
    globbed.select { |f| File.file?(f) && !f.end_with?(".map") }
  end

  # A gem built without the page installs a control room that serves a 404.
  # Only `gem build` is stopped (which `rake build` and `just publish` run):
  # Bundler, rspec and rubocop load this file too, in checkouts that have
  # never run npm. `abort` rather than `raise`, because Gem::Specification.load
  # swallows a StandardError into a warning and a puzzling "not found".
  building = File.basename($PROGRAM_NAME) == "gem" && ARGV.first == "build"
  if building && !File.file?(File.join(__dir__, "web", "dist", "index.html"))
    abort "openlanes.gemspec: web/dist/index.html is missing, so the gem would ship without its control room.\n" \
          "Build the page first: just web-build (or: cd web && npm ci && npm run build)."
  end

  spec.bindir = "exe"
  # `ol` and `lanes` are symlinks to `openlanes` in the checkout; named here
  # so that installing the gem writes all three, rather than only the one git
  # recorded.
  spec.executables = %w[openlanes ol lanes]
  spec.require_paths = ["lib"]

  spec.add_dependency "aasm"
  spec.add_dependency "concurrent-ruby"
  spec.add_dependency "dry-cli"
  spec.add_dependency "dry-cli-autocomplete", "~> 0.5"
  # 0.5.1 is the first release whose help screen survives `example [""]`,
  # which four commands here declare.
  spec.add_dependency "dry-cli-help", ">= 0.5.1", "< 0.6"
  spec.add_dependency "dry-cli-ui", "~> 0.5"
  spec.add_dependency "dry-inflector"
  spec.add_dependency "dry-monads"
  # Wires the application (A1): components from lib/ through the Zeitwerk
  # loader below, collaborators by Deps[...], providers for the outside world.
  spec.add_dependency "dry-system", "~> 1.2"
  spec.add_dependency "fuzzy-string-match"
  spec.add_dependency "inquirex-llm", "~> 0.12"
  # Opens the control room in the browser when `openlanes run` starts the API server.
  spec.add_dependency "launchy", "~> 3.1"
  spec.add_dependency "parallel"
  spec.add_dependency "pastel"
  # The API server (plan 004, W3, W7): Sinatra on a threaded Puma, so SSE streams hold a thread each.
  spec.add_dependency "puma", ">= 6.4"
  spec.add_dependency "rack-protection", "~> 4.2"
  spec.add_dependency "rackup", "~> 2.1"
  # The live run (plan 004) lives in Redis: board and command streams, plan claims.
  spec.add_dependency "redis-client", "~> 0.31"
  spec.add_dependency "agent-lock"
  spec.add_dependency "semantic_logger", "~> 5.1"
  spec.add_dependency "sinatra", "~> 4.2"
  spec.add_dependency "tty-box"
  spec.add_dependency "tty-command"
  spec.add_dependency "tty-cursor"
  spec.add_dependency "tty-prompt"
  spec.add_dependency "tty-screen"
  spec.add_dependency "unicode-display_width"
  spec.add_dependency "zeitwerk"
end
