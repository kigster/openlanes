# frozen_string_literal: true

require "erb"
require "fileutils"

module OpenLanes
  module Setup
    # Writes one CI config that runs the project's own lint and test
    # commands (M21). It never overwrites: a file already there is somebody's
    # CI, and replacing it is not a scaffold's call.
    class CiScaffold
      # What happened: where the file is, whether this call wrote it, and
      # when it did not because nothing would be checked, why.
      Result = Data.define(:path, :written, :skipped) do
        def initialize(path:, written:, skipped: nil) = super
      end

      # Said when no lint or test command is known. A CI that only checks
      # out the code passes every time, and a harness that gates on CI
      # would read that as green.
      NOTHING_TO_RUN = "no lint or test command is known for this stack, so no CI file was written"

      # Provider → the file it reads, relative to the root.
      PATHS = {
        github_actions: ".github/workflows/ci.yml",
        circleci:       ".circleci/config.yml",
        jenkins:        "Jenkinsfile"
      }.freeze

      # Provider → template under templates/.
      TEMPLATES = {
        github_actions: "github_actions.yml.erb",
        circleci:       "circleci.yml.erb",
        jenkins:        "Jenkinsfile.erb"
      }.freeze

      # Language → [lint, test], when the justfile names neither recipe.
      COMMANDS = {
        "ruby"   => ["bundle exec rubocop", "bundle exec rspec"],
        "node"   => ["npm run lint", "npm test"],
        "go"     => ["go vet ./...", "go test ./..."],
        "rust"   => ["cargo clippy -- -D warnings", "cargo test"],
        "elixir" => ["mix credo", "mix test"],
        "python" => ["ruff check .", "pytest"]
      }.freeze

      # Language → the step that installs what {COMMANDS} runs. Go and Rust
      # need none: their toolchains fetch dependencies, and the rust image
      # ships clippy. Python installs the project, else its requirements.
      INSTALLS = {
        "ruby"   => "bundle install",
        "node"   => "npm ci",
        "elixir" => "mix local.hex --force && mix deps.get"
      }.freeze

      # Names a person or a model may give a language → the key the tables use.
      LANGUAGES = { "javascript" => "node", "typescript" => "node", "js" => "node", "ts" => "node",
                    "nodejs" => "node", "node.js" => "node", "golang" => "go", "py" => "python",
                    "rb" => "ruby" }.freeze

      # Installs `just` into /usr/local/bin. GitHub Actions has setup-just;
      # CircleCI and Jenkins run in a bare language image that lacks it.
      # Jenkins runs its docker agent as the jenkins user, who cannot write
      # /usr/local/bin, so its template installs into the workspace instead.
      JUST_INSTALL = "curl --proto =https --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin"

      # The image when the language is unknown: Ubuntu with curl and git,
      # which a bare ubuntu image lacks and checkout needs.
      FALLBACK_IMAGE = "buildpack-deps:noble"

      # Container image per language, for the providers that run in one.
      IMAGES = {
        "ruby"   => "ruby:3.4",
        "node"   => "node:22",
        "go"     => "golang:1.23",
        "rust"   => "rust:1",
        "elixir" => "elixir:1.17",
        "python" => "python:3.12"
      }.freeze

      TEMPLATE_DIR = File.join(__dir__, "templates")

      # @return [Array<String>] the providers this can write a file for
      def self.providers = PATHS.keys

      # @param root [String]
      # @param provider [Symbol] one of {PATHS}'s keys
      # @param stack [OpenLanes::Setup::Stack, nil]
      # @raise [ArgumentError] for a provider this cannot scaffold
      def initialize(root, provider:, stack:)
        raise ArgumentError, "no CI scaffold for #{provider.inspect}" unless PATHS.key?(provider)

        @root = root
        @provider = provider
        @stack = stack
      end

      # @return [String] the file, relative to the root
      def path = PATHS.fetch(@provider)

      # @return [Array<String>] the lint command, then the test command;
      #   either may be absent when nothing names it
      def commands
        return %w[lint test].map { "just #{it}" } if %w[lint test].all? { recipe?(it) }

        COMMANDS.fetch(language, [])
      end

      # @return [Boolean] whether there is anything for the CI to check
      def runnable? = !commands.empty?

      # @return [String] the stack's language as the tables key it, so
      #   "Ruby" or "TypeScript" from an answer still finds its commands
      def language
        word = @stack&.language.to_s.strip.downcase
        LANGUAGES.fetch(word, word)
      end

      # @return [String, nil] the dependency install step, nil when none
      def install
        return INSTALLS[language] unless language == "python"

        file?("pyproject.toml") ? "pip install -e . ruff pytest" : "pip install -r requirements.txt ruff pytest"
      end

      # @return [String] the file's contents
      def render
        lint, test = commands
        image = IMAGES.fetch(language, FALLBACK_IMAGE)
        just = commands.first.to_s.start_with?("just ")
        ERB.new(File.read(File.join(TEMPLATE_DIR, TEMPLATES.fetch(@provider))), trim_mode: "-")
           .result_with_hash(lint:, test:, image:, just:, install:, just_install: JUST_INSTALL)
      end

      # @param dry_run [Boolean] report what would be written, write nothing
      # @return [OpenLanes::Setup::CiScaffold::Result]
      def call(dry_run: false)
        target = File.join(@root, path)
        return Result.new(path:, written: false, skipped: NOTHING_TO_RUN) unless runnable?
        return Result.new(path:, written: false) if File.exist?(target) || dry_run

        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, render)
        Result.new(path:, written: true)
      end

      private

      # @return [Boolean] whether the justfile defines the recipe
      # The name must end at whitespace or the colon, so `test-unit:` is not
      # read as a `test` recipe.
      def recipe?(name)
        file = %w[justfile Justfile .justfile].map { File.join(@root, it) }.find { File.file?(it) }
        !file.nil? && File.read(file).match?(/^#{name}(?=[\s:])[^:=]*:(?!=)/)
      end

      def file?(name) = File.file?(File.join(@root, name))
    end
  end
end
