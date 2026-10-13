# frozen_string_literal: true

require "yaml"

module OpenLanes
  module Evals
    # One eval: a fixture plan, the agent given it, the depth asked for, and
    # what the folder must look like afterwards.
    #
    # Validation refuses rather than ignores. A misspelt expectation would
    # otherwise be a check that silently never runs, and an eval that passes
    # because it checked nothing is worse than no eval at all.
    #
    # @!attribute [r] id
    #   @return [String] the file's basename, unique within its agent
    # @!attribute [r] agent
    #   @return [String] an `agents/*.md` name
    # @!attribute [r] depth
    #   @return [Symbol] one of {OpenLanes::Plans::Spec::DEPTHS}
    # @!attribute [r] description
    #   @return [String]
    # @!attribute [r] fixture
    #   @return [OpenLanes::Evals::Case::Fixture]
    # @!attribute [r] expect
    #   @return [Hash{String => Object}] as written, string keys
    # @!attribute [r] path
    #   @return [String] the YAML file
    Case = Data.define(:id, :agent, :depth, :description, :fixture, :expect, :path) do
      # The same case held to another depth's bounds.
      #
      # @param depth [Symbol, String, nil] nil keeps the case's own
      # @return [OpenLanes::Evals::Case]
      def at(depth) = depth.nil? ? self : with(depth: Case.depth!(depth, path))

      # The bounds for {#depth}, or for the one given. A depth the case says
      # nothing about has no bounds, so only the outcome checks apply.
      #
      # @param level [Symbol]
      # @return [Hash{String => Object}]
      def bounds(level = depth) = expect.fetch("depth", {}).fetch(level.to_s, {})

      # @return [String] where this case keeps its recordings
      def dir = path.delete_suffix(File.extname(path))

      # @param kind [Symbol, String] :pass or :fail
      # @return [OpenLanes::Evals::Recording, nil]
      def recording(kind) = Recording.at(File.join(dir, kind.to_s))

      # @return [Array<OpenLanes::Evals::Check>] every check, outcome first
      def checks = Check.for(self)

      # @return [String] `agent/id`, how the CLI names a case
      def to_s = "#{agent}/#{id}"
    end

    class Case
      # What the plan folder, and the repository around it, start as.
      #
      # @!attribute [r] state
      #   @return [Symbol] a status key
      # @!attribute [r] slug
      #   @return [String]
      # @!attribute [r] files
      #   @return [Hash{String => String}] plan-folder file to content
      # @!attribute [r] repo
      #   @return [Hash{String => String}] repository path to content
      Fixture = Data.define(:state, :slug, :files, :repo)

      TOP = %w[id agent depth description fixture expect].freeze
      FIXTURE = %w[state slug files repo].freeze
      EXPECT = %w[state signed files_exist files_absent sections contains excludes changed_paths untouched depth].freeze
      BOUNDS = %w[words count changed_files changed_lines max_seconds max_tokens].freeze

      # What each bound may carry. `words` and `count` take one mapping or a
      # list of them, so a case can bound two sections of one file.
      BOUND_KEYS = {
        "words"         => %w[file section min max],
        "count"         => %w[file section pattern min max],
        "changed_files" => %w[min max],
        "changed_lines" => %w[min max]
      }.freeze

      class << self
        # @param dir [String]
        # @param registry [OpenLanes::Agents::Registry]
        # @return [Array<OpenLanes::Evals::Case>]
        def all(dir, registry:)
          Dir.glob(File.join(File.expand_path(dir), "*", "*.yml")).map { |path| load(path, registry:) }
        end

        # @param path [String]
        # @param registry [OpenLanes::Agents::Registry]
        # @return [OpenLanes::Evals::Case]
        # @raise [OpenLanes::Evals::Invalid]
        def load(path, registry:)
          data = YAML.safe_load_file(path)
          refuse(path, "is not a mapping") unless data.is_a?(Hash)

          from(data, path:, registry:)
        rescue Psych::Exception => e
          refuse(path, "is not valid YAML (#{e.message.lines.first.strip})")
        end

        # @param data [Hash]
        # @param path [String]
        # @param registry [OpenLanes::Agents::Registry]
        # @return [OpenLanes::Evals::Case]
        def from(data, path:, registry:)
          unknown(path, data, TOP, "")
          id = data["id"].to_s
          refuse(path, "id #{id.inspect} must match the file name") unless id == File.basename(path, ".yml")
          agent = data["agent"].to_s
          refuse(path, "names no agent called #{agent.inspect}") unless registry.find(agent)
          refuse(path, "sits under #{File.basename(File.dirname(path))}/ but names #{agent}") unless File.basename(File.dirname(path)) == agent

          new(id:,
            agent:,
            depth:       depth!(data["depth"], path),
            description: data["description"].to_s.strip,
            fixture:     fixture(data["fixture"], path),
            expect:      expectations(data["expect"], path),
            path:)
        end

        # @param value [Object]
        # @param path [String]
        # @return [Symbol]
        def depth!(value, path)
          depth = value.to_s.strip.downcase.to_sym
          return depth if Plans::Spec::DEPTHS.include?(depth)

          refuse(path, "depth #{value.inspect} is not one of #{Plans::Spec::DEPTHS.join(", ")}")
        end

        private

        # @return [OpenLanes::Evals::Case::Fixture]
        def fixture(data, path)
          refuse(path, "has no fixture") unless data.is_a?(Hash)
          unknown(path, data, FIXTURE, "fixture.")
          state = Plans.status(data["state"].to_s) or refuse(path, "fixture.state #{data["state"].inspect} is not a status")
          files = files(data.fetch("files", {}), path, "fixture.files")
          refuse(path, "fixture.files has no spec.md") unless files.key?(Plans::Spec::FILENAME)

          Fixture.new(state:   state.key,
            slug:    data.fetch("slug", File.basename(path, ".yml")).to_s,
            files:,
            repo:    files(data.fetch("repo", {}), path, "fixture.repo"))
        end

        # @return [Hash{String => String}]
        def files(data, path, where)
          refuse(path, "#{where} must map file names to contents") unless data.is_a?(Hash)
          data.to_h { |name, body| [name.to_s, body.to_s] }
        end

        # @return [Hash]
        def expectations(data, path)
          refuse(path, "has no expect") unless data.is_a?(Hash)
          unknown(path, data, EXPECT, "expect.")
          if data.key?("state") && !Plans.status(data["state"].to_s)
            refuse(path, "expect.state #{data["state"].inspect} is not a status")
          end
          depth = data.fetch("depth", {})
          refuse(path, "expect.depth must map fast, medium or deep to bounds") unless depth.is_a?(Hash)
          depth.each do |level, bounds|
            depth!(level, path)
            refuse(path, "expect.depth.#{level} must be a mapping") unless bounds.is_a?(Hash)
            unknown(path, bounds, BOUNDS, "expect.depth.#{level}.")
            bounds.slice(*BOUND_KEYS.keys).each do |name, value|
              Array(value.is_a?(Hash) ? [value] : value).each do |bound|
                refuse(path, "expect.depth.#{level}.#{name} must be a mapping") unless bound.is_a?(Hash)
                unknown(path, bound, BOUND_KEYS.fetch(name), "expect.depth.#{level}.#{name}.")
              end
            end
          end
          data
        end

        # @return [void]
        def unknown(path, data, allowed, prefix)
          extra = data.keys.map(&:to_s) - allowed
          refuse(path, "#{extra.map { |k| "#{prefix}#{k}" }.join(", ")}: unknown, expected one of #{allowed.join(", ")}") unless extra.empty?
        end

        # @return [void] never returns
        def refuse(path, message) = raise(Invalid, "#{path}: #{message}")
      end
    end
  end
end
