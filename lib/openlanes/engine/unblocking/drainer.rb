# frozen_string_literal: true

module OpenLanes
  module Engine
    module Unblocking
      # Each answer set is tried once; a failed drain waits for `blocked.md`
      # to change. Drains finished since the last tick are settled first, so
      # the plan is picked up again in this run.
      class Drainer
        include Enumerable

        # @param context [Steps::Context]
        # @param settler [Settler]
        def initialize(context, settler:)
          @context = context
          @settler = settler
          @drains = []
          @tried = {}
        end

        # @yieldparam drain [Drain] each drain under way
        def each(&) = @drains.each(&)

        # @return [Boolean] whether nothing is being drained
        def empty? = @drains.empty?

        # @return [Hash{String => String}] see {Settler#failures}
        def failures = @settler.failures

        # @return [void]
        def call
          @drains.reject { it.thread.alive? }.each { settle(it) }
          runner = @context.runner
          return if runner.dry_run? || Execution::Control.quit? || Execution::Control.paused?

          blocked = runner.blocked
          return if blocked.empty?

          busy = @context.busy.call
          blocked.each { consider(it, busy) }
        end

        private

        # @return [void]
        def settle(drain)
          @drains.delete(drain)
          @settler.call(drain)
        end

        # @return [void]
        def consider(subject, busy)
          ordinal = subject.feature.ordinal.to_s
          return if busy.include?(ordinal) || !answered?(subject)

          answers = subject.read("blocked.md")
          return if @tried[ordinal] == answers

          agent = broker_for(subject) or return
          return unless @context.runner.claim(subject)

          @tried[ordinal] = answers
          start(agent, subject)
        end

        # @return [Boolean]
        def answered?(subject)
          questions = Lifecycle::Unblocker.questions(subject)
          !questions.empty? && questions.all?(&:answered)
        end

        # The drainer advances nothing itself, so {Agents::Registry#for_status},
        # which offers only agents that move a plan on, never names it. A 💤
        # the aging sweep made is drained as the ⭕ it was: no agent handles
        # 💤, so asking for its own state found no broker (issue 168).
        #
        # @return [Agents::Agent, nil]
        def broker_for(subject)
          status = Lifecycle.aged_out?(subject) ? Plans.status(:blocked) : subject.status
          registry.all.find { it.handles?(status) }
        end

        # Every agent the run's definitions hold, not the run's roster: the
        # roster says who builds, and drawing the broker from it left every
        # answered plan undrained under `run --agent X` or `--skip unblocker`,
        # with nothing said (issue 176).
        #
        # @return [Agents::Registry]
        def registry = @registry ||= Agents::Registry.new(dir: @context.runner.agents.dir)

        # @return [void]
        def start(agent, subject)
          ordinal = subject.feature.ordinal.to_s
          @settler.forget(ordinal)
          UI.log("unblocking: every question answered", plan: ordinal, agent: agent.name)
          drain = drain_for(agent, subject)
          drain.thread = spawn(drain, unblocker_for(agent), subject)
          @drains << drain
        end

        # @return [Drain] not yet started
        def drain_for(agent, subject)
          Drain.new(ordinal: subject.feature.ordinal.to_s,
            agent: agent.name,
            rounds: Plans::PlanState.for(subject.feature.path).journal(agent.name).size)
        end

        # @return [Lifecycle::Unblocker]
        def unblocker_for(agent)
          runner = @context.runner
          Lifecycle::Unblocker.new(tree: Plans::Tree.new(dir: runner.tree.dir),
            agent:,
            executor: runner.executor,
            commit: true,
            events: runner.events)
        end

        # @return [Thread]
        def spawn(drain, unblocker, subject)
          Thread.new do
            Thread.current.report_on_exception = false
            drain.outcome = begin
              unblocker.drain(subject)
            rescue StandardError => e
              e
            end
          end
        end
      end
    end
  end
end
