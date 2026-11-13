# frozen_string_literal: true

require "open3"

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

    # Everything openlanes keeps with a project. All of it is committed:
    # nothing here is ignored, and nothing a running process owns lives here.
    ROOT_DIR = ".openlanes"

    # Where proposed lessons wait, relative to the project root.
    INBOX_DIR = File.join(ROOT_DIR, "memory", "inbox")

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

      # @param root [String] the project root
      # @return [OpenLanes::Memory::Inbox] the candidates waiting in this checkout
      def inbox(root:) = Inbox.new(dir: File.join(File.expand_path(root), INBOX_DIR))

      # @param root [String] the project root
      # @return [OpenLanes::Memory::Promotion]
      def promotion(root:)
        Promotion.new(inbox: inbox(root:), lessons_dir: File.join(File.expand_path(root), PROJECT_DIR))
      end

      # @param root [String] the project root
      # @param agent [OpenLanes::Agents::Agent]
      # @param dry_run [Boolean] true invokes no agent
      # @return [OpenLanes::Memory::Curation]
      def curation(root:, agent:, dry_run: false)
        Curation.new(executor: Execution.executor(root: File.expand_path(root), dry_run:), agent:, root: File.expand_path(root))
      end

      # Read the curator's output for one plan into the inbox.
      #
      # @param text [String] what the curator said
      # @param plan [String] the ordinal it was looking at
      # @param root [String] the project root
      # @return [Array<OpenLanes::Memory::Inbox::Outcome>] one per proposal line, malformed ones dropped with a reason
      def propose(text, plan:, root:)
        box = inbox(root:)
        Proposal.scan(text).map do |read|
          next box.add(read, plan:) if read.is_a?(Proposal)

          Inbox::Outcome.new(slug: nil, status: :dropped, reason: read.reason)
        end
      end

      # @param root [String] the project root
      # @return [Hash{String => Array<OpenLanes::Memory::Secrets::Finding>}] files under `.openlanes/` holding a secret
      def secrets(root:) = Secrets.scan_tree(File.join(File.expand_path(root), ROOT_DIR))

      # Files under `.openlanes/` that git ignores. The folder travels with
      # the project whole: an ignored file there is memory one machine has
      # and the next clone does not.
      #
      # @param root [String] the project root
      # @return [Array<String>] paths relative to the root; empty outside a repository
      def ignored(root:)
        out, status = Open3.capture2e("git", "-C", File.expand_path(root), "ls-files", "--others", "--ignored", "--exclude-standard", "--", ROOT_DIR)
        status.success? ? out.lines.map(&:chomp).reject(&:empty?) : []
      rescue SystemCallError
        []
      end

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
