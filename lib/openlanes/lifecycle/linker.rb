# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # `openlanes link`: hand each unfinished plan whose spec has not answered
    # `depends_on:` to the agent that handles 🔗, one at a time, and read the
    # key back. In the run loop the same agent works a plan once, at 🔗; this
    # is the sweep over the plans that were past 🔗 before it existed, or
    # whose key a person emptied.
    #
    # A plan the sweep links while it sits at 🔗 moves on to 📋, exactly as
    # the run loop would have moved it, so the two never disagree about what
    # a linked plan is called.
    class Linker
      # The state whose agent does the linking. Asking the registry who
      # handles it keeps `agents/*.md` the one place that says.
      STATE = :ready_for_linking

      # Plans that need no link: done, or dropped. A blocked or deferred
      # plan still comes back, and still needs its key when it does.
      FINISHED = (Plans::Dependencies::DONE + %i[discarded retroactive]).freeze

      # What one run did.
      #
      # @!attribute [r] linked
      #   @return [Array<OpenLanes::Plans::Subject>] plans whose key is now written
      # @!attribute [r] unchanged
      #   @return [Array<OpenLanes::Plans::Subject>] on a dry run, the plans
      #     that would be linked. A real run that leaves a key unanswered
      #     reports it under {#failed} instead.
      # @!attribute [r] failed
      #   @return [Array<Array(OpenLanes::Plans::Subject, String)>] each with its note
      # @!attribute [r] cycles
      #   @return [Array<Array<String>>] dependency cycles after the run, among
      #     the plans asked for when `--plans` named some
      Result = Data.define(:linked, :unchanged, :failed, :cycles) do
        # @return [Boolean]
        def ok? = failed.empty? && cycles.empty?
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param registry [OpenLanes::Agents::Registry]
      # @param executor [#call] receives (agent, subject, root:), returns a
      #   result answering `ok` and `note`
      # @param plans [Array<String>, nil] `NNN` or `NNN.MM` tokens; nil for every plan
      # @param root [String] the repository the agent works in
      def initialize(tree:, registry:, executor:, plans: nil, root: nil)
        @tree = tree
        @registry = registry
        @executor = executor
        @plans = plans
        @root = root || File.dirname(tree.dir)
      end

      # @return [OpenLanes::Agents::Agent, nil] who handles {STATE}
      def agent = @registry.for_status(Plans.status(STATE)).first

      # The unfinished plans, narrowed to {#plans}, whose spec has not
      # answered `depends_on:`: no key, or a bare `[]`.
      #
      # @return [Array<OpenLanes::Plans::Subject>]
      def candidates
        @tree.subjects.select do |subject|
          wanted?(subject) && !FINISHED.include?(subject.status.key) && subject.file?(Plans::Spec::FILENAME) &&
            !Plans::Spec.load(subject.feature.path).linked?
        end
      end

      # Every plan is linked before any is advanced, so a key that closes a
      # cycle is seen before its plan moves on to 📋.
      #
      # @param dry_run [Boolean] invoke no agent; every candidate is reported unchanged
      # @return [Result]
      # @raise [OpenLanes::Error] when no agent handles {STATE}
      def call(dry_run: false)
        worker = agent or raise Error, "no agent handles #{Plans.status(STATE)}; is agents/ewoki-linker.md installed?"
        linked = []
        unchanged = []
        failed = []
        candidates.each do |subject|
          next unchanged << subject if dry_run

          outcome = @executor.call(worker, subject, root: @root)
          next failed << [subject, outcome.note.to_s] unless outcome.ok

          spec = Plans::Spec.load(subject.feature.path)
          next failed << [subject, unanswered(spec)] unless spec.linked?

          linked << subject
        end
        dependencies = @tree.reload.dependencies
        failed += unknown(linked, dependencies)
        cycles = scoped(dependencies.cycles, linked)
        on_cycle = cycles.flatten
        linked.reject { on_cycle.include?(it.feature.ordinal.to_s) }.each { advance(it.feature.ordinal) }
        @tree.reload
        Result.new(linked:, unchanged:, failed:, cycles:)
      end

      private

      # 🔗 → 📋, as the run loop does when the agent completes. Anywhere else
      # the folder keeps its name: the key is all this sweep owes it. The
      # folder is found again by ordinal, since a reload may have renamed it.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal]
      # @return [void]
      def advance(ordinal)
        subject = @tree.reload.find(ordinal) or return
        machine = subject.machine
        machine.promote!(:ready_for_planning) if subject.status.key == STATE && machine.may?(:ready_for_planning)
      end

      # An agent that ran cleanly and left the key unanswered is a failure:
      # reported as "No new dependencies found." it read as success, and a
      # spec with malformed frontmatter always ended here.
      #
      # @param spec [OpenLanes::Plans::Spec]
      # @return [String]
      def unanswered(spec)
        ["ran, but spec.md still does not answer depends_on:", *spec.problems].join("; ")
      end

      # A plan number nobody has is an edge `Dependencies#waiting_on` waits
      # on forever.
      #
      # @return [Array<Array(OpenLanes::Plans::Subject, String)>]
      def unknown(linked, dependencies)
        linked.filter_map do |subject|
          missing = dependencies.unknown(subject.feature.ordinal)
          [subject, "depends_on names #{missing.join(", ")}, which no plan here has"] if missing.any?
        end
      end

      # With `--plans`, only a cycle through a plan asked for or linked is
      # this run's business; one among unrelated plans would fail every
      # narrowed run and dry run alike.
      #
      # @return [Array<Array<String>>]
      def scoped(cycles, linked)
        return cycles if @plans.nil? || @plans.empty?

        mine = linked.map { it.feature.ordinal.to_s } + wanted.map(&:to_s)
        cycles.select { |cycle| cycle.intersect?(mine) }
      end

      # @return [Boolean]
      def wanted?(subject)
        return true if @plans.nil? || @plans.empty?

        wanted.include?(subject.feature.ordinal)
      end

      # @return [Array<OpenLanes::Plans::Ordinal>] the plans `--plans` named
      def wanted = Array(@plans).flat_map { |t| t.to_s.split(",") }.filter_map { |t| Plans::Ordinal.parse(t.strip) }
    end
  end
end
