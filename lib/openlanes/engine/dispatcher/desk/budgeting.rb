# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # The dollar cap (plan 062.00): a plan past `budget.plan_usd` gets no
        # new agent, and is held as queued plans are, without a state fired
        # or a folder renamed.
        class Budgeting
          # @param runner [OpenLanes::Engine::Runner]
          # @param budget [OpenLanes::Engine::Budget]
          def initialize(runner:, budget:)
            @runner = runner
            @budget = budget
            @said = {}
          end

          # A query only: {#announce_budget} says it.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @return [String, nil] `over budget: $X of $Y`, or nil when it may run
          def budget_refusal(subject) = @budget.refusal(subject.feature.ordinal.to_s)

          # Says a budget hold once per reason, not on every tick.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @param reason [String, nil] what {#budget_refusal} answered
          # @return [void]
          def announce_budget(subject, reason)
            ordinal = subject.feature.ordinal.to_s
            UI.log("#{reason}; no new round starts", plan: ordinal, level: :warn) if reason && @said[ordinal] != reason
            @said[ordinal] = reason
          end

          # @return [Hash{String => String}] in-scope plans the cap holds, with why
          def budget_holds
            @runner.in_scope.to_h { [it.feature.ordinal.to_s, budget_refusal(it)] }.compact
          end
        end
      end
    end
  end
end
