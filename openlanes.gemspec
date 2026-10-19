# frozen_string_literal: true

require_relative "lib/openlanes/version"

Gem::Specification.new do |spec|
  spec.name = "openlanes"
  spec.version = OpenLanes::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "Agentic specification-driven development: spec, plan, build, review"
  spec.description = <<~TEXT
    Keeps a project's specifications, plans and pull requests joined up, and
    drives specialist agents over them in parallel. A feature's state is its
    folder name under .plans, so a transition renames a directory rather than
    updating a row, and nothing can claim a phase whose document is missing.
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
    globbed = Dir.glob(["*.gemspec", "lib/**/*.rb", "agents/*.md", "schemas/*.json", "evals/cases/**/*", "skills/**/*",
                        "exe/*", "web/dist/**/*", "web/src/api/fixtures/board.json", "Brewfile"])
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
  spec.add_dependency "semantic_logger", "~> 5.1"
  spec.add_dependency "sinatra", "~> 4.2"
  spec.add_dependency "agent-lock"
  spec.add_dependency "tty-box"
  spec.add_dependency "tty-command"
  spec.add_dependency "tty-cursor"
  spec.add_dependency "tty-prompt"
  spec.add_dependency "tty-screen"
  spec.add_dependency "unicode-display_width"
  spec.add_dependency "zeitwerk"
  spec.add_dependency "newrelic_rpm"
  spec.add_dependency "newrelic-infinite_tracing"
end
