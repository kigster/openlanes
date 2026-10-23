# frozen_string_literal: true

require "erb"
require "fileutils"

module OpenLanes
  module Setup
    # Writes one CI config that runs the project's own lint and test
    # commands (M21). It never overwrites: a file already there is somebody's
    # CI, and replacing it is not a scaffold's call.
    class CiScaffold
      # What happened: where the file is, and whether this call wrote it.
      Result = Data.define(:path, :written)

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

        COMMANDS.fetch(@stack&.language.to_s, [])
      end

      # @return [String] the file's contents
      def render
        lint, test = commands
        image = IMAGES.fetch(@stack&.language.to_s, "ubuntu:24.04")
        just = commands.first.to_s.start_with?("just ")
        ERB.new(File.read(File.join(TEMPLATE_DIR, TEMPLATES.fetch(@provider))), trim_mode: "-")
           .result_with_hash(lint:, test:, image:, just:)
      end

      # @param dry_run [Boolean] report what would be written, write nothing
      # @return [OpenLanes::Setup::CiScaffold::Result]
      def call(dry_run: false)
        target = File.join(@root, path)
        return Result.new(path:, written: false) if File.exist?(target) || dry_run

        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, render)
        Result.new(path:, written: true)
      end

      private

      # @return [Boolean] whether the justfile defines the recipe
      def recipe?(name)
        file = %w[justfile Justfile .justfile].map { File.join(@root, it) }.find { File.file?(it) }
        !file.nil? && File.read(file).match?(/^#{name}\b[^:=]*:(?!=)/)
      end
    end
  end
end
