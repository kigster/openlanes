# frozen_string_literal: true

module OpenLanes
  module Setup
    # What a folder already shows of its architecture, read from file names and
    # dependency manifests. Secrets are found by name only: `.env` and its kin
    # are never opened.
    class ArchitectureScan
      # Folders that conventionally hold a monorepo's projects.
      PROJECT_PARENTS = %w[apps packages services].freeze

      # Any of these at the root says the repository is a workspace of projects.
      WORKSPACES = %w[pnpm-workspace.yaml lerna.json nx.json turbo.json go.work].freeze

      # @param root [String]
      def initialize(root)
        @root = root
      end

      # @return [OpenLanes::Setup::Architecture]
      def call
        Architecture.new(merged(dependencies))
      end

      private

      # @return [Hash{Symbol => Array<Symbol>}]
      def merged(names)
        [from_files, from_dependencies(names), layout, { languages:, ci: }].reduce({}) do |all, part|
          all.merge(part) { |_, one, other| one | other }
        end
      end

      # @return [Hash{Symbol => Array<Symbol>}]
      def from_files
        Markers::FILES.to_h do |attribute, values|
          [attribute, values.filter_map { |value, patterns| value if patterns.any? { found?(it) } }]
        end
      end

      # @return [Hash{Symbol => Array<Symbol>}]
      def from_dependencies(names)
        Markers::DEPENDENCIES.to_h do |attribute, values|
          [attribute, values.filter_map { |value, packages| value if packages.intersect?(names) }]
        end
      end

      # @return [Hash{Symbol => Object}]
      def layout
        return { layout: :monorepo, projects: } if monorepo?
        return { layout: :library } if found?("*.gemspec")

        languages.empty? ? {} : { layout: :single_application }
      end

      # @return [Boolean]
      def monorepo? = WORKSPACES.any? { found?(it) } || projects.size > 1

      # @return [Array<String>] folders below the root that hold their own manifest
      def projects
        @projects ||= [".", *PROJECT_PARENTS].flat_map { children(it) }.select { manifest?(it) }.sort
      end

      # @return [Array<String>] one level of folders, relative to the root
      def children(parent)
        base = File.join(@root, parent)
        Dir.children(base).reject { it.start_with?(".") || Markers::NOT_PROJECTS.include?(it) }
           .select { File.directory?(File.join(base, it)) }.map { parent == "." ? it : File.join(parent, it) }
      rescue SystemCallError
        []
      end

      # @return [Boolean]
      def manifest?(folder) = Manifests::FILES.any? { File.file?(File.join(@root, folder, it)) }

      # @return [Array<Symbol>]
      def languages
        @languages ||= ([@root] + projects.map { File.join(@root, it) })
                       .flat_map { StackDetector.new(it).call.languages }.uniq.map(&:to_sym)
      end

      # @return [Array<Symbol>]
      def ci = CiDetector.new(@root).call.map(&:provider)

      # @return [Array<String>] package names from the root's manifests and each project's
      def dependencies = [".", *projects].flat_map { Manifests.new(File.join(@root, it)).names }.uniq

      # @return [Boolean]
      def found?(pattern) = Dir.glob(pattern, File::FNM_DOTMATCH, base: @root).any?
    end
  end
end
