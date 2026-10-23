# frozen_string_literal: true

require "json"

module OpenLanes
  module Setup
    # Reads the marker files a folder already holds and names its stack.
    #
    # It never guesses between two languages: a folder with a Gemfile and a
    # go.mod is reported as mixed, with no stack, and the interview asks.
    class StackDetector
      # What one folder looks like.
      #
      # @!attribute [r] languages
      #   @return [Array<String>] every language a marker named, in table order
      # @!attribute [r] stack
      #   @return [OpenLanes::Setup::Stack, nil] nil when no language, or more than one
      # @!attribute [r] hints
      #   @return [Array<String>] files that say something about deployment or
      #     versions but name no language: Dockerfile, .tool-versions
      Detection = Data.define(:languages, :stack, :hints) do
        # @return [Boolean] whether two or more languages were found
        def mixed? = languages.size > 1
      end

      # Marker file → language. The first that exists names it.
      LANGUAGES = {
        "ruby"   => %w[Gemfile],
        "node"   => %w[package.json],
        "go"     => %w[go.mod],
        "rust"   => %w[Cargo.toml],
        "elixir" => %w[mix.exs],
        "python" => %w[pyproject.toml requirements.txt]
      }.freeze

      # Files that hint at deployment or versions only.
      HINTS = %w[Dockerfile .tool-versions].freeze

      # Frameworks a Gemfile.lock may name.
      RUBY_FRAMEWORKS = %w[rails sinatra].freeze

      # package.json dependencies that are frameworks; react is a front end.
      NODE_FRAMEWORKS = %w[next astro vite].freeze

      # Python frameworks named in pyproject.toml or requirements.txt.
      PYTHON_FRAMEWORKS = %w[fastapi django].freeze

      # @param root [String] the folder to read
      def initialize(root)
        @root = root
      end

      # @return [OpenLanes::Setup::StackDetector::Detection]
      def call
        languages = LANGUAGES.filter_map { |language, markers| language if markers.any? { file?(it) } }
        stack = languages.one? ? refine(languages.first) : nil
        Detection.new(languages:, stack:, hints: HINTS.select { file?(it) })
      end

      private

      # @return [OpenLanes::Setup::Stack]
      def refine(language)
        case language
        when "ruby" then Stack.new(language:, frameworks: ruby_frameworks)
        when "node" then node(language)
        when "python" then Stack.new(language:, frameworks: python_frameworks)
        else Stack.new(language:)
        end
      end

      # @return [Array<String>]
      def ruby_frameworks
        lock = read("Gemfile.lock")
        RUBY_FRAMEWORKS.select { lock.match?(/^\s+#{it} \(/) }
      end

      # @return [OpenLanes::Setup::Stack]
      def node(language)
        package = JSON.parse(read("package.json")) rescue {} # rubocop:disable Style/RescueModifier
        package = {} unless package.is_a?(Hash)
        deps = %w[dependencies devDependencies].flat_map { (package[it] || {}).keys }
        frameworks = NODE_FRAMEWORKS.select { deps.include?(it) }
        frameworks |= %w[astro] if glob?("astro.config.*")
        frameworks |= %w[vite] if glob?("vite.config.*")
        Stack.new(language:, frameworks:, front_end: ("react" if deps.include?("react")))
      end

      # @return [Array<String>]
      def python_frameworks
        text = read("pyproject.toml") + read("requirements.txt")
        PYTHON_FRAMEWORKS.select { text.match?(/\b#{it}\b/i) }
      end

      def file?(name) = File.exist?(File.join(@root, name))
      def glob?(pattern) = Dir.glob(File.join(@root, pattern)).any?
      def read(name) = file?(name) ? File.read(File.join(@root, name), encoding: "UTF-8") : ""
    end
  end
end
