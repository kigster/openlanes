# frozen_string_literal: true

module OpenLanes
  module Engine
    # The plans the board keeps as finished: approved or merged, in this run
    # or, for the one that finished last, the run before it. A plan's own
    # `state.json` is the record; this is the board's view of it, guarded
    # because agents' threads settle while the board is drawn.
    class Finishes
      # @param runner [Runner]
      # @param clock [#now]
      def initialize(runner:, clock:)
        @runner = runner
        @clock = clock
        @mutex = Mutex.new
        @finished = carried_over
      end

      # @return [Array<String>] ordinals, in the order they finished
      def ordinals = @mutex.synchronize { @finished.keys }

      # Record an approval or a merge. A dry run writes nothing, but the
      # board still shows it.
      #
      # @param subject [Plans::Subject]
      # @param kind [String] one of {Plans::PlanState::FINISH_KINDS}
      # @return [void]
      def finish(subject, kind)
        at = @clock.now
        kept = @runner.dry_run? ? Plans::PlanState::Finished.new(kind:, at:) : Plans::PlanState.for(subject.feature.path).finish!(kind, at:)
        @mutex.synchronize { @finished[subject.feature.ordinal.to_s] = kept }
      end

      # Read back what {PrOutcomes} wrote: a merge joins the finished plans,
      # a rejection leaves them. Read rather than told, so the watch's one
      # record of it is the only one.
      #
      # @param ordinal [String]
      # @return [void]
      def keep(ordinal)
        subject = Plans::Tree.new(dir: @runner.tree.dir).find(Plans::Ordinal.parse(ordinal)) or return
        finished = Plans::PlanState.for(subject.feature.path).finished
        @mutex.synchronize { finished ? @finished[ordinal] = finished : @finished.delete(ordinal) }
      end

      # An agent is starting on the plan, so it is not finished any more: the
      # board would otherwise show an approved row over a rebuild.
      #
      # @param subject [Plans::Subject]
      # @return [void]
      def unfinish(subject)
        @mutex.synchronize { @finished.delete(subject.feature.ordinal.to_s) }
        Plans::PlanState.for(subject.feature.path).unfinish! unless @runner.dry_run?
      end

      private

      # The one plan that finished last before this engine started, so a
      # restarted board is not empty of what it just did, and not crowded
      # with everything it ever did either.
      #
      # @return [Hash{String => Plans::PlanState::Finished}]
      def carried_over
        latest = @runner.tree.subjects.reject { @runner.foreign?(it) }.filter_map { |subject|
          finished = Plans::PlanState.for(subject.feature.path).finished
          [subject.feature.ordinal.to_s, finished] if finished
        }.max_by { |_, finished| finished.at }
        latest ? [latest].to_h : {}
      end
    end
  end
end
