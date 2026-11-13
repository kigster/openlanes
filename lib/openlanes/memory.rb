# frozen_string_literal: true

module OpenLanes
  # What the factory has learnt on a project, carried into every agent's
  # prompt: one lesson per markdown file, each naming the agents it is for
  # (docs/continuous-learning.md, phase 1).
  #
  # Two scopes. The project's lessons are committed beside `.openlanes.yml`,
  # so everyone working on it teaches and reads the same memory, and they
  # count only once merged: they are read from the default branch, never
  # from a checkout an agent can write to. The global
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

    class << self
      # The lessons one run tells its agents, read once and kept for the run.
      #
      # Project lessons come from the commit `origin/<default branch>` points
      # at when the run starts: what a person merged, not what an agent wrote
      # into a checkout since. A repository with no such ref has no project
      # lessons, and says so in +problems+, rather than falling back to the
      # working tree it was built not to trust.
      #
      # @param root [String] the project root
      # @param env [Hash{String => String}]
      # @return [OpenLanes::Memory::Library]
      def library(root:, env: ENV)
        project = reviewed(root:)
        library = Library.load([project, global(env:)].compact)
        return library if project

        library.with(problems: ["project lessons skipped: no #{ref(root)} to read reviewed ones from", *library.problems])
      end

      # The prompt section +agent+ is given, empty when no lesson is for it.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param library [OpenLanes::Memory::Library] as {library} read it
      # @return [String]
      def section(agent:, library:) = Section.new(library.for(agent), agent:).to_s

      # The project's lessons on the default branch, at the commit it points at now.
      #
      # @param root [String]
      # @return [OpenLanes::Memory::Committed, nil] nil when the ref is unknown
      def reviewed(root:)
        Committed.at(name: :project, root: File.expand_path(root), ref: ref(root), dir: PROJECT_DIR)
      end

      # @param root [String]
      # @return [String] e.g. `origin/main`
      def ref(root) = "origin/#{Vcs.default_branch(File.expand_path(root))}"

      # @param env [Hash{String => String}]
      # @return [OpenLanes::Memory::Folder]
      def global(env: ENV) = Folder.new(name: :global, dir: global_dir(env:))

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
