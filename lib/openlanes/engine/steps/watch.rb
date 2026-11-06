# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # The pull requests a person may merge, close or reject, in every merge
      # mode (M4, #171). The `gh` call runs on a thread
      # of its own, so a slow GitHub never stretches the tick; its outcomes
      # are applied on the first tick after it returns, where every other
      # rename happens.
      class Watch
        # @param context [Context]
        # @param watch [PrWatch]
        # @param finishes [Finishes] reads back what a merge or rejection wrote
        # @param state [StateFile, nil] told which pull requests are waiting
        def initialize(context, watch:, finishes:, state:)
          @context = context
          @watch = watch
          @finishes = finishes
          @state = state
          @thread = nil
          @waiting_on = {}
        end

        # @return [Hash{String => Array}] each plan's pull requests still open
        attr_reader :waiting_on

        # @return [Thread, nil] the poll under way, once it has ended
        def join = @thread&.join

        # @return [void]
        def call
          if @thread && !@thread.alive?
            settle(@thread.value)
            @thread = nil
          end
          return if @thread || !@watch.due?

          subjects = watched
          @thread = Thread.new { poll(subjects) }
        end

        private

        # @return [Array<Plans::Subject>] plans whose pull requests to ask about
        def watched
          busy = @context.busy.call
          runner = @context.runner
          @removed = runner.removed_in_scope.map { it.feature.ordinal.to_s }
          (runner.in_scope + runner.removed_in_scope).reject { busy.include?(it.feature.ordinal.to_s) }
        end

        # StandardError, not only OpenLanes::Error: `#value` re-raises
        # whatever ended the thread, so a stray JSON::ParserError or Errno
        # from `gh` would otherwise end the whole run on the next tick.
        #
        # @return [Array<PrWatch::Outcome>, nil] nil when the poll failed
        def poll(subjects)
          @watch.poll(subjects)
        rescue StandardError => e
          UI.log("pull requests unwatched this time: #{Steps.first_line(e)}", level: :warn)
          nil
        end

        # @param outcomes [Array<PrWatch::Outcome>, nil]
        # @return [void]
        def settle(outcomes)
          return if outcomes.nil?

          # Nothing waits on a plan that left the list.
          @waiting_on = outcomes.select { it.kind == :waiting && !Array(@removed).include?(it.plan) }.group_by(&:plan).transform_values { it.map(&:pr) }
          effects = effects_for(@context.runner)
          outcomes.each { apply(effects, it) }
          @state&.waiting_on = @waiting_on
        end

        # Every agent defined, not this run's roster: the mail waits in the
        # plan folder for whichever run next starts the builders, and a run
        # typed with `--agent staff-reviewer` must not lose it.
        #
        # @return [PrOutcomes]
        def effects_for(runner)
          PrOutcomes.new(tree_dir: runner.tree.dir, agents: Agents::Registry.new(dir: runner.agents.dir), events: runner.events)
        end

        # @return [void]
        def apply(effects, outcome)
          return if outcome.kind == :waiting || @context.busy.call.include?(outcome.plan) || recorded?(outcome)

          applied = effects.apply(outcome) or return
          @context.reopen.call(applied.plan) if applied.to
          @finishes.keep(applied.plan)
          say(applied)
          @context.wake.call
        end

        # Whether the folder already records this merge or close. {Merging}
        # applies a 🏁 plan's merge itself, in every mode, and may do so
        # between the poll that still read the row as open and the tick that
        # settles it. {PrOutcomes#apply} would change nothing on disk the
        # second time, but it still answers, so the merge was logged twice
        # and kept as a finish this watch never saw. A rejection is never
        # skipped here: its row stays open, and {PrOutcomes} owns that check.
        #
        # @param outcome [PrWatch::Outcome]
        # @return [Boolean]
        def recorded?(outcome)
          return false unless %i[merged closed].include?(outcome.kind)

          row = rows(outcome.plan).find { it.number.to_s.delete("#").to_i == outcome.pr }
          !row.nil? && !row.open?
        end

        # Read afresh, removed plans included: the folder may have moved
        # since the poll began.
        #
        # @param ordinal [String]
        # @return [Array<Plans::PullRequest>]
        def rows(ordinal)
          Plans::Tree.new(dir: @context.runner.tree.dir).everything.find(ordinal)&.pull_requests || []
        end

        # @return [void]
        def say(applied)
          moved = " → #{Plans::STATUS_BY_KEY.fetch(applied.to)}" if applied.to
          UI.log("#{applied.plan}: #{applied.note}#{moved}")
        end
      end
    end
  end
end
