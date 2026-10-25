# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # The pull requests a person owes (M4). The `gh` call runs on a thread
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

          busy = @context.busy.call
          subjects = @context.runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }
          @thread = Thread.new { poll(subjects) }
        end

        private

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

          @waiting_on = outcomes.select { it.kind == :waiting }.group_by(&:plan).transform_values { it.map(&:pr) }
          effects = effects_for(@context.runner)
          outcomes.each { apply(effects, it) }
          @state&.waiting_on = @waiting_on
        end

        # Every agent defined, not this run's roster: the mail waits in the
        # plan folder for whichever run next starts the builders, and a run
        # typed with `--agent hansolo-reviewer` must not lose it.
        #
        # @return [PrOutcomes]
        def effects_for(runner)
          PrOutcomes.new(tree_dir: runner.tree.dir, agents: Agents::Registry.new(dir: runner.agents.dir), events: runner.events)
        end

        # @return [void]
        def apply(effects, outcome)
          return if outcome.kind == :waiting || @context.busy.call.include?(outcome.plan)

          applied = effects.apply(outcome) or return
          @context.reopen.call(applied.plan) if applied.to
          @finishes.keep(applied.plan)
          say(applied)
          @context.wake.call
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
