# frozen_string_literal: true

module OpenLanes
  module Presentation
    class Reporter
      # The table's Spend cell (decision C11): what a plan has spent, with its
      # cap when `budget.plan_usd` sets one, e.g. `$3.20 / $25.00`. The web
      # board shows the same {Events::PlanSpend}, read through the same
      # {Engine::Budget}, so the two cannot count a plan differently.
      class Spend
        # @param budget [OpenLanes::Engine::Budget]
        def initialize(budget)
          @budget = budget
          @spends = {}
        end

        # Blank for a plan nothing has been spent on, so an archive of plans
        # built before the log existed does not read as a column of zeros.
        #
        # @param ordinal [String, #to_s]
        # @return [String]
        def text(ordinal)
          spend = of(ordinal)
          return "" if spend.nil? || (spend.usd.zero? && spend.unpriced_runs.zero?)

          [spend.dollars(spend.usd), (spend.dollars(spend.cap) if spend.cap)].compact.join(" / ")
        end

        # @param ordinal [String, #to_s]
        # @return [Symbol] red once the plan has reached its cap
        def colour(ordinal) = of(ordinal)&.over? ? :red : :green

        private

        # Read once per plan: the width pass and the row both ask. A cap that
        # cannot be read shows nothing rather than failing the table.
        #
        # @param ordinal [String, #to_s]
        # @return [OpenLanes::Events::PlanSpend, nil]
        def of(ordinal)
          key = ordinal.to_s
          @spends.fetch(key) do
            @spends[key] = begin
              @budget.spend(key)
            rescue Error
              nil
            end
          end
        end
      end
    end
  end
end
