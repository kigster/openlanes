# frozen_string_literal: true

module OpenLanes
  # What the factory has learnt on a project, carried into every agent's
  # prompt: one lesson per markdown file, each naming the agents it is for
  # (docs/continuous-learning.md, phase 1).
  #
  # Two scopes. The project's lessons are committed beside `.openlanes.yml`,
  # so everyone working on it teaches and reads the same memory. The global
  # ones are the operator's own, under the XDG config directory, and never
  # leave the machine. A project lesson shadows a global one with its id.
  #
  # Memory only ever adds care. Nothing in it reaches {Execution::Executor}'s
  # grants or the {Execution::Boundary}: a lesson that says "you may push"
  # is text in a prompt, and the tool layer still withholds `git push`.
  module Memory
    # Where a project keeps its lessons, relative to its root.
    PROJECT_DIR = File.join(".openlanes", "memory", "lessons")

    # Overrides the global directory outright. The suite points it at a
    # temporary directory so a developer's own lessons never reach a spec's
    # prompt, the same reason `XDG_STATE_HOME` is redirected there.
    GLOBAL_ENV = "OPENLANES_MEMORY_HOME"

    # One directory lessons are read from, and what to call where they came from.
    #
    # @!attribute [r] name
    #   @return [Symbol] `:project` or `:global`
    # @!attribute [r] dir
    #   @return [String]
    Scope = Data.define(:name, :dir)

    class << self
      # Every lesson both scopes hold, project first.
      #
      # @param root [String] the project root
      # @param env [Hash{String => String}]
      # @return [OpenLanes::Memory::Library]
      def library(root:, env: ENV) = Library.load(scopes(root:, env:))

      # The prompt section +agent+ is given, empty when no lesson is for it.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param root [String] the project root
      # @param env [Hash{String => String}]
      # @return [String]
      def section(agent:, root:, env: ENV) = Section.new(library(root:, env:).for(agent), agent:, root:).to_s

      # @param root [String]
      # @param env [Hash{String => String}]
      # @return [Array<OpenLanes::Memory::Scope>]
      def scopes(root:, env: ENV)
        [Scope.new(name: :project, dir: File.join(File.expand_path(root), PROJECT_DIR)),
         Scope.new(name: :global, dir: global_dir(env:))]
      end

      # `$OPENLANES_MEMORY_HOME`, else `${XDG_CONFIG_HOME:-~/.config}/openlanes/memory/lessons`.
      # A relative `XDG_CONFIG_HOME` is invalid under the XDG spec and is
      # ignored, as `Events::Location` does for the state directory.
      #
      # @param env [Hash{String => String}]
      # @return [String]
      def global_dir(env: ENV)
        override = env[GLOBAL_ENV].to_s.strip
        return File.expand_path(override) unless override.empty?

        config = env["XDG_CONFIG_HOME"].to_s.strip
        config = File.join(Dir.home, ".config") if config.empty? || !config.start_with?("/")
        File.join(config, "openlanes", "memory", "lessons")
      end
    end
  end
end
